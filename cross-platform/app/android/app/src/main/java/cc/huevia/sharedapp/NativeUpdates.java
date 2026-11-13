package cc.huevia.sharedapp;

import android.app.Activity;
import android.content.ClipData;
import android.content.Intent;
import android.net.Uri;
import android.provider.Settings;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;
import java.util.LinkedHashMap;
import java.util.Map;

/** Reuses the production updater and its package/signature verification without its original UI. */
public final class NativeUpdates implements AutoCloseable {
    private final Activity host;
    private final NextAppUpdateManager manager;
    private EventChannel.EventSink events;
    private boolean resumed=true,closed;
    private long installEpoch;
    public NativeUpdates(Activity host,BinaryMessenger messenger){
        this.host=host;
        manager=new NextAppUpdateManager(host,new NextAppUpdateManager.Listener(){
            public void changed(){emit();}
            public void available(){emit();}
        });
        new EventChannel(messenger,"cc.huevia/update-events").setStreamHandler(new EventChannel.StreamHandler(){
            public void onListen(Object args,EventChannel.EventSink sink){events=sink;emit();}
            public void onCancel(Object args){events=null;}
        });
        new MethodChannel(messenger,"cc.huevia/updates").setMethodCallHandler((call,reply)->{
            try{
                switch(call.method){
                    case "snapshot":reply.success(snapshot());return;
                    case "check":manager.check(false);reply.success(snapshot());return;
                    case "channel":{String selected=call.argument("channel");if(!"stable".equals(selected)&&!"beta".equals(selected)){reply.error("INVALID_ARGUMENT","更新通道无效。",null);return;}manager.channel(selected);reply.success(snapshot());return;}
                    case "download":manager.download(Boolean.TRUE.equals(call.argument("mobileAllowed")));reply.success(snapshot());return;
                    case "cancel":manager.cancel();reply.success(snapshot());return;
                    case "install":{
                        long epoch=++installEpoch;
                        manager.verifyForInstall(()->{if(!closed&&resumed&&epoch==installEpoch)openInstaller();});
                        reply.success(snapshot());return;
                    }
                    default:reply.notImplemented();
                }
            }catch(RuntimeException failure){reply.error("UPDATE_FAILED","更新操作未完成，请稍后重试。",null);}
        });
        manager.resume();
    }
    private Map<String,Object> snapshot(){
        Map<String,Object> value=new LinkedHashMap<>();
        String version="";try{version=host.getPackageManager().getPackageInfo(host.getPackageName(),0).versionName;}catch(Exception ignored){}
        value.put("platform","android");value.put("versionName",version);value.put("versionCode",manager.installedCode());
        value.put("packageName",host.getPackageName());value.put("channel",manager.channel());
        value.put("status",manager.status);value.put("error",manager.error);value.put("checking",manager.checking);
        value.put("downloading",manager.downloading);value.put("verifying",manager.verifying);value.put("verified",manager.verified);
        value.put("mandatory",manager.mandatory());value.put("progress",manager.progress);value.put("metered",manager.metered());
        if(manager.release!=null){NextAppUpdateManager.Release r=manager.release;Map<String,Object> release=new LinkedHashMap<>();
            release.put("id",r.id);release.put("versionName",r.name);release.put("versionCode",r.code);release.put("byteLength",r.bytes);
            release.put("sha256",r.hash);release.put("notes",r.notes);release.put("packageName",r.packageName);value.put("release",release);}
        return value;
    }
    private void emit(){if(!closed&&events!=null)events.success(snapshot());}
    private void openInstaller(){
        if(host.isFinishing()||host.isDestroyed())return;
        try{
            if(!host.getPackageManager().canRequestPackageInstalls()){
                host.startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,Uri.parse("package:"+host.getPackageName())));return;
            }
            Uri uri=manager.installerUri();if(uri==null)return;
            Intent intent=new Intent(Intent.ACTION_VIEW).setDataAndType(uri,"application/vnd.android.package-archive").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            intent.setClipData(ClipData.newRawUri("Huevia update",uri));host.startActivity(intent);
        }catch(RuntimeException failure){manager.error="无法打开系统安装程序，请在设置中允许此来源安装后重试。";emit();}
    }
    public void onHostPaused(){resumed=false;installEpoch++;manager.pause();}
    public void onHostResumed(){resumed=true;manager.resume();emit();}
    @Override public void close(){closed=true;installEpoch++;events=null;manager.close();}
}
