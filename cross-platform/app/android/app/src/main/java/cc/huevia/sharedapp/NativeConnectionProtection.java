package cc.huevia.sharedapp;

import android.Manifest;
import android.app.Activity;
import android.content.*;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.*;
import android.provider.Settings;
import cc.huevia.library.SharedJson;
import cc.huevia.shared.SharedRuntime;
import io.flutter.embedding.engine.*;
import io.flutter.plugin.common.*;
import java.lang.ref.WeakReference;

/** Retains the existing Flutter/native owner only while explicit camera work runs. */
final class NativeConnectionProtection implements MethodChannel.MethodCallHandler,EventChannel.StreamHandler {
    static final String ENGINE="huevia-camera-background";
    private static WeakReference<NativeConnectionProtection> current=new WeakReference<>(null);
    private static MainActivity retainedHost;
    private static FlutterEngine retainedEngine;
    private static boolean active,attached=true;
    private static String warning="";
    private static long stopRevision;
    private static long serviceRevision,lastServiceStop=-1;
    private final MainActivity activity;
    private final FlutterEngine engine;
    private EventChannel.EventSink events;
    private MethodChannel.Result pending;
    NativeConnectionProtection(MainActivity activity,FlutterEngine engine){
        if(retainedEngine!=null&&retainedEngine!=engine){MainActivity oldHost=retainedHost;FlutterEngine oldEngine=retainedEngine;retainedHost=null;retainedEngine=null;FlutterEngineCache.getInstance().remove(ENGINE);NativeConnectionProtection old=current.get();if(old!=null)old.events=null;if(oldHost!=null)oldHost.retireRetainedBackend();oldEngine.destroy();}
        this.activity=activity;this.engine=engine;NativeConnectionProtection prior=current.get();if(prior!=null)events=prior.events;current=new WeakReference<>(this);attached=true;
        if(active&&retainedEngine==engine)retainedHost=activity;
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),"cc.huevia/connection-protection").setMethodCallHandler(this);
        new EventChannel(engine.getDartExecutor().getBinaryMessenger(),"cc.huevia/connection-protection-events").setStreamHandler(this);
    }
    static MainActivity previousHost(FlutterEngine engine){return engine!=null&&engine==retainedEngine&&keepEngine()?retainedHost:null;}
    static FlutterEngine cachedEngine(){return keepEngine()?FlutterEngineCache.getInstance().get(ENGINE):null;}
    static boolean keepEngine(){return (CameraRetentionService.running||CameraRetentionService.requested)&&active&&retainedEngine!=null;}
    static boolean wanted(Context context){return active&&context.getSharedPreferences("camera-protection",0).getBoolean("enabled",false);}
    static long serviceRevision(){return serviceRevision;}
    static long lastServiceStop(){return lastServiceStop;}
    private boolean enabled(){return activity.getSharedPreferences("camera-protection",0).getBoolean("enabled",false);}
    private String status(){PowerManager power=activity.getSystemService(PowerManager.class);return SharedJson.encode(SharedRuntime.map("available",true,"enabled",enabled(),"running",CameraRetentionService.running,"backgroundAllowed",enabled()&&active&&CameraRetentionService.running,"limited",false,"batteryExempt",power.isIgnoringBatteryOptimizations(activity.getPackageName()),"warning",warning,"stopRevision",stopRevision));}
    boolean maintenanceAllowed(){return enabled()&&active&&CameraRetentionService.running;}
    private void emit(){activity.updateCameraMaintenance();EventChannel.EventSink sink=events;if(sink!=null)try{sink.success(status());}catch(RuntimeException detached){events=null;}}
    @Override public void onListen(Object arguments,EventChannel.EventSink sink){events=sink;emit();}
    @Override public void onCancel(Object arguments){events=null;}
    @Override public void onMethodCall(MethodCall call,MethodChannel.Result reply){
        if(call.method.equals("status")||call.method.equals("foreground")){reply.success(status());return;}
        if(call.method.equals("batterySettings")){try{activity.startActivity(new Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS));reply.success(status());}catch(RuntimeException unavailable){reply.error("SETTINGS_UNAVAILABLE","系统电池设置暂不可用。",null);}return;}
        if(!call.method.equals("set")){reply.notImplemented();return;}
        Object enable=call.argument("enabled"),work=call.argument("active");
        if(enable!=null&&!(enable instanceof Boolean)||work!=null&&!(work instanceof Boolean)){reply.error("INVALID_ARGUMENT","连接保护设置无效。",null);return;}
        if(Boolean.TRUE.equals(enable)&&Build.VERSION.SDK_INT>=33&&activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED){
            if(pending!=null){reply.error("BUSY","请完成通知权限选择。",null);return;}
            pending=reply;activity.requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS},49324);return;
        }
        if(enable instanceof Boolean)activity.getSharedPreferences("camera-protection",0).edit().putBoolean("enabled",(Boolean)enable).commit();
        if(work instanceof Boolean)active=(Boolean)work;apply();reply.success(status());
    }
    void permissionResult(){MethodChannel.Result reply=pending;pending=null;if(reply==null)return;boolean granted=Build.VERSION.SDK_INT<33||activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)==PackageManager.PERMISSION_GRANTED;activity.getSharedPreferences("camera-protection",0).edit().putBoolean("enabled",granted).commit();warning=granted?"":"需要允许通知，才能开启可见的后台接收保护。";apply();reply.success(status());}
    private void apply(){
        if(wanted(activity)){
            warning="";retainedHost=activity;retainedEngine=engine;FlutterEngineCache.getInstance().put(ENGINE,engine);CameraRetentionService.requested=true;
            try{activity.startForegroundService(new Intent(activity,CameraRetentionService.class).putExtra("generation",++serviceRevision));}catch(RuntimeException failure){failed(failure);}
        }else {lastServiceStop=++serviceRevision;CameraRetentionService.markStopping(lastServiceStop);activity.stopService(new Intent(activity,CameraRetentionService.class));}
        emit();
    }
    void detached(){if(current.get()==this)attached=false;if(pending!=null){pending.error("CANCELLED","通知权限选择已取消。",null);pending=null;}}
    static void userStopped(){++stopRevision;NativeConnectionProtection value=current.get();if(value!=null){value.activity.getSharedPreferences("camera-protection",0).edit().putBoolean("enabled",false).commit();warning="已从通知停止接收，队列保留在本机。";value.activity.stopCameraWork();value.emit();}active=false;}
    static void failed(RuntimeException failure){warning="系统未允许后台连接保护，请保持应用前台并查看电池设置。";active=false;CameraRetentionService.requested=false;serviceStopped(Long.MAX_VALUE);}
    static void serviceChanged(){NativeConnectionProtection value=current.get();if(value!=null)value.emit();}
    static void serviceStopped(long stoppedGeneration){
        NativeConnectionProtection value=current.get();
        if(value!=null&&wanted(value.activity)&&serviceRevision>stoppedGeneration&&retainedEngine!=null){
            CameraRetentionService.requested=true;
            try{value.activity.startForegroundService(new Intent(value.activity,CameraRetentionService.class).putExtra("generation",serviceRevision));return;}catch(RuntimeException failure){warning="后台连接保护重启未完成，请保持应用前台。";}
        }
        active=false;
        CameraRetentionService.requested=false;if(value!=null)value.emit();
        if(!attached&&retainedHost!=null){MainActivity host=retainedHost;FlutterEngine old=retainedEngine;retainedHost=null;retainedEngine=null;FlutterEngineCache.getInstance().remove(ENGINE);if(value!=null)value.events=null;host.releaseRetainedBackend();if(old!=null)old.destroy();}
        else{retainedHost=null;retainedEngine=null;FlutterEngineCache.getInstance().remove(ENGINE);}
    }
}
