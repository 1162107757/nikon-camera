package cc.huevia.album;

import android.content.Context;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.provider.MediaStore;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.function.BooleanSupplier;

/** Adapts verified shared versions to the original byte-exact gallery journal. */
public final class SharedGalleryPublication {
    private SharedGalleryPublication() {}
    public static void verify(Context context,String address,String expectedSha,long bytes,BooleanSupplier cancel)throws IOException {
        if(address==null||!address.matches("content://media/(external|external_primary)/images/media/[0-9]+")||expectedSha==null||!expectedSha.matches("[0-9a-f]{64}")||bytes<4||bytes>512L*1024*1024)throw new IOException("相册保存记录无效。");
        Uri uri=Uri.parse(address);String[] columns=Build.VERSION.SDK_INT>=29?new String[]{MediaStore.Images.Media.OWNER_PACKAGE_NAME,MediaStore.Images.Media.IS_PENDING}:new String[]{MediaStore.Images.Media._ID};
        try(Cursor row=context.getContentResolver().query(uri,columns,null,null,null)){
            if(row==null||!row.moveToFirst())throw new IOException("此前保存的副本已不可访问，请保留应用内成品并重新导出。");
            if(Build.VERSION.SDK_INT>=29&&(!context.getPackageName().equals(row.getString(0))||row.getInt(1)!=0))throw new IOException("相册副本归属或保存状态已变化，未覆盖或重复保存。");
        }
        java.security.MessageDigest hash;try{hash=java.security.MessageDigest.getInstance("SHA-256");}catch(java.security.NoSuchAlgorithmException impossible){throw new AssertionError(impossible);}
        long total=0;byte[] buffer=new byte[65536];
        try(InputStream in=context.getContentResolver().openInputStream(uri)){
            if(in==null)throw new IOException("无法读取相册副本，请稍后重试。");int n;
            while((n=in.read(buffer))!=-1){check(cancel);total+=n;if(total>bytes)throw new IOException("相册副本已被修改，未覆盖或删除。");hash.update(buffer,0,n);}
        }
        StringBuilder actual=new StringBuilder();for(byte b:hash.digest())actual.append(String.format(java.util.Locale.ROOT,"%02x",b&255));
        if(total!=bytes||!expectedSha.contentEquals(actual))throw new IOException("相册副本已被修改，未覆盖或删除。");
    }
    public static String publish(Context context,File verified,String owner,String version,String filename,String expectedSha,long bytes,boolean extra,BooleanSupplier cancel)throws IOException {
        if(version==null||!version.matches("[0-9a-f]{64}")||expectedSha==null||!expectedSha.matches("[0-9a-f]{64}")||bytes<4||bytes>512L*1024*1024)throw new IOException("成品保存信息无效。");
        File root=context.getFilesDir().getCanonicalFile(),directory=new File(root,"photo-export-staging");
        if(Files.isSymbolicLink(directory.toPath())||(!directory.isDirectory()&&!directory.mkdirs())||!root.equals(directory.getCanonicalFile().getParentFile()))throw new IOException("相册暂存目录无效。");
        String identity=PhotoEditStore.hash((owner+"\n"+version).getBytes(StandardCharsets.UTF_8)).substring(0,32);
        File named=new File(directory,"export-"+identity+".JPG");
        if(Files.isSymbolicLink(named.toPath()))throw new IOException("相册暂存文件无效。");
        File stage=named.getCanonicalFile(),temporary=null;
        if(!directory.getCanonicalFile().equals(stage.getParentFile()))throw new IOException("相册暂存文件无效。");
        boolean own=false;
        try {
            check(cancel);
            if(!stage.exists()) {
                temporary=File.createTempFile("shared-publish-",".part",directory);
                try(InputStream in=new FileInputStream(verified);FileOutputStream out=new FileOutputStream(temporary)) {
                    int first=in.read(),second=in.read();if(first!=0xff||second!=0xd8)throw new IOException("成品不是完整的 JPEG，未保存到相册。");
                    out.write(first);out.write(second);long copied=2;byte[] buffer=new byte[65536];int n;
                    while((n=in.read(buffer))!=-1){check(cancel);copied+=n;if(copied>bytes)throw new IOException("成品内容已变化。");out.write(buffer,0,n);}
                    if(copied!=bytes)throw new IOException("成品尚未完整保存。");out.getFD().sync();
                }
                if(!PhotoEditStore.hashFile(temporary).equals(expectedSha))throw new IOException("成品校验失败，未保存到相册。");
                Files.move(temporary.toPath(),stage.toPath(),StandardCopyOption.ATOMIC_MOVE);temporary=null;
            }
            if(stage.length()!=bytes||!PhotoEditStore.hashFile(stage).equals(expectedSha))throw new IOException("上次相册暂存内容已变化，未覆盖或删除。");
            own=true;check(cancel);
            String name=filename==null?"":filename.replaceAll("[\\p{Cntrl}\\\\/]","_").trim();
            if(name.isEmpty())name="Huevia-"+version.substring(0,12)+".jpg";
            while(name.getBytes(StandardCharsets.UTF_8).length>180)name=name.substring(0,name.offsetByCodePoints(name.length(),-1));
            if(!name.toLowerCase(java.util.Locale.ROOT).matches(".*\\.jpe?g"))name+=".jpg";
            PhotoLiveGallery publisher=new PhotoLiveGallery(context);DownloadedPhoto photo=new DownloadedPhoto(stage,name,"","");
            String uri=publisher.publish(photo,extra);PhotoLiveGallery.PublicationState status=publisher.publicationStatus(photo);
            if((status.status!=PhotoLiveGallery.PublicationStatus.PUBLISHED&&status.status!=PhotoLiveGallery.PublicationStatus.EXISTING_SOURCE)||!uri.equals(status.uri))throw new IOException("相册副本尚未核对完成，应用内成品仍然保留，请重试。");
            check(cancel);return uri;
        } finally {
            if(temporary!=null)Files.deleteIfExists(temporary.toPath());
            if(own&&!Files.isSymbolicLink(stage.toPath())&&stage.isFile()&&stage.length()==bytes&&PhotoEditStore.hashFile(stage).equals(expectedSha))Files.deleteIfExists(stage.toPath());
        }
    }
    private static void check(BooleanSupplier cancel)throws InterruptedIOException {
        if(Thread.currentThread().isInterrupted()||(cancel!=null&&cancel.getAsBoolean()))throw new InterruptedIOException("保存照片已取消，应用内成品仍然保留。");
    }
}
