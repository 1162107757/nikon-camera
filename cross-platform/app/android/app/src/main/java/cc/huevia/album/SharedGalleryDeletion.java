package cc.huevia.album;

import android.content.Context;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.function.BooleanSupplier;

/** Restores the deterministic publisher input only to read its verified original journal. */
public final class SharedGalleryDeletion {
    private SharedGalleryDeletion(){}
    public static String published(Context context,File source,String owner,String version,String sha,long bytes,BooleanSupplier cancel)throws IOException {
        return published(context,source,owner,version,sha,bytes,false,cancel);
    }
    public static String published(Context context,File source,String owner,String version,String sha,long bytes,boolean original,BooleanSupplier cancel)throws IOException {
        if(!version.matches("[0-9a-f]{64}")||!sha.matches("[0-9a-f]{64}")||source.length()!=bytes||!PhotoEditStore.hashFile(source).equals(sha))throw new IOException("成品内容已变化，未查询系统删除范围。");
        File root=context.getFilesDir().getCanonicalFile(),directory=new File(root,"photo-export-staging");if(Files.isSymbolicLink(directory.toPath())||(!directory.isDirectory()&&!directory.mkdirs())||!directory.getCanonicalFile().getParentFile().equals(root))throw new IOException("系统相册记录路径无效。");
        String identity=PhotoEditStore.hash((owner+"\n"+version).getBytes(StandardCharsets.UTF_8)).substring(0,32);File stage=new File(directory,"export-"+identity+".JPG");if(Files.isSymbolicLink(stage.toPath()))throw new IOException("系统相册暂存路径无效。");boolean created=false;
        try {
            if(!stage.exists()){File temp=File.createTempFile("delete-read-",".part",directory);try{try(InputStream in=new FileInputStream(source);FileOutputStream out=new FileOutputStream(temp)){byte[] block=new byte[65536];int n;while((n=in.read(block))!=-1){if(cancel.getAsBoolean())throw new InterruptedIOException("删除范围读取已停止。");out.write(block,0,n);}out.getFD().sync();}Files.move(temp.toPath(),stage.toPath(),StandardCopyOption.ATOMIC_MOVE);created=true;}finally{Files.deleteIfExists(temp.toPath());}}
            if(stage.length()!=bytes||!PhotoEditStore.hashFile(stage).equals(sha))throw new IOException("系统相册暂存内容已变化。");
            PhotoLiveGallery publisher=new PhotoLiveGallery(context);DownloadedPhoto photo=new DownloadedPhoto(stage,"Huevia.jpg","","");PhotoLiveGallery.PublicationState state=original?publisher.exactPublicationStatus(photo):publisher.publicationStatus(photo);
            if(state.status==PhotoLiveGallery.PublicationStatus.PENDING)throw new IOException("系统相册保存仍待确认，请先核对该成品。");
            return state.status==PhotoLiveGallery.PublicationStatus.PUBLISHED?state.uri:"";
        }finally{if(created&&stage.isFile()&&stage.length()==bytes&&PhotoEditStore.hashFile(stage).equals(sha))Files.deleteIfExists(stage.toPath());}
    }
}
