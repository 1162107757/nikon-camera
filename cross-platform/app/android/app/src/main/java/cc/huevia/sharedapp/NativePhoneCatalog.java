package cc.huevia.sharedapp;

import android.Manifest;
import android.content.ContentResolver;
import android.content.ContentUris;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.graphics.Bitmap;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.MediaStore;
import android.util.Size;
import cc.huevia.album.PhotoSort;
import cc.huevia.album.PhotoSourceFormat;
import cc.huevia.shared.SharedRuntime;
import java.io.*;
import java.util.*;
import java.util.concurrent.FutureTask;
import java.util.concurrent.TimeUnit;
import java.util.function.BooleanSupplier;

/** Read-only MediaStore catalogue. Filtering precedes paging, including mixed media. */
final class NativePhoneCatalog {
    static final class Entry {
        final Uri uri;
        final String id, name, mime, albumId, albumName;
        final long bytes, added, modified, taken, duration;
        final boolean video, raw;
        Boolean live;
        Entry(Uri uri, String name, String mime, long bytes, long added, long modified,
              long taken, long duration, boolean video, Boolean live, String albumId, String albumName) {
            this.uri=uri; id=uri.toString(); this.name=name==null?"照片":name;
            this.mime=mime==null?"":mime; this.bytes=bytes; this.added=added;
            this.modified=modified; this.taken=taken; this.duration=duration;
            this.video=video; this.raw=!video&&PhotoSourceFormat.raw(this.name,this.mime);
            this.live=raw||video?Boolean.FALSE:live;
            this.albumId=albumId==null?"other":albumId;
            this.albumName=albumName==null||albumName.isEmpty()?"其他相册":albumName;
        }
    }

    private final Context context;
    private final ContentResolver resolver;
    private List<Entry> index;
    private String permissionKey="";
    private final LinkedHashMap<String,Entry> known=new LinkedHashMap<>();
    NativePhoneCatalog(Context context){this.context=context.getApplicationContext();resolver=this.context.getContentResolver();}
    void invalidate(){index=null;}
    private boolean granted(String permission){return context.checkSelfPermission(permission)==PackageManager.PERMISSION_GRANTED;}
    private String access(boolean video){
        if(video)return "none";
        if(Build.VERSION.SDK_INT<33)return granted(Manifest.permission.READ_EXTERNAL_STORAGE)?"full":"none";
        if(granted(Manifest.permission.READ_MEDIA_IMAGES))return "full";
        return Build.VERSION.SDK_INT>=34&&granted(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)?"limited":"none";
    }
    Map<String,Object> access(){
        String image=access(false),video=access(true);
        return SharedRuntime.map("access",image.equals("full")||video.equals("full")?"full":!image.equals("none")||!video.equals("none")?"limited":"none",
            "imageAccess",image,"videoAccess",video,"canAsk",true);
    }
    private static void check(BooleanSupplier cancel)throws IOException{if(cancel.getAsBoolean())throw new InterruptedIOException("相册读取已取消。");}

