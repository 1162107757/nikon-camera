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
    private final ThreadPoolExecutor worker=new ThreadPoolExecutor(1,1,30,TimeUnit.SECONDS,new ArrayBlockingQueue<>(8));
    private final ConcurrentHashMap<String,AtomicBoolean> jobs=new ConcurrentHashMap<>();
    private SharedRuntime runtime;
    private NativeMedia media;
    private SharedCamera camera;
    private volatile EventChannel.EventSink events;
    @Override public void configureFlutterEngine(FlutterEngine engine){
        super.configureFlutterEngine(engine);
        new EventChannel(engine.getDartExecutor().getBinaryMessenger(),"cc.huevia/events").setStreamHandler(new EventChannel.StreamHandler(){
            public void onListen(Object args,EventChannel.EventSink sink){events=sink;}
            public void onCancel(Object args){events=null;}
        });
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),"cc.huevia/core").setMethodCallHandler((call,reply)->{
            if(call.method.equals("cancel")){String id=call.argument("jobId");AtomicBoolean flag=jobs.get(id);if(flag!=null)flag.set(true);if(camera!=null)camera.cancel(id);reply.success(null);return;}
            String job=call.argument("jobId");final String identity=job==null?UUID.randomUUID().toString():job;
            AtomicBoolean cancelled=new AtomicBoolean();jobs.put(identity,cancelled);
            try{worker.execute(()->{
                try{
                    Object value;
                    if(call.method.equals("initialize")){
                        if(runtime==null){File root=new File(getFilesDir(),"huevia-shared");runtime=new SharedRuntime(root.getPath(),new AndroidAccountStore(this),new AccountHttpTransport());media=new NativeMedia(this,runtime);camera=new SharedCamera(root.getPath(),(host,port,fuji)->{cc.huevia.album.CameraWifiNetwork network=new cc.huevia.album.CameraWifiNetwork(this);return fuji?network.fujifilmPhotoConnector(host,port):network.connector(host,port);});}
                        value=SharedJson.encode(SharedRuntime.map("root",runtime.root().getPath(),"schema",SharedJson.object(CoreEngine.schema()),"platform","android"));
                    }else{
                        if(runtime==null)throw new IOException("应用尚未初始化。");
                        String operation=call.argument("operation"),payload=call.argument("payload");
                        if(operation==null||payload==null||payload.length()>4*1024*1024)throw new IOException("操作数据无效。");
                        if(cancelled.get())throw new InterruptedIOException("操作已取消。");
                        java.util.function.DoubleConsumer progress=valueProgress->main.post(()->{EventChannel.EventSink sink=events;if(sink!=null)sink.success(SharedRuntime.map("jobId",identity,"progress",valueProgress));});
                        if(operation.startsWith("media."))value=media.request(operation,payload,cancelled::get,progress);
                        else if(operation.startsWith("camera."))value=camera.request(operation,payload,identity,cancelled::get,progress);
                        else value=runtime.request(operation,payload);
                    }
                    main.post(()->reply.success(value));
                }catch(Exception error){String message=error.getMessage();main.post(()->reply.error(error instanceof InterruptedIOException?"CANCELLED":"OPERATION_FAILED",message==null?"操作未完成，请重试。":message,null));}
                catch(OutOfMemoryError exhausted){main.post(()->reply.error("MEMORY_LIMIT","内存不足，请关闭其他应用后重试。",null));}
                finally{jobs.remove(identity);}
            });}catch(RejectedExecutionException busy){jobs.remove(identity);reply.error("BUSY","任务较多，请等待当前操作完成。",null);}
        });
    }
    @Override public void cleanUpFlutterEngine(FlutterEngine engine){events=null;for(AtomicBoolean flag:jobs.values())flag.set(true);super.cleanUpFlutterEngine(engine);}
    @Override protected void onDestroy(){for(AtomicBoolean flag:jobs.values())flag.set(true);if(camera!=null)camera.disconnect();worker.shutdown();super.onDestroy();}
}
