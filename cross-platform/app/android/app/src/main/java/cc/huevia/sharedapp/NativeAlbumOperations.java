package cc.huevia.sharedapp;

import android.app.*;
import android.content.*;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.provider.MediaStore;
import cc.huevia.album.PhotoEditStore;
import cc.huevia.library.SharedJson;
import cc.huevia.shared.SharedRuntime;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.BooleanSupplier;

/** A single system consent transaction, journaled before the provider can change. */
final class NativeAlbumOperations {
    private static final int CONSENT=6473;
    private final Activity activity;private final SharedRuntime runtime;private final NativeGallery gallery;
    private volatile Pending pending;
    private volatile boolean closed;
    private static final class Pending {final CountDownLatch ready=new CountDownLatch(1);volatile int result=Activity.RESULT_CANCELED;volatile Exception error;}
    NativeAlbumOperations(Activity activity,SharedRuntime runtime,NativeGallery gallery){this.activity=activity;this.runtime=runtime;this.gallery=gallery;}
    boolean onActivityResult(int request,int result,Intent data){if(request!=CONSENT)return false;Pending value=pending;if(value!=null){value.result=result;value.ready.countDown();}return true;}
    void close(){closed=true;Pending value=pending;if(value!=null){value.error=new IOException("页面已关闭，请重新核对系统删除结果。");value.ready.countDown();}}
    synchronized String request(String operation,String json,BooleanSupplier cancel)throws IOException {
        Map<String,Object> p=SharedJson.object(json);String owner=SharedRuntime.text(p,"owner",64);runtime.guardOwner(owner);
        if(operation.equals("gallery.publishedCopies"))return copies(owner,p,cancel);
        if(!operation.equals("gallery.delete"))throw new IOException("未知的系统相册任务。");
        String id=SharedRuntime.text(p,"operationId",32);if(!id.matches("[0-9a-f]{32}"))throw new IOException("删除任务标识无效。");
        Object raw=p.get("ids");if(!(raw instanceof List)||((List<?>)raw).isEmpty()||((List<?>)raw).size()>100)throw new IOException("请选择 1–100 张系统照片。");
        List<String> ids=new ArrayList<>();for(Object value:(List<?>)raw){if(!(value instanceof String)||!((String)value).matches("content://media/(external|external_primary)/images/media/[0-9]+"))throw new IOException("系统照片标识无效。");if(ids.contains(value))throw new IOException("系统照片重复。");ids.add((String)value);}
        File directory=new File(runtime.root(),"system-album-deletions").getCanonicalFile();if(!directory.getParentFile().equals(runtime.root().getCanonicalFile())||Files.isSymbolicLink(directory.toPath())||(!directory.isDirectory()&&!directory.mkdirs()))throw new IOException("无法记录系统删除任务。");
        File record=new File(directory,id+".json");if(Files.isSymbolicLink(record.toPath()))throw new IOException("删除记录不能是链接。");
        Map<String,Object> plan;
        if(record.exists()){if(record.length()>32768)throw new IOException("删除记录过大。");plan=SharedJson.object(new String(Files.readAllBytes(record.toPath()),StandardCharsets.UTF_8));if(!owner.equals(plan.get("owner"))||!ids.equals(plan.get("ids")))throw new IOException("删除任务与照片范围不符。");if(Boolean.TRUE.equals(plan.get("deleted")))return SharedJson.encode(plan);}
        else {for(String value:ids)gallery.deletionUri(value);plan=SharedRuntime.map("owner",owner,"ids",ids,"deleted",false);write(record,plan);}
        List<Uri> present=new ArrayList<>();for(String value:ids){check(cancel);Uri uri=Uri.parse(value);if(exists(uri))present.add(uri);}
        if(!present.isEmpty()){
            check(cancel);runtime.guardOwner(owner);
            if(Build.VERSION.SDK_INT>=30) consent(MediaStore.createDeleteRequest(activity.getContentResolver(),present),cancel);
            else for(Uri uri:present){check(cancel);runtime.guardOwner(owner);try{activity.getContentResolver().delete(uri,null,null);}catch(SecurityException denied){if(Build.VERSION.SDK_INT>=29&&denied instanceof RecoverableSecurityException){consent(((RecoverableSecurityException)denied).getUserAction().getActionIntent(),cancel);check(cancel);activity.getContentResolver().delete(uri,null,null);}else throw new IOException("照片删除权限已变化，请重新授权。",denied);}}
        }
        // A successful activity result is not a deletion receipt: query every selected row.
        for(String value:ids)if(exists(Uri.parse(value)))throw new IOException("系统仍保留部分照片，请重试未完成任务。");
        plan.put("deleted",true);write(record,plan);return SharedJson.encode(plan);
    }
    private void consent(PendingIntent intent,BooleanSupplier cancel)throws IOException {
        if(closed)throw new IOException("系统删除确认页面已关闭。");
        Pending value=new Pending();pending=value;
        activity.runOnUiThread(()->{try{if(closed||activity.isFinishing()||activity.isDestroyed())throw new IOException("页面已关闭。");activity.startIntentSenderForResult(intent.getIntentSender(),CONSENT,null,0,0,0);}catch(Exception e){value.error=e;value.ready.countDown();}});
        try {while(!value.ready.await(100,TimeUnit.MILLISECONDS))check(cancel);if(value.error!=null)throw new IOException("无法打开系统删除确认。",value.error);if(value.result!=Activity.RESULT_OK)throw new IOException("系统删除已取消，应用内照片保持原样。");}
        catch(InterruptedException interrupted){Thread.currentThread().interrupt();throw new InterruptedIOException("系统删除等待已停止。");}
        finally{if(pending==value)pending=null;}
    }
    private boolean exists(Uri uri)throws IOException{try(Cursor cursor=activity.getContentResolver().query(uri,new String[]{MediaStore.Images.Media._ID},null,null,null)){if(cursor==null)throw new IOException("无法核对系统照片，未确认删除。");return cursor.moveToFirst();}catch(SecurityException denied){throw new IOException("照片权限已变化，未确认删除。",denied);}}
    private String copies(String owner,Map<String,Object> p,BooleanSupplier cancel)throws IOException {
        Object raw=p.get("versionIds");if(!(raw instanceof List)||((List<?>)raw).size()>1000)throw new IOException("成品选择无效。");Set<String> versions=new HashSet<>();for(Object id:(List<?>)raw){if(!(id instanceof String)||!((String)id).matches("[0-9a-f]{64}"))throw new IOException("成品标识无效。");versions.add((String)id);}
        File base=new File(activity.getFilesDir(),"shared-gallery-copies/"+PhotoEditStore.hash(owner.getBytes(StandardCharsets.UTF_8))).getCanonicalFile();List<Object> ids=new ArrayList<>();File[] files=base.listFiles();
        if(files!=null)for(File file:files){check(cancel);if(!file.getName().matches("[0-9a-f]{32}\\.json")||Files.isSymbolicLink(file.toPath())||file.length()>8192)continue;Map<String,Object> row=SharedJson.object(new String(Files.readAllBytes(file.toPath()),StandardCharsets.UTF_8));Object uri=row.get("uri");if(versions.contains(row.get("version"))&&"complete".equals(row.get("state"))&&uri instanceof String&&exists(Uri.parse((String)uri))){cc.huevia.album.SharedGalleryPublication.verify(activity,(String)uri,(String)row.get("sha256"),((Number)row.get("bytes")).longValue(),cancel);gallery.allowDeletionUri((String)uri);if(!ids.contains(uri))ids.add(uri);}}
        for(String version:versions){check(cancel);Map<String,Object> row=SharedJson.object(runtime.request("version.open",SharedJson.encode(SharedRuntime.map("owner",owner,"id",version)),cancel,v->{}));String uri=cc.huevia.album.SharedGalleryDeletion.published(activity,new File((String)row.get("path")),owner,version,(String)row.get("sha256"),((Number)row.get("bytes")).longValue(),cancel);if(!uri.isEmpty()&&exists(Uri.parse(uri))){cc.huevia.album.SharedGalleryPublication.verify(activity,uri,(String)row.get("sha256"),((Number)row.get("bytes")).longValue(),cancel);gallery.allowDeletionUri(uri);if(!ids.contains(uri))ids.add(uri);}}
        String sourcePath=SharedRuntime.text(p,"path",4096),sourceSha=SharedRuntime.text(p,"sourceSha",64);
        if(!sourcePath.isEmpty()){
            File source=runtime.privateFile(sourcePath);if(!source.getParentFile().equals(new File(runtime.root(),"originals").getCanonicalFile())||!sourceSha.matches("[0-9a-f]{64}"))throw new IOException("原始照片删除范围无效。");runtime.validateSource(sourcePath,sourceSha);
            File records=new File(runtime.root(),"source-publications/"+PhotoEditStore.hash(owner.getBytes(StandardCharsets.UTF_8))).getCanonicalFile();File[] originals=records.listFiles();if(originals!=null)for(File file:originals){check(cancel);if(!file.getName().matches("[0-9a-f]{32}\\.json")||Files.isSymbolicLink(file.toPath())||file.length()>8192)continue;Map<String,Object> row=SharedJson.object(new String(Files.readAllBytes(file.toPath()),StandardCharsets.UTF_8));if(!sourceSha.equals(row.get("sourceSha"))||!"JPEG".equals(row.get("format")))continue;String uri=cc.huevia.album.SharedGalleryDeletion.published(activity,source,owner,(String)row.get("id"),sourceSha,source.length(),true,cancel);if(!uri.isEmpty()&&exists(Uri.parse(uri))){cc.huevia.album.SharedGalleryPublication.verify(activity,uri,sourceSha,source.length(),cancel);gallery.allowDeletionUri(uri);if(!ids.contains(uri))ids.add(uri);}}
            for(String suffix:new String[]{".record",".legacy.record"}){File file=new File(activity.getFilesDir(),"raw-photo-publications/"+sourceSha+suffix);if(!file.exists()&&!new File(file+".bak").exists())continue;if(Files.isSymbolicLink(file.toPath())||Files.isSymbolicLink(new File(file+".bak").toPath()))throw new IOException("RAW 保存记录不能是链接。");try(DataInputStream in=new DataInputStream(new android.util.AtomicFile(file).openRead())){if(in.readInt()!=0x52505031||in.readLong()!=source.length()||!sourceSha.equals(in.readUTF()))throw new IOException("RAW 保存记录与原图不符。");String uri=in.readUTF();boolean published=in.readBoolean();in.readUTF();if(!published&&!uri.isEmpty())throw new IOException("RAW 系统副本保存仍待确认。");if(!uri.isEmpty()&&exists(Uri.parse(uri))){cc.huevia.album.SharedGalleryPublication.verify(activity,uri,sourceSha,source.length(),cancel);gallery.allowDeletionUri(uri);if(!ids.contains(uri))ids.add(uri);}}}
        }
        return SharedJson.encode(SharedRuntime.map("ids",ids,"scope","recorded-export-copies"));
    }
    private static void write(File file,Map<String,Object> value)throws IOException{File temp=File.createTempFile("delete-",".part",file.getParentFile());try(FileOutputStream out=new FileOutputStream(temp)){out.write(SharedJson.encode(value).getBytes(StandardCharsets.UTF_8));out.getFD().sync();}try{Files.move(temp.toPath(),file.toPath(),StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);}finally{Files.deleteIfExists(temp.toPath());}}
    private static void check(BooleanSupplier cancel)throws InterruptedIOException{if(Thread.currentThread().isInterrupted()||cancel.getAsBoolean())throw new InterruptedIOException("删除已停止，当前系统确认可能已生效。");}
}
