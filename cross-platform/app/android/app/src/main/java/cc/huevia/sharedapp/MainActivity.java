package cc.huevia.sharedapp;

import android.os.Handler;
import android.os.Looper;
import cc.huevia.account.*;
import cc.huevia.library.SharedJson;
import cc.huevia.shared.*;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.*;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;

public final class MainActivity extends FlutterActivity {
    private final Handler main=new Handler(Looper.getMainLooper());
    private ThreadPoolExecutor worker=new ThreadPoolExecutor(1,1,30,TimeUnit.SECONDS,new ArrayBlockingQueue<>(8));
    private ConcurrentHashMap<String,NativeTaskCancellation> jobs=new ConcurrentHashMap<>();
    private AtomicBoolean backendClosed=new AtomicBoolean();
    private boolean ownsBackend=true;
    private NativeConnectionProtection protection;
    private NativeOriginalFiles originalFiles;
    private NativeAlbumOperations albumOperations;
    private BinaryMessenger messenger;
    private MainActivity eventTarget;
    private SharedRuntime runtime;
    private NativeMedia media;
    private SharedCamera camera;
    private NativeUsbCamera usbCamera;
    private NativeImportPicker importPicker;
    private NativeGallery gallery;
    private NativeQqAuthorization qqAuthorization;
    private NativeUpdates updates;
    private NativeLegacyFiles legacyFiles;
    private MethodChannel.Result galleryPermission;
    private MethodChannel.Result gallerySavePermission;
    private volatile EventChannel.EventSink events;
    @Override public FlutterEngine provideFlutterEngine(android.content.Context context){return NativeConnectionProtection.cachedEngine();}
    @Override public boolean shouldDestroyEngineWithHost(){return ownsBackend&&!NativeConnectionProtection.keepEngine();}
    @Override public void configureFlutterEngine(FlutterEngine engine){
        super.configureFlutterEngine(engine);
        MainActivity prior=NativeConnectionProtection.previousHost(engine);
        if(prior!=null&&prior!=this&&!prior.backendClosed.get()){
            worker.shutdown();worker=prior.worker;jobs=prior.jobs;backendClosed=prior.backendClosed;
            prior.ownsBackend=false;
            runtime=prior.runtime;media=prior.media;camera=prior.camera;usbCamera=prior.usbCamera;gallery=prior.gallery;
            events=prior.events;prior.eventTarget=this;
        }
        messenger=engine.getDartExecutor().getBinaryMessenger();
        protection=new NativeConnectionProtection(this,engine);
        if(qqAuthorization!=null)qqAuthorization.close();
        if(updates!=null)updates.close();
        if(legacyFiles!=null)legacyFiles.close();
        qqAuthorization=new NativeQqAuthorization(this,engine.getDartExecutor().getBinaryMessenger());
        updates=new NativeUpdates(this,engine.getDartExecutor().getBinaryMessenger());
        legacyFiles=new NativeLegacyFiles(this,engine.getDartExecutor().getBinaryMessenger(),worker);
        NativeStability stability=new NativeStability(this);
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),"cc.huevia/stability").setMethodCallHandler((call,reply)->{
            if(call.method.equals("recordFlutter")){
                try{stability.recordFlutter(call.arguments);reply.success(null);}
                catch(Exception|LinkageError|OutOfMemoryError unavailable){reply.error("STABILITY_UNAVAILABLE","异常记录暂不可用。",null);}return;
            }
            if(!call.method.equals("snapshot")){reply.notImplemented();return;}
            try{worker.execute(()->{try{String value=stability.snapshot();main.post(()->reply.success(value));}
                catch(Exception|LinkageError|OutOfMemoryError unavailable){main.post(()->reply.error("STABILITY_UNAVAILABLE","异常记录暂不可用。",null));}});}
            catch(RejectedExecutionException busy){reply.error("BUSY","请等待当前操作完成后再读取诊断。",null);}
        });
        if(usbCamera==null)usbCamera=new NativeUsbCamera(getApplicationContext());
        importPicker=new NativeImportPicker(this,worker);
        configureStorageAdapters();
        new EventChannel(engine.getDartExecutor().getBinaryMessenger(),"cc.huevia/events").setStreamHandler(new EventChannel.StreamHandler(){
            public void onListen(Object args,EventChannel.EventSink sink){events=sink;}
            public void onCancel(Object args){events=null;}
        });
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),"cc.huevia/core").setMethodCallHandler((call,reply)->{
            if(call.method.equals("cameraUsbPermission")){String id=call.argument("id");if(id==null){reply.error("INVALID_ARGUMENT","请选择 USB 相机。",null);return;}usbCamera.requestPermission(id,reply);return;}
            if(call.method.equals("gallerySavePermission")){
                if(gallery==null){reply.error("NOT_READY","应用尚未准备好。",null);return;}
                if(android.os.Build.VERSION.SDK_INT>=29||checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE)==android.content.pm.PackageManager.PERMISSION_GRANTED){reply.success(SharedJson.encode(SharedRuntime.map("granted",true)));return;}
                if(galleryPermission!=null||gallerySavePermission!=null){reply.error("BUSY","请完成当前照片权限选择。",null);return;}
                gallerySavePermission=reply;requestPermissions(new String[]{android.Manifest.permission.WRITE_EXTERNAL_STORAGE,android.Manifest.permission.READ_EXTERNAL_STORAGE},49319);return;
            }
            if(call.method.equals("galleryPermission")){
                if(gallery==null){reply.error("NOT_READY","应用尚未准备好。",null);return;}
                if(galleryPermission!=null||gallerySavePermission!=null){reply.error("BUSY","请完成当前照片权限选择。",null);return;}
                galleryPermission=reply;
                String permission=android.os.Build.VERSION.SDK_INT>=33?android.Manifest.permission.READ_MEDIA_IMAGES:android.Manifest.permission.READ_EXTERNAL_STORAGE;
                requestPermissions(android.os.Build.VERSION.SDK_INT>=34?new String[]{permission,android.Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED}:new String[]{permission},49318);return;
            }
            if(call.method.equals("pickAvatar")){
                Object owner=call.argument("owner"),updatedAt=call.argument("updatedAt");
                if(runtime==null||!(owner instanceof String)||!(updatedAt instanceof String)){reply.error("INVALID_ARGUMENT","账号尚未准备好。",null);return;}
                try{worker.execute(()->{try{runtime.guardProfile((String)owner,(String)updatedAt);runOnUiThread(()->importPicker.pickAvatar((String)owner,(String)updatedAt,runtime,runtime.root().getPath(),reply));}
                    catch(Exception failure){runOnUiThread(()->reply.error("AVATAR_FAILED",failure.getMessage(),null));}});}
                catch(RejectedExecutionException busy){reply.error("BUSY","任务较多，请稍后重试。",null);}return;
            }
            if(call.method.equals("pickFile")){
                Object kind=call.argument("preset");
                if(!(kind instanceof Boolean)||runtime==null){reply.error("INVALID_ARGUMENT","应用尚未准备好或导入类型无效。",null);return;}
                Object submission=call.argument("submissionKind");
                if(submission!=null){
                    Object owner=call.argument("owner");
                    if(!(submission instanceof String)||!java.util.Arrays.asList("ncp","preview").contains(submission)||!(owner instanceof String)||((Boolean)kind)!=submission.equals("ncp")){reply.error("INVALID_ARGUMENT","投稿文件类型无效。",null);return;}
                    try{worker.execute(()->{try{runtime.guardOwner((String)owner);runOnUiThread(()->importPicker.pickSubmission((String)submission,(String)owner,runtime.root().getPath(),reply));}
                        catch(Exception failure){runOnUiThread(()->reply.error("IMPORT_FAILED",failure.getMessage(),null));}});}
                    catch(RejectedExecutionException busy){reply.error("BUSY","任务较多，请稍后重试。",null);}return;
                }
                importPicker.pick((Boolean)kind,runtime.root().getPath(),reply);return;
            }
            Object rawJob=call.argument("jobId");
            if(rawJob!=null&&!(rawJob instanceof String)){reply.error("INVALID_ARGUMENT","任务标识格式无效。",null);return;}
            String job=(String)rawJob;
            if(call.method.equals("cancel")){if(job!=null){NativeTaskCancellation flag=jobs.get(job);if(flag!=null&&flag.cancelIfActive()){if(camera!=null)camera.cancel(job);if(gallery!=null)gallery.cancel(job);}}reply.success(null);return;}
            final String identity=job==null?UUID.randomUUID().toString():job;
            NativeTaskCancellation cancelled=new NativeTaskCancellation();if(jobs.putIfAbsent(identity,cancelled)!=null){reply.error("BUSY","该任务正在执行。",null);return;}
            try{worker.execute(()->{
                try{
                    Object value;
                    if(call.method.equals("initialize")){
                        if(runtime==null){android.content.Context app=getApplicationContext();File root=new File(app.getFilesDir(),"huevia-shared");runtime=new SharedRuntime(root.getPath(),new AndroidAccountStore(app),new AccountHttpTransport(),AccountInstallation.id(app));media=new NativeMedia(app,runtime);camera=new SharedCamera(root.getPath(),(host,port,fuji)->{cc.huevia.album.CameraWifiNetwork network=new cc.huevia.album.CameraWifiNetwork(app);return fuji?network.fujifilmPhotoConnector(host,port):network.connector(host,port);},usbCamera);}
                        if(gallery==null)gallery=new NativeGallery(this,runtime);
                        main.post(this::configureStorageAdapters);
                        value=SharedJson.encode(SharedRuntime.map("root",runtime.root().getPath(),"schema",SharedJson.object(CoreEngine.schema()),"platform","android"));
                    }else{
                        if(runtime==null)throw new IOException("应用尚未初始化。");
                        String operation=call.argument("operation"),payload=call.argument("payload");
                        if(operation==null||payload==null||payload.length()>4*1024*1024)throw new IOException("操作数据无效。");
                        if(cancelled.get())throw new InterruptedIOException("操作已取消。");
                        long[] lastProgress={0};double[] lastValue={-1};
                        java.util.function.DoubleConsumer progress=valueProgress->{
                            if(!Double.isFinite(valueProgress))return;double normalized=Math.max(0,Math.min(1,valueProgress));long now=System.nanoTime();
                            if(normalized==lastValue[0]||normalized<1&&now-lastProgress[0]<60_000_000L)return;lastProgress[0]=now;lastValue[0]=normalized;
                            main.post(()->emit(SharedRuntime.map("jobId",identity,"progress",normalized)));
                        };
                        if(operation.startsWith("media."))value=media.request(operation,payload,cancelled::get,progress);
                        else if(operation.startsWith("camera.")){Map<String,Object> p=SharedJson.object(payload);if(p.containsKey("queueId"))runtime.guardOwner(SharedRuntime.text(p,"owner",64));value=camera.request(operation,payload,identity,cancelled::get,progress);}
                        else if(operation.equals("files.publishOriginal")){if(originalFiles==null)throw new IOException("文件保存尚未准备好。");value=originalFiles.publish(payload,cancelled::get);}
                        else if(operation.equals("gallery.delete")||operation.equals("gallery.publishedCopies")){if(albumOperations==null)throw new IOException("系统相册尚未准备好。");value=albumOperations.request(operation,payload,cancelled::get);}
                        else if(operation.startsWith("gallery.")){value=gallery.request(operation,payload,cancelled::get,identity);if(operation.equals("gallery.publish")||operation.equals("gallery.publishOriginal"))main.post(()->emit(SharedRuntime.map("kind","galleryChanged")));}
                        else value=runtime.request(operation,payload,cancelled::get,progress);
                    }
                    complete(identity,cancelled,()->reply.success(value));
                }catch(Exception error){String message=error.getMessage();complete(identity,cancelled,()->reply.error(error instanceof InterruptedIOException?"CANCELLED":"OPERATION_FAILED",message==null?"操作未完成，请重试。":message,error instanceof AccountException?SharedRuntime.map("accountCode",((AccountException)error).code,"status",((AccountException)error).status):null));}
                catch(OutOfMemoryError exhausted){complete(identity,cancelled,()->reply.error("MEMORY_LIMIT","内存不足，请关闭其他应用后重试。",null));}
                catch(LinkageError missing){complete(identity,cancelled,()->reply.error("INSTALLATION_ERROR","安装包中的原生组件不可用，请重新安装此版本。",null));}
                finally{cancelled.finish();jobs.remove(identity,cancelled);}
            });}catch(RejectedExecutionException busy){cancelled.finish();jobs.remove(identity,cancelled);reply.error("BUSY","任务较多，请等待当前操作完成。",null);}
        });
    }
    private void complete(String identity,NativeTaskCancellation task,Runnable deliver){
        // Flutter may issue the next request synchronously from this result.
        // A late finalizer for this task must never remove its replacement.
        task.finish();
        main.post(()->{jobs.remove(identity,task);if(!backendClosed.get())deliver.run();});
    }
    private void emit(Map<String,Object> value){if(eventTarget!=null){eventTarget.emit(value);return;}EventChannel.EventSink sink=events;if(sink!=null&&!backendClosed.get())try{sink.success(value);}catch(RuntimeException detached){events=null;}}
    private void configureStorageAdapters(){if(runtime==null||messenger==null||isDestroyed())return;if(originalFiles==null){originalFiles=new NativeOriginalFiles(this,runtime);new MethodChannel(messenger,"cc.huevia/file-publication").setMethodCallHandler(originalFiles);}if(albumOperations==null&&gallery!=null)albumOperations=new NativeAlbumOperations(this,runtime,gallery);}
    void stopCameraWork(){for(Map.Entry<String,NativeTaskCancellation> entry:jobs.entrySet()){String id=entry.getKey();if((id.startsWith("camera-")||id.startsWith("download-"))&&entry.getValue().cancelIfActive()){if(camera!=null)camera.cancel(id);}}}
    void releaseRetainedBackend(){if(!ownsBackend||!backendClosed.compareAndSet(false,true))return;events=null;for(AtomicBoolean flag:jobs.values())flag.set(true);if(gallery!=null)gallery.cancelAll();if(camera!=null)camera.closeTransport();if(usbCamera!=null)usbCamera.dispose();worker.shutdown();}
    void retireRetainedBackend(){releaseRetainedBackend();ownsBackend=false;}
    @Override public void cleanUpFlutterEngine(FlutterEngine engine){if(ownsBackend&&!NativeConnectionProtection.keepEngine()){events=null;for(AtomicBoolean flag:jobs.values())flag.set(true);if(gallery!=null)gallery.cancelAll();}super.cleanUpFlutterEngine(engine);}
    @Override protected void onActivityResult(int request,int result,android.content.Intent data){if(albumOperations!=null&&albumOperations.onActivityResult(request,result,data))return;if(originalFiles!=null&&originalFiles.onActivityResult(request,result,data))return;if(qqAuthorization!=null&&qqAuthorization.onActivityResult(request,result,data))return;if(legacyFiles!=null&&legacyFiles.onActivityResult(request,result,data))return;super.onActivityResult(request,result,data);if(importPicker!=null&&importPicker.handles(request))importPicker.result(result,data);}
    @Override protected void onPause(){if(qqAuthorization!=null)qqAuthorization.onHostPaused();if(updates!=null)updates.onHostPaused();super.onPause();}
    @Override protected void onResume(){super.onResume();if(qqAuthorization!=null)qqAuthorization.onHostResumed();if(updates!=null)updates.onHostResumed();}
    @Override public void onRequestPermissionsResult(int request,String[] permissions,int[] grants){super.onRequestPermissionsResult(request,permissions,grants);if(request==49324&&protection!=null)protection.permissionResult();if(request==49318&&galleryPermission!=null){MethodChannel.Result reply=galleryPermission;galleryPermission=null;try{reply.success(gallery.access());}catch(IOException error){reply.error("PERMISSION_ERROR",error.getMessage(),null);}}if(request==49319&&gallerySavePermission!=null){MethodChannel.Result reply=gallerySavePermission;gallerySavePermission=null;reply.success(SharedJson.encode(SharedRuntime.map("granted",checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE)==android.content.pm.PackageManager.PERMISSION_GRANTED)));}}
    @Override protected void onDestroy(){if(albumOperations!=null)albumOperations.close();if(qqAuthorization!=null)qqAuthorization.close();if(updates!=null)updates.close();if(legacyFiles!=null)legacyFiles.close();if(originalFiles!=null)originalFiles.dispose();if(galleryPermission!=null){galleryPermission.error("CANCELLED","照片权限选择已取消。",null);galleryPermission=null;}if(gallerySavePermission!=null){gallerySavePermission.error("CANCELLED","保存权限选择已取消。",null);gallerySavePermission=null;}if(importPicker!=null)importPicker.cancel();if(protection!=null)protection.detached();if(!NativeConnectionProtection.keepEngine())releaseRetainedBackend();super.onDestroy();}
}
