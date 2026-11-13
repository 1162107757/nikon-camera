package cc.huevia.album;

import android.content.Context;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.function.BooleanSupplier;

/** Reuses the original NEF store and system publisher, including its persistent exact-byte receipt. */
public final class SharedRawGalleryPublication {
    private SharedRawGalleryPublication(){}
    public static synchronized String publish(Context context,File snapshot,String owner,String operation,String filename,String sha,long bytes,BooleanSupplier cancel)throws IOException {
        if(!operation.matches("[0-9a-f]{64}")||!sha.matches("[0-9a-f]{64}")||bytes<8||bytes>512L*1024*1024||snapshot.length()!=bytes||!PhotoEditStore.hashFile(snapshot).equals(sha))throw new IOException("NEF 原文件发布信息无效。");
        PhotoFormat.validateNef(snapshot,bytes);
        RawPhotoStore store=new RawPhotoStore(new File(context.getFilesDir(),"camera-raw"));
        String source=PhotoEditStore.hash(("shared-raw-publication-v1\n"+owner+"\n"+operation).getBytes(StandardCharsets.UTF_8));
        RawPhotoDownload saved=store.find(source);
        if(saved==null){File temporary=store.createTemporary();try{
            long copied=0;byte[] buffer=new byte[65536];int count;
            try(InputStream in=new FileInputStream(snapshot);FileOutputStream out=new FileOutputStream(temporary)){
                while((count=in.read(buffer))!=-1){check(cancel);copied+=count;if(copied>bytes)throw new IOException("NEF 原文件内容已变化。");out.write(buffer,0,count);}out.getFD().sync();
            }
            if(copied!=bytes||!PhotoEditStore.hashFile(temporary).equals(sha))throw new IOException("NEF 原文件暂存校验失败。");check(cancel);saved=store.commit(source,temporary,filename);
        }finally{Files.deleteIfExists(temporary.toPath());}}
        if(saved.byteSize()!=bytes||!saved.sha256().equals(sha))throw new IOException("上次 NEF 发布记录与此原文件不匹配。");
        check(cancel);String uri=new RawPhotoPublisher(context).publish(saved);SharedGalleryPublication.verify(context,uri,sha,bytes,cancel);
        // The application original remains in originals/. This is only the original
        // publisher's verified compatibility stage; its tiny receipts support a retry.
        File stage=saved.file();if(stage.isFile()&&stage.length()==bytes&&PhotoEditStore.hashFile(stage).equals(sha))Files.deleteIfExists(stage.toPath());
        return uri;
    }
    private static void check(BooleanSupplier cancel)throws IOException{if(Thread.currentThread().isInterrupted()||cancel.getAsBoolean())throw new InterruptedIOException("NEF 原文件保存已取消。");}
}