    Map<String,Object> page(Map<String,Object> p,BooleanSupplier cancel)throws IOException {
        int offset=SharedRuntime.integer(p,"offset",0);
        if(offset<0)throw new IOException("相册分页位置无效。");
        String category=p.containsKey("category")?SharedRuntime.text(p,"category",16):"all";
        if(!Arrays.asList("all","image","live","raw").contains(category))throw new IOException("相册分类无效。");
        String query=p.containsKey("query")?SharedRuntime.text(p,"query",256).toLowerCase(Locale.ROOT):"";
        Object requestedAlbum=p.getOrDefault("album", "");
        if(!(requestedAlbum instanceof String)||((String)requestedAlbum).length()>256)throw new IOException("相册位置无效。");
        String album=(String)requestedAlbum;
        String permissions=access(false)+":"+access(true);
        if(Boolean.TRUE.equals(p.get("refresh"))||!permissions.equals(permissionKey))invalidate();
        if(index==null){
            List<Entry> all=new ArrayList<>();
            if(!access(false).equals("none"))read(false,all,cancel);
            check(cancel);index=all;permissionKey=permissions;
        }
        PhotoSort order=new PhotoSort(Boolean.TRUE.equals(p.get("added")),Boolean.TRUE.equals(p.get("oldest")));
        List<Entry> sorted=new ArrayList<>();
        for(Entry e:index){
            check(cancel);
            if(!album.isEmpty()&&!album.equals(e.albumId))continue;
            if(!e.name.toLowerCase(Locale.ROOT).contains(query))continue;
            if(category.equals("raw")&&!e.raw
                ||(category.equals("image")||category.equals("live"))&&(e.video||e.raw))continue;
            sorted.add(e);
        }
        sorted.sort((a,b)->order.compare(a.taken,a.added,a.id,b.taken,b.added,b.id));
        int cursor=Math.min(offset,sorted.size()),scanned=0;
        List<Object> rows=new ArrayList<>();
        while(cursor<sorted.size()&&rows.size()<60&&scanned++<300){
            check(cancel);Entry e=sorted.get(cursor++);
            boolean live=motion(e,cancel);
            if(category.equals("live")&&!live)continue;
            known.put(e.id,e);
            rows.add(SharedRuntime.map("id",e.id,"name",e.name,"raw",e.raw,"live",live,
                "mediaType",e.video?"video":"image","date",order.date(e.taken,e.added),"bytes",e.bytes,"duration",e.duration));
        }
        List<Object> albums=albums(cancel);
        while(known.size()>600)known.remove(known.keySet().iterator().next());
        if(!permissions.equals(access(false)+":"+access(true))){invalidate();throw new IOException("相册访问权限已变化，请重新加载。");}
        Map<String,Object> result=SharedRuntime.map("items",rows,"nextOffset",cursor,"hasMore",cursor<sorted.size(),"albums",albums);
        if(!category.equals("live"))result.put("total",sorted.size());
        return result;
    }

    private List<Object> albums(BooleanSupplier cancel)throws IOException {
        List<Entry> latest=new ArrayList<>(index);
        latest.sort((a,b)->Long.compare(Math.max(b.taken,b.added),Math.max(a.taken,a.added)));
        LinkedHashMap<String,Map<String,Object>> groups=new LinkedHashMap<>();
        Map<String,Object> all=SharedRuntime.map("id","","name","全部相册","count",latest.size());
        if(!latest.isEmpty()){all.put("cover",latest.get(0).id);known.put(latest.get(0).id,latest.get(0));}
        for(Entry e:latest){
            check(cancel);
            Map<String,Object> group=groups.get(e.albumId);
            if(group==null){group=SharedRuntime.map("id",e.albumId,"name",e.albumName,"count",0,"cover",e.id);groups.put(e.albumId,group);known.put(e.id,e);}
            group.put("count",((Number)group.get("count")).intValue()+1);
        }
        List<Object> result=new ArrayList<>();result.add(all);result.addAll(groups.values());return result;
    }

