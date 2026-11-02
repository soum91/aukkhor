package dev.soum91.aukkhor.tv;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.Looper;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.text.InputType;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;

import java.io.*;
import java.math.BigInteger;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.security.cert.X509Certificate;
import java.util.*;
import java.util.concurrent.*;
import javax.crypto.*;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import javax.net.ssl.*;
import javax.security.auth.x500.X500Principal;
import org.json.JSONObject;

/**
 * Local-only, pinned HTTPS receiver. A six-digit code pairs a phone,
 * then HMAC challenge/response authenticates every short-lived bearer session.
 * Only the currently focused, non-password editor can receive committed text.
 * No keylogging or background reading of TV fields.
 */
public final class TVBridgeServer implements AutoCloseable {
    public static final int PORT = 45790;
    private static final String PREFS = "aukkhor_tv";
    private static final String TLS_ALIAS = "aukkhor-tv-https-v1";
    private static final String SECRET_ALIAS = "aukkhor-tv-secret-v1";
    private final Handler main = new Handler(Looper.getMainLooper());
    private final SharedPreferences prefs;
    private final ExecutorService workers = Executors.newFixedThreadPool(4);
    private final Map<String,Long> challenges = new ConcurrentHashMap<>();
    private final Map<String,Long> bearer = new ConcurrentHashMap<>();
    private final SecureRandom random = new SecureRandom();
    private final String id;
    private final String secret;
    private SSLServerSocket server;
    private volatile boolean running;
    private volatile AukkhorIME ime;
    private volatile String fieldSession = "";
    private volatile String fieldLabel = "";
    private volatile boolean fieldAvailable = false;
    private volatile long fieldTimestamp = 0L;
    private volatile String pairingCode;
    private volatile long pairingUntil;
    private volatile int failedPairings;

