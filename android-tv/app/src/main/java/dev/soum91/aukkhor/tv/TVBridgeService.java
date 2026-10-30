package dev.soum91.aukkhor.tv;

import android.app.*;
import android.content.*;
import android.os.*;
import android.view.inputmethod.EditorInfo;

/**
 * User-started persistent bridge. A selected IME reports focus to this service.
 * The foreground notification makes its running status visible on Google TV.
 */
public final class TVBridgeService extends Service {
    private static final String CHANNEL="aukkhor.bridge";
    private static volatile TVBridgeService current;
    private TVBridgeServer bridge;
    private String error;

    public static TVBridgeService instance(){return current;}
    public TVBridgeServer bridge(){return bridge;}
    public String error(){return error;}
    @Override public void onCreate(){
        super.onCreate();
        current=this;
        NotificationChannel channel=new NotificationChannel(CHANNEL,"Aukkhor iPhone keyboard bridge",NotificationManager.IMPORTANCE_LOW);
        ((NotificationManager)getSystemService(NOTIFICATION_SERVICE)).createNotificationChannel(channel);
        startForeground(1001,makeNotification("Preparing keyboard receiver"));
        try {
            bridge=new TVBridgeServer(this);
            bridge.start();
            updateNotification("Ready for paired iPhone");
        } catch(Exception e){
            error=e.getMessage();
            updateNotification("Bridge unavailable: "+error);
        }
    }
    private Notification makeNotification(String status){
        Intent intent=new Intent(this,TVActivity.class);
        PendingIntent pending=PendingIntent.getActivity(this,100,intent,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
        return new Notification.Builder(this,CHANNEL)
            .setSmallIcon(android.R.drawable.ic_menu_edit)
            .setContentTitle("Aukkhor TV keyboard")
            .setContentText(status)
            .setOngoing(true)
            .setContentIntent(pending)
            .build();
    }
    private void updateNotification(String status){
        ((NotificationManager)getSystemService(NOTIFICATION_SERVICE)).notify(1001,makeNotification(status));
    }
    void editorOpened(AukkhorIME ime,EditorInfo info){
        if(bridge!=null){
            bridge.editorOpened(ime,info);
            updateNotification("Text field detected • iPhone can type");
        }
    }
    void editorClosed(AukkhorIME ime){
        if(bridge!=null){bridge.editorClosed(ime);updateNotification("Ready for paired iPhone");}
    }
    @Override public int onStartCommand(Intent intent,int flags,int startId){return START_STICKY;}
    @Override public IBinder onBind(Intent intent){return null;}
    @Override public void onDestroy(){
        current=null;
        if(bridge!=null)try{bridge.close();}catch(Exception ignored){}
        super.onDestroy();
    }
}
