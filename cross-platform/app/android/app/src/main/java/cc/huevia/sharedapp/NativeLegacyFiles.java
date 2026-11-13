package cc.huevia.sharedapp;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import cc.huevia.shared.LegacyArchive;
import io.flutter.plugin.common.*;
import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;

/** User-selected document only; no attempt to read the old package's private directory. */
public final class NativeLegacyFiles implements AutoCloseable {
    private static final int REQUEST=49340;
    private final Activity host;
    private final ExecutorService worker;
    private MethodChannel.Result pending;
    private long generation;
    private boolean closed;
    public NativeLegacyFiles(Activity host,BinaryMessenger messenger,ExecutorService worker){
        this.host=host;this.worker=worker;
        new MethodChannel(messenger,"cc.huevia/legacy-files").setMethodCallHandler((call,reply)->{
            if(!call.method.equals("pick")){reply.notImplemented();return;}
            if(pending!=null){reply.error("BUSY","请先完成当前文件选择。",null);return;}
            pending=reply;generation++;
            try{host.startActivityForResult(new Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*").putExtra(Intent.EXTRA_MIME_TYPES,new String[]{"application/zip","application/octet-stream"}),REQUEST);}
            catch(RuntimeException failure){finish(null,"无法打开系统文件选择器，请稍后重试。");}
        });
    }
    public boolean onActivityResult(int request,int result,Intent data){
        if(request!=REQUEST)return false;
        if(pending==null)return true;
        if(result!=Activity.RESULT_OK||data==null||data.getData()==null){finish(Collections.singletonMap("cancelled",true),null);return true;}
        final long attempt=generation;Uri uri=data.getData();
        try{worker.execute(()->{
            File target=null;
            try{
                File root=new File(host.getFilesDir(),"huevia-shared/legacy-incoming");if(!root.isDirectory()&&!root.mkdirs())throw new IOException();
                if(Files.isSymbolicLink(root.toPath()))throw new IOException();target=new File(root,UUID.randomUUID()+".zip");
                try(InputStream input=host.getContentResolver().openInputStream(uri);FileOutputStream output=new FileOutputStream(target)){
                    if(input==null)throw new IOException();byte[] block=new byte[65536];long bytes=0;int count;
                    while((count=input.read(block))!=-1){if(closed||attempt!=generation)throw new InterruptedIOException();bytes+=count;if(bytes>LegacyArchive.MAX_BYTES||root.getUsableSpace()<64L*1024*1024)throw new IOException();output.write(block,0,count);}output.getFD().sync();
                }
                File complete=target;host.runOnUiThread(()->{if(!closed&&attempt==generation)finish(Collections.singletonMap("path",complete.getPath()),null);else complete.delete();});
            }catch(Exception failure){if(target!=null)target.delete();host.runOnUiThread(()->{if(!closed&&attempt==generation)finish(null,"无法读取迁入包，请检查文件与可用空间后重试。");});}
        });}catch(RejectedExecutionException busy){finish(null,"请等待当前操作完成后重试。");}
        return true;
    }
    private void finish(Object value,String error){MethodChannel.Result reply=pending;pending=null;if(reply==null)return;if(error==null)reply.success(value);else reply.error("LEGACY_IMPORT_FAILED",error,null);}
    @Override public void close(){closed=true;generation++;finish(Collections.singletonMap("cancelled",true),null);}
}
