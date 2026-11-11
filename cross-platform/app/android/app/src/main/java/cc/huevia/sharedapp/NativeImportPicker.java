package cc.huevia.sharedapp;

import android.app.Activity;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.provider.OpenableColumns;
import android.os.Handler;
import android.os.Looper;
import cc.huevia.library.SharedJson;
import cc.huevia.shared.*;
import io.flutter.plugin.common.MethodChannel;
import java.io.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

/** SAF metadata and bytes stay native; XFile.fromData eagerly loads entire Android documents. */
final class NativeImportPicker {
    private static final AtomicInteger requests=new AtomicInteger();
    private int activeRequest=-1;
    private final Activity activity;private final Executor worker;private final Handler main=new Handler(Looper.getMainLooper());
    private MethodChannel.Result pending;private boolean preset;private String root,submissionKind="",owner="";private volatile InputStream active;
    private AtomicBoolean cancelled=new AtomicBoolean();private volatile int generation,activeGeneration;
    NativeImportPicker(Activity activity,Executor worker){this.activity=activity;this.worker=worker;}
    void pick(boolean preset,String root,MethodChannel.Result reply){
        begin(preset,root,"","",reply);
    }
    void pickSubmission(String kind,String owner,String root,MethodChannel.Result reply){
        begin("ncp".equals(kind),root,kind,owner,reply);
    }
    private void begin(boolean preset,String root,String submissionKind,String owner,MethodChannel.Result reply){
        if(pending!=null){reply.error("BUSY","文件正在导入，请稍候。",null);return;}
        this.preset=preset;this.root=root;this.submissionKind=submissionKind;this.owner=owner;pending=reply;cancelled=new AtomicBoolean();int ticket=++generation;
        Intent intent=new Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        activeRequest=0xc000+(requests.incrementAndGet()&0x1fff);
        try{activity.startActivityForResult(intent,activeRequest);}catch(RuntimeException failure){finish(ticket,null,failure);}
    }
    boolean handles(int request){return pending!=null&&request==activeRequest;}
    void result(int result,Intent data){
        if(pending==null)return;
        activeRequest=-1;
        final int ticket=generation;final AtomicBoolean flag=cancelled;final boolean preset=this.preset;
        final String root=this.root,submissionKind=this.submissionKind,owner=this.owner;
        Uri uri=data==null?null:data.getData();
        if(result!=Activity.RESULT_OK||uri==null){finish(ticket,SharedJson.encode(SharedRuntime.map("cancelled",true)),null);return;}
        try{worker.execute(()->{
            try{
                String name=null;long declared=-1;
                try(Cursor cursor=activity.getContentResolver().query(uri,new String[]{OpenableColumns.DISPLAY_NAME,OpenableColumns.SIZE},null,null,null)){
                    if(cursor!=null&&cursor.moveToFirst()){int n=cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME),s=cursor.getColumnIndex(OpenableColumns.SIZE);if(n>=0)name=cursor.getString(n);if(s>=0&&!cursor.isNull(s))declared=cursor.getLong(s);}
                }
                if(declared>(preset?1024L*1024:submissionKind.isEmpty()?1024L*1024*1024:4L*1024*1024))throw new IOException("文件大小超出允许范围。");
                InputStream stream=activity.getContentResolver().openInputStream(uri);if(stream==null)throw new IOException("无法打开所选文件。");activeGeneration=ticket;active=stream;
                String receipt=submissionKind.isEmpty()?SharedImport.copy(stream,name,preset,root,flag::get):SharedImport.stageSubmission(stream,name,submissionKind,owner,root,flag::get);
                if(activeGeneration==ticket)active=null;finish(ticket,receipt,null);
            }catch(Exception failure){if(activeGeneration==ticket)active=null;finish(ticket,null,failure);}
            catch(OutOfMemoryError exhausted){if(activeGeneration==ticket)active=null;finish(ticket,null,new IOException("内存不足，文件未导入。"));}
        });}catch(RejectedExecutionException busy){finish(ticket,null,new IOException("任务较多，请等待当前操作完成。"));}
    }
    private void finish(int ticket,String value,Exception failure){main.post(()->{if(ticket!=generation)return;MethodChannel.Result reply=pending;pending=null;activeRequest=-1;if(reply==null)return;if(cancelled.get())reply.success(SharedJson.encode(SharedRuntime.map("cancelled",true)));else if(failure==null)reply.success(value);else reply.error("IMPORT_FAILED",failure.getMessage(),null);});}
    void cancel(){int ticket=generation;cancelled.set(true);InputStream stream=active;if(activeGeneration==ticket&&stream!=null)try{stream.close();}catch(IOException ignored){}finish(ticket,SharedJson.encode(SharedRuntime.map("cancelled",true)),null);}
}