    public TVBridgeServer(Context ctx) throws Exception {
        prefs = ctx.getApplicationContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        id = persistedRandom("id", 16);
        secret = persistedRandom("secret", 32);
        rotatePairing();
        SSLContext tls = SSLContext.getInstance("TLS");
        KeyStore ks = KeyStore.getInstance("AndroidKeyStore");
        ks.load(null);
        if (!ks.containsAlias(TLS_ALIAS)) {
            KeyPairGenerator g = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_RSA, "AndroidKeyStore");
            g.initialize(new KeyGenParameterSpec.Builder(TLS_ALIAS, KeyProperties.PURPOSE_SIGN | KeyProperties.PURPOSE_VERIFY)
                .setKeySize(2048)
                .setDigests(KeyProperties.DIGEST_SHA256)
                .setSignaturePaddings(KeyProperties.SIGNATURE_PADDING_RSA_PKCS1)
                .setCertificateSubject(new X500Principal("CN=Aukkhor TV"))
                .setCertificateSerialNumber(BigInteger.valueOf(45790))
                .setCertificateNotBefore(new Date(System.currentTimeMillis() - 86400000L))
                .setCertificateNotAfter(new Date(System.currentTimeMillis() + 5L * 365 * 86400000L))
                .build());
            g.generateKeyPair();
        }
        KeyManagerFactory km = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
        km.init(ks, null);
        tls.init(km.getKeyManagers(), null, new SecureRandom());
        server = (SSLServerSocket) tls.getServerSocketFactory().createServerSocket();
        server.setReuseAddress(true);
        // The TV is on a trusted home LAN; TLS + fingerprint confirmation + pairing is mandatory.
        server.bind(new InetSocketAddress(PORT));
        server.setEnabledProtocols(new String[] {"TLSv1.2", "TLSv1.3"});
    }

    private static String hex(byte[] bytes) {
        char[] letters = "0123456789ABCDEF".toCharArray();
        char[] chars = new char[bytes.length * 2];
        for (int i=0; i<bytes.length; i++) { chars[2*i]=letters[(bytes[i] >> 4)&15]; chars[2*i+1]=letters[bytes[i]&15]; }
        return new String(chars);
    }
    private String randomHex(int bytes) {
        byte[] a = new byte[bytes]; random.nextBytes(a); return hex(a);
    }
    private String persistedRandom(String key, int bytes) throws Exception {
        String data = prefs.getString(key, "");
        if (!data.isEmpty()) {
            try { return new String(decrypt(Base64.getDecoder().decode(data)), StandardCharsets.US_ASCII); }
            catch (Exception ignored) { /* wiped Keystore: force re-pairing */ }
        }
        String value = randomHex(bytes);
        prefs.edit().putString(key, Base64.getEncoder().encodeToString(encrypt(value.getBytes(StandardCharsets.US_ASCII)))).apply();
        return value;
    }
    private SecretKey vaultKey() throws Exception {
        KeyStore ks = KeyStore.getInstance("AndroidKeyStore"); ks.load(null);
        if (!ks.containsAlias(SECRET_ALIAS)) {
            KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
            generator.init(new KeyGenParameterSpec.Builder(SECRET_ALIAS, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build());
            generator.generateKey();
        }
        return ((KeyStore.SecretKeyEntry) ks.getEntry(SECRET_ALIAS, null)).getSecretKey();
    }
    private byte[] encrypt(byte[] data) throws Exception {
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, vaultKey());
        byte[] iv=cipher.getIV(), result=cipher.doFinal(data), out=new byte[iv.length+result.length];
        System.arraycopy(iv,0,out,0,iv.length); System.arraycopy(result,0,out,iv.length,result.length); return out;
    }
    private byte[] decrypt(byte[] data) throws Exception {
        if(data.length<29) throw new IllegalArgumentException("Invalid vault");
        Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE,vaultKey(),new GCMParameterSpec(128,Arrays.copyOf(data,12)));
        return cipher.doFinal(Arrays.copyOfRange(data,12,data.length));
    }
    public String fingerprint() throws Exception {
        KeyStore ks=KeyStore.getInstance("AndroidKeyStore"); ks.load(null);
        X509Certificate cert=(X509Certificate)ks.getCertificate(TLS_ALIAS);
        return hex(MessageDigest.getInstance("SHA-256").digest(cert.getEncoded()));
    }
    private synchronized void rotatePairing() {
        pairingCode = String.format(Locale.US,"%06d",random.nextInt(1_000_000));
        pairingUntil=System.currentTimeMillis()+900000L;
        failedPairings=0;
    }
    public synchronized String pairingCode() {
        if(System.currentTimeMillis()>pairingUntil) rotatePairing();
        return pairingCode;
    }
    public synchronized void resetPairing() { rotatePairing(); }

    public void start() {
        running=true;
        Thread listener=new Thread(()->{
            while(running) {
                try {
                    SSLSocket socket=(SSLSocket)server.accept();
                    socket.setSoTimeout(6000);
                    workers.submit(()->handle(socket));
                } catch(IOException e) { if(running) android.util.Log.w("AukkhorTV","Socket listener",e); }
            }
        },"Aukkhor-TV-TLS");
        listener.setDaemon(true);
        listener.start();
    }

    public void editorOpened(AukkhorIME service, EditorInfo info) {
        int kind=info.inputType & InputType.TYPE_MASK_CLASS;
        int variation=info.inputType & InputType.TYPE_MASK_VARIATION;
        boolean sensitive=kind==InputType.TYPE_CLASS_TEXT && (variation==InputType.TYPE_TEXT_VARIATION_PASSWORD
            || variation==InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
            || variation==InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD)
            || kind==InputType.TYPE_CLASS_NUMBER && variation==InputType.TYPE_NUMBER_VARIATION_PASSWORD;
        ime=service;
        fieldAvailable=!sensitive && info.inputType!=InputType.TYPE_NULL;
        fieldSession=fieldAvailable?randomHex(12):"";
        String app=info.packageName==null?"TV app":info.packageName;
        fieldLabel=app.length()>70?app.substring(0,70):app;
        fieldTimestamp=System.currentTimeMillis();
    }
    public void editorClosed(AukkhorIME service) {
        if(ime==service) { fieldAvailable=false; fieldSession=""; ime=null; }
    }
    private String mac(String nonce) throws Exception {
        Mac h=Mac.getInstance("HmacSHA256");
        h.init(new SecretKeySpec(hexToBytes(secret),"HmacSHA256"));
        return hex(h.doFinal(nonce.getBytes(StandardCharsets.US_ASCII)));
    }
    private static byte[] hexToBytes(String hex) {
        byte[] out=new byte[hex.length()/2];
        for(int i=0;i<out.length;i++)out[i]=(byte)Integer.parseInt(hex.substring(i*2,i*2+2),16);
        return out;
    }
    private void handle(SSLSocket client) {
        try(client) {
            client.startHandshake();
            InputStream in=client.getInputStream();
            String first=readLine(in,512);
            if(first==null)return;
            String[] parts=first.split(" ");
            if(parts.length!=3 || !parts[2].equals("HTTP/1.1")) {respond(client,400,"Bad request");return;}
            String method=parts[0],path=parts[1];
            Map<String,String> headers=new HashMap<>();
            for(int i=0;i<25;i++){
                String row=readLine(in,1024);
                if(row==null){respond(client,400,"Bad headers");return;}
                if(row.isEmpty())break;
                int col=row.indexOf(':');
                if(col<=0){respond(client,400,"Bad headers");return;}
                headers.put(row.substring(0,col).trim().toLowerCase(Locale.US),row.substring(col+1).trim());
            }
            int length;
            try {length=Integer.parseInt(headers.getOrDefault("content-length","0"));} catch(NumberFormatException e){respond(client,400,"Length required");return;}
            if(length<0 || length>8192){respond(client,413,"Too large");return;}
            byte[] body=new byte[length];
            int offset=0;
            while(offset<length){int n=in.read(body,offset,length-offset);if(n<0)break;offset+=n;}
            if(offset!=length){respond(client,400,"Short request");return;}
            long now=System.currentTimeMillis();
            challenges.entrySet().removeIf(e->e.getValue()<now);
            bearer.entrySet().removeIf(e->e.getValue()<now);
            if(method.equals("POST")&&path.equals("/pair")){
                String supplied=headers.getOrDefault("x-aukkhor-code","");
                boolean valid;
                synchronized(this){
                    valid=failedPairings<10 && now<pairingUntil && supplied.equals(pairingCode);
                    if(!valid) failedPairings++;
                    else rotatePairing();
                }
                if(!valid){respond(client,403,"Invalid pairing code");return;}
                respond(client,200,new JSONObject().put("id",id).put("secret",secret).toString());return;
            }
            if(method.equals("GET")&&path.equals("/challenge")){
                String nonce=randomHex(24);
                challenges.put(nonce,now+60000L);
                respond(client,200,new JSONObject().put("id",id).put("nonce",nonce).toString());return;
            }
            if(method.equals("POST")&&path.equals("/reconnect")){
                String proof=headers.getOrDefault("x-aukkhor-proof","");
                boolean valid=false;
                for(String nonce:challenges.keySet()){
                    if(proof.length()==64 && MessageDigest.isEqual(mac(nonce).getBytes(StandardCharsets.US_ASCII),
                            proof.toUpperCase(Locale.US).getBytes(StandardCharsets.US_ASCII))){
                        valid=challenges.remove(nonce)!=null;break;
                    }
                }
                if(!valid){respond(client,403,"Authentication failed");return;}
                String token=randomHex(24);
                bearer.put(token,now+600000L);
                respond(client,200,token);return;
            }
            String authorization=headers.getOrDefault("authorization","");
            String token=authorization.startsWith("Bearer ")?authorization.substring(7):"";
            if(!bearer.containsKey(token)){respond(client,403,"Pair your iPhone");return;}
            if(method.equals("GET")&&path.equals("/prompt")){
                boolean ready=fieldAvailable && (now-fieldTimestamp)<600000 && ime!=null;
                respond(client,200,new JSONObject().put("active",ready).put("session",ready?fieldSession:"")
                    .put("label",ready?fieldLabel:"").toString());return;
            }
            if(method.equals("POST")&&path.equals("/type")){
                String target=headers.getOrDefault("x-aukkhor-session","");
                String text=new String(body,StandardCharsets.UTF_8);
                if(!fieldAvailable || !target.equals(fieldSession) || text.codePointCount(0,text.length())>2048
                    || text.indexOf('\u0000')!=-1 || ime==null){respond(client,409,"Field changed or unavailable");return;}
                CountDownLatch applied=new CountDownLatch(1);
                final boolean[] ok={false};
                main.post(()->{
                    AukkhorIME current=ime;
                    if(current!=null && fieldAvailable && target.equals(fieldSession)){
                        ok[0]=current.commitRemoteText(text);
                    }
                    applied.countDown();
                });
                if(!applied.await(3,TimeUnit.SECONDS)){respond(client,503,"TV busy");return;}
                respond(client,ok[0]?200:409,ok[0]?"OK":"Focus lost");return;
            }
            respond(client,404,"Not found");
        } catch(Exception e){android.util.Log.w("AukkhorTV","Connection terminated: "+e.getClass().getSimpleName());}
    }
    private static String readLine(InputStream in,int limit)throws IOException{
        ByteArrayOutputStream buf=new ByteArrayOutputStream();
        for(int i=0;i<limit;i++){
            int b=in.read();if(b<0)return null;
            if(b=='\n')return buf.toString("UTF-8").replace("\r","");
            buf.write(b);
        }
        throw new IOException("Oversized header");
    }
    private static void respond(SSLSocket client,int status,String text)throws IOException{
        byte[] bytes=text.getBytes(StandardCharsets.UTF_8);
        String reason=status==200?"OK":status==403?"Forbidden":status==409?"Conflict":"Error";
        String contentType=text.startsWith("{")?"application/json":"text/plain";
        String header="HTTP/1.1 "+status+" "+reason+"\r\nContent-Type: "+contentType+"; charset=utf-8\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nContent-Length: "+bytes.length+"\r\nConnection: close\r\n\r\n";
        client.getOutputStream().write(header.getBytes(StandardCharsets.US_ASCII));
        client.getOutputStream().write(bytes);
        client.getOutputStream().flush();
    }
    @Override public void close() throws IOException {
        running=false;
        fieldAvailable=false;
        if(server!=null)server.close();
        workers.shutdownNow();
    }
}
