package dev.soum91.aukkhor.tv;

import android.app.*;
import android.content.*;
import android.graphics.*;
import android.graphics.drawable.GradientDrawable;
import android.net.wifi.WifiManager;
import android.os.*;
import android.provider.Settings;
import android.view.*;
import android.view.inputmethod.InputMethodManager;
import android.widget.*;
import java.net.*;
import java.util.*;

/**
 * Fully D-pad usable setup page. Displays pairing info only on the TV.
 * Does not expose codes or trust secrets through a public exported activity.
 */
public final class TVActivity extends Activity {
    private LinearLayout content;
    private TextView status,deviceCode,fingerprint,ipAddress;
    private final Handler handler=new Handler(Looper.getMainLooper());
    private final Runnable refresh=new Runnable(){
        public void run(){update();handler.postDelayed(this,2000);}
    };
    @Override public void onCreate(Bundle state){
        super.onCreate(state);
        getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LAYOUT_STABLE);
        ScrollView scroll=new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(Color.rgb(11,18,35));
        content=new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(55,32,55,40);
        scroll.addView(content);setContentView(scroll);
        title("Aukkhor  •  অক্ষর",34,Color.rgb(101,208,255));
        title("Type on your iPhone whenever a text field opens on Google TV",20,Color.WHITE);
        status=title("Bridge status: starting",18,Color.rgb(255,203,117));
        button("1. Start / keep receiver running",()->startReceiver());
        button("2. Enable the Aukkhor TV keyboard",()->startActivity(new Intent(Settings.ACTION_INPUT_METHOD_SETTINGS)));
        button("3. Select Aukkhor TV keyboard",()->{
            InputMethodManager imm=(InputMethodManager)getSystemService(INPUT_METHOD_SERVICE);
            imm.showInputMethodPicker();
        });
        title("LOCAL NETWORK PAIRING",21,Color.rgb(101,208,255));
        title("Pair on a private home network. Compare the full fingerprint before entering the code.",16,Color.LTGRAY);
        ipAddress=title("TV address: ...",20,Color.WHITE);
        deviceCode=title("Pairing code: ...",25,Color.WHITE);
        fingerprint=title("SHA-256 fingerprint: ...",16,Color.LTGRAY);
        button("New pairing code",()->{
            TVBridgeService s=TVBridgeService.instance();
            if(s!=null && s.bridge()!=null){s.bridge().resetPairing();update();}
        });
        title("On iPhone: Aukkhor → TV companion → enter TV IP, fingerprint and pairing code.",17,Color.LTGRAY);
        title("When a TV text field appears, keep Aukkhor open on iPhone for the automatic typing sheet. The TV cannot wake a suspended iPhone by local Wi-Fi alone.",16,Color.LTGRAY);
        title("Android TV keyboard features: D-pad navigation, English, Bangla, number/symbols, Delete, Space and Done. Secure password fields never accept remote text.",16,Color.LTGRAY);
        startReceiver();
    }
    private TextView title(String message,int size,int color){
        TextView label=new TextView(this);
        label.setText(message);label.setTextSize(size);label.setTextColor(color);
        label.setPadding(4,8,4,8);
        content.addView(label);return label;
    }
    private void button(String text,Runnable action){
        Button button=new Button(this);button.setText(text);button.setAllCaps(false);
        button.setTextSize(17);button.setOnClickListener(v->action.run());
        LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,65);lp.setMargins(0,5,0,5);
        content.addView(button,lp);
    }
    private void startReceiver(){
        if(TVBridgeService.instance()==null){
            Intent i=new Intent(this,TVBridgeService.class);
            try{startForegroundService(i);}catch(RuntimeException e){status.setText("Cannot start bridge: "+e.getMessage());}
        }
        handler.postDelayed(this::update,500);
    }
    private String localAddress(){
        try{
            Enumeration<NetworkInterface> interfaces=NetworkInterface.getNetworkInterfaces();
            while(interfaces.hasMoreElements()){
                NetworkInterface nic=interfaces.nextElement();
                if(!nic.isUp()||nic.isLoopback())continue;
                Enumeration<InetAddress> addresses=nic.getInetAddresses();
                while(addresses.hasMoreElements()){
                    InetAddress address=addresses.nextElement();
                    if(address instanceof Inet4Address && address.isSiteLocalAddress())return address.getHostAddress();
                }
            }
        }catch(Exception ignored){}
        return "No private IPv4 found";
    }
    private void update(){
        if(isFinishing())return;
        TVBridgeService service=TVBridgeService.instance();
        TVBridgeServer bridge=service==null?null:service.bridge();
        ipAddress.setText("TV IP and port: "+localAddress()+":"+TVBridgeServer.PORT);
        if(bridge==null){
            status.setText("Receiver unavailable "+(service==null?"":service.error()));
            deviceCode.setText("Open app and start receiver");
            fingerprint.setText("");
            return;
        }
        status.setText("Receiver running • enable/select keyboard above");
        deviceCode.setText("Pairing code: "+bridge.pairingCode());
        try{fingerprint.setText("Certificate SHA-256:\n"+bridge.fingerprint());}
        catch(Exception e){fingerprint.setText("Certificate unavailable: "+e.getMessage());}
    }
    @Override public void onResume(){super.onResume();handler.post(refresh);}
    @Override public void onPause(){handler.removeCallbacks(refresh);super.onPause();}
}
