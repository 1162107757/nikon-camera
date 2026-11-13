package cc.huevia.sharedapp;

import android.app.*;
import android.content.*;
import android.content.pm.ServiceInfo;
import android.net.wifi.WifiManager;
import android.os.*;

/** User-visible connected-device work, never an invisible/boot-started service. */
public final class CameraRetentionService extends Service {
    static final String STOP="cc.huevia.next.CAMERA_STOP";
    static volatile boolean running;
    static volatile boolean requested;
    private static CameraRetentionService instance;
    private long generation,stoppedGeneration=-1;
    static void markStopping(long generation){if(instance!=null)instance.stoppedGeneration=generation;}
    static long currentGeneration(){return instance==null?-1:instance.generation;}
    private PowerManager.WakeLock wake;
    private WifiManager.WifiLock wifi;
    private final Handler handler=new Handler(Looper.getMainLooper());
    private final Runnable renew=new Runnable(){public void run(){if(!running)return;hold();handler.postDelayed(this,5*60*1000);}};
    @Override public void onCreate(){super.onCreate();instance=this;NotificationManager notifications=getSystemService(NotificationManager.class);notifications.createNotificationChannel(new NotificationChannel("camera-transfer","相机接收与连接",NotificationManager.IMPORTANCE_LOW));}
    @Override public int onStartCommand(Intent intent,int flags,int id){
        if(intent!=null&&STOP.equals(intent.getAction())){NativeConnectionProtection.userStopped();stopSelf();return START_NOT_STICKY;}
        long requestedGeneration=intent==null?NativeConnectionProtection.serviceRevision():intent.getLongExtra("generation",NativeConnectionProtection.serviceRevision());
        generation=Math.max(generation,requestedGeneration);
        if(requestedGeneration<=NativeConnectionProtection.lastServiceStop())stoppedGeneration=Math.max(stoppedGeneration,NativeConnectionProtection.lastServiceStop());
        if(!NativeConnectionProtection.wanted(this)){stopSelf();return START_NOT_STICKY;}
        PendingIntent open=PendingIntent.getActivity(this,501,new Intent(this,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
        PendingIntent stop=PendingIntent.getService(this,502,new Intent(this,CameraRetentionService.class).setAction(STOP),PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
        Notification notification=new Notification.Builder(this,"camera-transfer").setSmallIcon(android.R.drawable.stat_sys_download).setContentTitle("相机照片接收")
                .setContentText("保留连接与任务进度；可随时停止").setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true)
                .addAction(new Notification.Action.Builder(null,"停止接收",stop).build()).build();
        try{
            if(Build.VERSION.SDK_INT>=29)startForeground(21501,notification,ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE);else startForeground(21501,notification);
            running=true;requested=false;hold();handler.removeCallbacks(renew);handler.postDelayed(renew,5*60*1000);NativeConnectionProtection.serviceChanged();
        }catch(RuntimeException unavailable){NativeConnectionProtection.failed(unavailable);stopSelf();}
        return START_NOT_STICKY;
    }
    private void hold(){
        try{if(wake==null)wake=getSystemService(PowerManager.class).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK,getPackageName()+":camera-transfer");if(wake.isHeld())wake.release();wake.acquire(10*60*1000L);}catch(RuntimeException ignored){}
        try{if(wifi==null)wifi=((WifiManager)getApplicationContext().getSystemService(Context.WIFI_SERVICE)).createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF,getPackageName()+":camera-transfer");if(!wifi.isHeld())wifi.acquire();}catch(RuntimeException ignored){}
    }
    @Override public void onDestroy(){boolean current=instance==this;if(current){instance=null;running=false;}handler.removeCallbacks(renew);try{if(wake!=null&&wake.isHeld())wake.release();}catch(RuntimeException ignored){}try{if(wifi!=null&&wifi.isHeld())wifi.release();}catch(RuntimeException ignored){}stopForeground(STOP_FOREGROUND_REMOVE);if(current)NativeConnectionProtection.serviceStopped(stoppedGeneration>=0?stoppedGeneration:generation);super.onDestroy();}
    @Override public IBinder onBind(Intent intent){return null;}
}
