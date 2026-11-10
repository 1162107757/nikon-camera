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
    private NativeImportPicker importPicker;
    private volatile EventChannel.EventSink events;
    @Override public void configureFlutterEngine(FlutterEngine engine){
        super.configureFlutterEngine(engine);
        importPicker=new NativeImportPicker(this,worker);
        new EventChannel(engine.getDartExecutor().getBinaryMessenger(),"cc.huevia/events").setStreamHandler(new EventChannel.StreamHandler(){
            public void onListen(Object args,EventChannel.EventSink sink){events=sink;}
            public void onCancel(Object args){events=null;}
        });
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),"cc.huevia/core").setMethodCallHandler((call,reply)->{
            if(call.method.equals("pickFile")){
                Object kind=call.argument("preset");
                if(!(kind instanceof Boolean)||runtime==null){reply.error("INVALID_ARGUMENT","应用尚未准备好或导入类型无效。",null);return;}
                importPicker.pick((Boolean)kind,runtime.root().getPath(),reply);return;
            }
            Object rawJob=call.argument("jobId");
            if(rawJob!=null&&!(rawJob instanceof String)){reply.error("INVALID_ARGUMENT","任务标识格式无效。",null);return;}
            String job=(String)rawJob;
            if(call.method.equals("cancel")){if(job!=null){AtomicBoolean flag=jobs.get(job);if(flag!=null)flag.set(true);if(camera!=null)camera.cancel(job);}reply.success(null);return;}
            final String identity=job==null?UUID.randomUUID().toString():job;
            AtomicBoolean cancelled=new AtomicBoolean();if(jobs.putIfAbsent(identity,cancelled)!=null){reply.error("BUSY","该任务正在执行。",null);return;}
            try{worker.execute(()->{
                try{
                    Object value;
                    if(call.method.equals("initialize")){
                        if(runtime==null){File root=new File(getFilesDir(),"huevia-shared");runtime=new SharedRuntime(root.getPath(),new AndroidAccountStore(this),new AccountHttpTransport(),AccountInstallation.id(this));media=new NativeMedia(this,runtime);camera=new SharedCamera(root.getPath(),(host,port,fuji)->{cc.huevia.album.CameraWifiNetwork network=new cc.huevia.album.CameraWifiNetwork(this);return fuji?network.fujifilmPhotoConnector(host,port):network.connector(host,port);});}
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
                            main.post(()->{EventChannel.EventSink sink=events;if(sink!=null)sink.success(SharedRuntime.map("jobId",identity,"progress",normalized));});
                        };
                        if(operation.startsWith("media."))value=media.request(operation,payload,cancelled::get,progress);
                        else if(operation.startsWith("camera."))value=camera.request(operation,payload,identity,cancelled::get,progress);
                        else value=runtime.request(operation,payload,cancelled::get,progress);
                    }
                    main.post(()->reply.success(value));
                }catch(Exception error){String message=error.getMessage();main.post(()->reply.error(error instanceof InterruptedIOException?"CANCELLED":"OPERATION_FAILED",message==null?"操作未完成，请重试。":message,null));}
                catch(OutOfMemoryError exhausted){main.post(()->reply.error("MEMORY_LIMIT","内存不足，请关闭其他应用后重试。",null));}
                catch(LinkageError missing){main.post(()->reply.error("INSTALLATION_ERROR","安装包中的原生组件不可用，请重新安装此版本。",null));}
                finally{jobs.remove(identity);}
            });}catch(RejectedExecutionException busy){jobs.remove(identity);reply.error("BUSY","任务较多，请等待当前操作完成。",null);}
        });
    }
    @Override public void cleanUpFlutterEngine(FlutterEngine engine){events=null;for(AtomicBoolean flag:jobs.values())flag.set(true);super.cleanUpFlutterEngine(engine);}
    @Override protected void onActivityResult(int request,int result,android.content.Intent data){super.onActivityResult(request,result,data);if(request==NativeImportPicker.REQUEST&&importPicker!=null)importPicker.result(result,data);}
    @Override protected void onDestroy(){for(AtomicBoolean flag:jobs.values())flag.set(true);if(importPicker!=null)importPicker.cancel();if(camera!=null)camera.closeTransport();worker.shutdown();super.onDestroy();}
}
