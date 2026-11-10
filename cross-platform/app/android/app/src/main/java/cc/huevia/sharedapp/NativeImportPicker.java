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

/** SAF metadata and bytes stay native; XFile.fromData eagerly loads entire Android documents. */
final class NativeImportPicker {
    static final int REQUEST=49317;
    private final Activity activity;private final Executor worker;private final Handler main=new Handler(Looper.getMainLooper());
    private MethodChannel.Result pending;private boolean preset;private String root;private volatile InputStream active;
    private final AtomicBoolean cancelled=new AtomicBoolean();
    NativeImportPicker(Activity activity,Executor worker){this.activity=activity;this.worker=worker;}
    void pick(boolean preset,String root,MethodChannel.Result reply){
        if(pending!=null){reply.error("BUSY","文件正在导入，请稍候。",null);return;}
        this.preset=preset;this.root=root;pending=reply;cancelled.set(false);
        Intent intent=new Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        try{activity.startActivityForResult(intent,REQUEST);}catch(RuntimeException failure){finish(null,failure);}
    }
    void result(int result,Intent data){
        if(pending==null)return;
        Uri uri=data==null?null:data.getData();
        if(result!=Activity.RESULT_OK||uri==null){finish(SharedJson.encode(SharedRuntime.map("cancelled",true)),null);return;}
        try{worker.execute(()->{
            try{
                String name=null;long declared=-1;
                try(Cursor cursor=activity.getContentResolver().query(uri,new String[]{OpenableColumns.DISPLAY_NAME,OpenableColumns.SIZE},null,null,null)){
                    if(cursor!=null&&cursor.moveToFirst()){int n=cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME),s=cursor.getColumnIndex(OpenableColumns.SIZE);if(n>=0)name=cursor.getString(n);if(s>=0&&!cursor.isNull(s))declared=cursor.getLong(s);}
                }
                if(declared>(preset?1024L*1024:1024L*1024*1024))throw new IOException("文件大小超出允许范围。");
                InputStream stream=activity.getContentResolver().openInputStream(uri);if(stream==null)throw new IOException("无法打开所选文件。");active=stream;
                String receipt=SharedImport.copy(stream,name,preset,root,cancelled::get);active=null;finish(receipt,null);
            }catch(Exception failure){active=null;finish(null,failure);}
            catch(OutOfMemoryError exhausted){active=null;finish(null,new IOException("内存不足，文件未导入。"));}
        });}catch(RejectedExecutionException busy){finish(null,new IOException("任务较多，请等待当前操作完成。"));}
    }
    private void finish(String value,Exception failure){main.post(()->{MethodChannel.Result reply=pending;pending=null;if(reply==null)return;if(failure==null)reply.success(value);else reply.error("IMPORT_FAILED",failure.getMessage(),null);});}
    void cancel(){cancelled.set(true);InputStream stream=active;if(stream!=null)try{stream.close();}catch(IOException ignored){}finish(SharedJson.encode(SharedRuntime.map("cancelled",true)),null);}
}
