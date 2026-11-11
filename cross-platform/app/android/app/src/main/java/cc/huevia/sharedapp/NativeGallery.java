package cc.huevia.sharedapp;

import android.content.Context;
import android.graphics.Bitmap;
import cc.huevia.album.LocalPhotoRepository;
import cc.huevia.album.PhotoSort;
import cc.huevia.album.PhotoEditStore;
import cc.huevia.library.SharedJson;
import cc.huevia.shared.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.function.BooleanSupplier;

/** Original MediaStore catalogue/thumbnail code; full originals stream natively. */
final class NativeGallery {
    private final Context context;
    private final SharedRuntime runtime;
    private final LocalPhotoRepository repository;
    private final LinkedHashMap<String,LocalPhotoRepository.PhonePhoto> known=new LinkedHashMap<>();
    NativeGallery(Context context,SharedRuntime runtime){this.context=context.getApplicationContext();this.runtime=runtime;repository=new LocalPhotoRepository(this.context);}
    String access()throws IOException{return SharedJson.encode(SharedRuntime.map("access",repository.access().name().toLowerCase(Locale.ROOT)));}
    synchronized String request(String operation,String json,BooleanSupplier cancel)throws IOException{
        Map<String,Object> p=SharedJson.object(json);
        if(operation.equals("gallery.access"))return access();
        if(operation.equals("gallery.page")){
            if(Boolean.TRUE.equals(p.get("refresh")))repository.invalidatePhoneIndex();
            int offset=SharedRuntime.integer(p,"offset",0);if(offset<0)throw new IOException("照片分页位置无效。");
            PhotoSort order=new PhotoSort(Boolean.TRUE.equals(p.get("added")),Boolean.TRUE.equals(p.get("oldest")));
            LocalPhotoRepository.Page page=repository.phonePage(offset,60,order,cancel);
            List<Object> rows=new ArrayList<>();
            for(LocalPhotoRepository.PhonePhoto photo:page.photos){known.put(photo.key,photo);rows.add(SharedRuntime.map("id",photo.key,"name",photo.filename,"raw",photo.raw(),"date",order.date(photo.takenDate,photo.date),"bytes",photo.bytes));}
            while(known.size()>600)known.remove(known.keySet().iterator().next());
            return SharedJson.encode(SharedRuntime.map("items",rows,"nextOffset",page.nextOffset,"hasMore",page.hasMore,"access",repository.access().name().toLowerCase(Locale.ROOT)));
        }
        LocalPhotoRepository.PhonePhoto photo=known.get(SharedRuntime.text(p,"id",2048));
        if(photo==null||repository.access()==LocalPhotoRepository.Access.NONE)throw new IOException("照片访问范围已变化，请刷新相册。");
        if(operation.equals("gallery.import")){
            InputStream input=context.getContentResolver().openInputStream(photo.uri);
            if(input==null)throw new IOException("无法打开所选照片。");
            return SharedImport.copy(input,photo.filename,false,runtime.root().getPath(),cancel);
        }
        if(!operation.equals("gallery.thumbnail"))throw new IOException("未知的手机相册操作。");
        File directory=new File(runtime.root(),"gallery-thumbnails");
        if(!directory.isDirectory()&&!directory.mkdirs())throw new IOException("无法创建照片缩略图目录。");
        String key=PhotoEditStore.hash((photo.thumbnailKey()+":384-v1").getBytes(StandardCharsets.UTF_8));
        File target=new File(directory,key+".jpg");
        if(Files.isSymbolicLink(target.toPath())||!target.getCanonicalFile().getParentFile().equals(directory.getCanonicalFile()))throw new IOException("缩略图路径无效。");
        if(target.isFile())return SharedJson.encode(SharedRuntime.map("path",target.getPath()));
        if(cancel.getAsBoolean())throw new InterruptedIOException("读取缩略图已取消。");
        Bitmap bitmap=repository.thumbnail(photo,384);if(bitmap==null)throw new IOException("暂时无法读取此照片的缩略图。");
        File temporary=File.createTempFile("thumb-",".part",directory);
        try{
            try(FileOutputStream out=new FileOutputStream(temporary)){if(!bitmap.compress(Bitmap.CompressFormat.JPEG,85,out))throw new IOException("缩略图编码失败。");out.getFD().sync();}
            if(cancel.getAsBoolean())throw new InterruptedIOException("读取缩略图已取消。");
            Files.move(temporary.toPath(),target.toPath(),StandardCopyOption.REPLACE_EXISTING);
        }finally{bitmap.recycle();Files.deleteIfExists(temporary.toPath());}
        File[] cached=directory.listFiles((dir,name)->name.matches("[0-9a-f]{64}\\.jpg"));
        if(cached!=null&&cached.length>256){Arrays.sort(cached,Comparator.comparingLong(File::lastModified));for(int i=0;i<cached.length-256;i++)Files.deleteIfExists(cached[i].toPath());}
        return SharedJson.encode(SharedRuntime.map("path",target.getPath()));
    }
}