    private void read(boolean video,List<Entry> all,BooleanSupplier cancel)throws IOException {
        boolean xmp=!video&&Build.VERSION.SDK_INT>=30;
        try{read(video,xmp,all,cancel);}
        catch(IllegalArgumentException unsupported){if(!xmp)throw new IOException("无法读取手机相册。",unsupported);read(video,false,all,cancel);}
        catch(SecurityException denied){throw new IOException("相册权限已变化，请重新授权。",denied);}
    }
    private void read(boolean video,boolean xmp,List<Entry> all,BooleanSupplier cancel)throws IOException {
        Uri collection=video?MediaStore.Video.Media.EXTERNAL_CONTENT_URI:MediaStore.Images.Media.EXTERNAL_CONTENT_URI;
        List<String> columns=new ArrayList<>(Arrays.asList("_id","_display_name","mime_type","_size","date_added","date_modified","datetaken"));
        if(video)columns.add("duration");else if(xmp)columns.add("xmp");
        columns.add("bucket_id");columns.add("bucket_display_name");
        List<Entry> loaded=new ArrayList<>();
        try(Cursor cursor=resolver.query(collection,columns.toArray(new String[0]),null,null,null)){
            if(cursor==null)throw new IOException("系统未返回相册内容，请刷新重试。");
            while(cursor.moveToNext()){
                check(cancel);
                String name=cursor.getString(1),mime=cursor.getString(2);
                // Retain the editor's supported image formats; video is read-only preview.
                if(!video&&!"image/jpeg".equals(mime)&&!"image/png".equals(mime)&&!PhotoSourceFormat.raw(name,mime))continue;
                byte[] packet=!video&&xmp&&!cursor.isNull(7)?cursor.getBlob(7):null;
                loaded.add(new Entry(ContentUris.withAppendedId(collection,cursor.getLong(0)),name,mime,cursor.getLong(3),
                    Math.max(0,cursor.getLong(4))*1000L,Math.max(0,cursor.getLong(5)),Math.max(0,cursor.getLong(6)),
                    video?Math.max(0,cursor.getLong(7)):0,video,packet==null?null:MotionPhotoMetadata.isMotion(packet),cursor.getString(columns.indexOf("bucket_id")),cursor.getString(columns.indexOf("bucket_display_name"))));
            }
        }
        all.addAll(loaded);
    }
    private boolean motion(Entry e,BooleanSupplier cancel)throws IOException {
        if(e.live!=null)return e.live;
        check(cancel);
        // Some OEM providers omit indexed XMP. A bounded header read never decodes the original.
        try(InputStream input=resolver.openInputStream(e.uri)){
            if(input==null)return false;
            ByteArrayOutputStream header=new ByteArrayOutputStream();byte[] block=new byte[8192];int count;
            while(header.size()<256*1024&&(count=input.read(block,0,Math.min(block.length,256*1024-header.size())))>0){check(cancel);header.write(block,0,count);}
            e.live=MotionPhotoMetadata.isMotion(header.toByteArray());
        }catch(SecurityException denied){throw new IOException("照片权限已变化，请重新加载。",denied);}
        catch(InterruptedIOException cancelled){throw cancelled;}
        catch(IOException unavailable){return false;}
        return e.live;
    }
    Entry known(String id)throws IOException {
        Entry e=known.get(id);
        if(e==null||access(e.video).equals("none"))throw new IOException("照片访问范围已变化，请刷新相册。");
        // Re-query the URI so a limited-library revocation cannot use an old cached entry.
        try(Cursor cursor=resolver.query(e.uri,new String[]{"_id"},null,null,null)){
            if(cursor==null||!cursor.moveToFirst())throw new IOException("此项目已不可访问，请刷新相册。");
        }catch(SecurityException denied){throw new IOException("相册权限已变化，请重新选择。",denied);}
        return e;
    }
    Entry find(String id){return known.get(id);}
    Bitmap thumbnail(Entry e)throws IOException {
        try{
            if(Build.VERSION.SDK_INT>=29)return resolver.loadThumbnail(e.uri,new Size(384,384),null);
            android.media.MediaMetadataRetriever retriever=new android.media.MediaMetadataRetriever();
            try{
                retriever.setDataSource(context,e.uri);
                if(Build.VERSION.SDK_INT>=27)return retriever.getScaledFrameAtTime(0,android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC,384,384);
                Bitmap frame=retriever.getFrameAtTime(0,android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC);
                if(frame!=null&&Math.max(frame.getWidth(),frame.getHeight())>384){
                    double scale=384.0/Math.max(frame.getWidth(),frame.getHeight());
                    Bitmap small=Bitmap.createScaledBitmap(frame,Math.max(1,(int)(frame.getWidth()*scale)),Math.max(1,(int)(frame.getHeight()*scale)),true);frame.recycle();return small;
                }
                return frame;
            }
            finally{retriever.release();}
        }
        catch(RuntimeException failure){throw new IOException("暂时无法读取视频缩略图。",failure);}
    }
    Map<String,Object> preview(String id,BooleanSupplier cancel)throws IOException {
        Entry e=known(id);check(cancel);
        Intent view=new Intent(Intent.ACTION_VIEW).setDataAndType(e.uri,e.mime)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION|Intent.FLAG_ACTIVITY_NEW_TASK);
        view.setClipData(android.content.ClipData.newRawUri("media",e.uri));
        FutureTask<Void> show=new FutureTask<>(()->{context.startActivity(view);return null;});
        new Handler(Looper.getMainLooper()).post(show);
        try{show.get(5,TimeUnit.SECONDS);}
        catch(Exception failure){show.cancel(false);throw new IOException("无法打开系统预览，请安装可查看此文件的相册或播放器。",failure);}
        return SharedRuntime.map("opened",true);
    }
}
