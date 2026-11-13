package cc.huevia.sharedapp;

import android.graphics.*;
import android.media.ExifInterface;
import cc.huevia.album.RawDeveloper;
import cc.huevia.album.PhotoEditStore;
import cc.huevia.shared.SharedRuntime;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.function.BooleanSupplier;

/** Bounded, disposable display cache. Never replaces or registers the RAW. */
final class NativeRawThumbnail {
    static final class Callbacks {
        private final BooleanSupplier cancel;
        Callbacks(BooleanSupplier cancel){this.cancel=cancel;}
        public boolean cancelled(){return Thread.currentThread().isInterrupted()||cancel.getAsBoolean();}
        public void onProgress(double value){}
    }
    private static native byte[] embeddedJpeg(String path,Callbacks callbacks)throws IOException;
    private static native Bitmap preview(String path,int mode,int kelvin,int tint,int exposure,int highlights,int quality,Callbacks callbacks)throws IOException;
    static Map<String,Object> request(SharedRuntime runtime,File source,BooleanSupplier cancel)throws IOException {
        Callbacks callbacks=new Callbacks(cancel);check(callbacks);
        if(!RawDeveloper.available())throw new IOException("RAW 预览解码器不可用。");
        String sha=runtime.sourceIdentity(source.getPath(),true);
        File directory=new File(runtime.root(),"raw-thumbnails");
        if(Files.isSymbolicLink(directory.toPath())||!directory.isDirectory()&&!directory.mkdir())throw new IOException("RAW 预览目录不可用。");
        String key=PhotoEditStore.hash(("raw-thumb-v2\n"+sha+"\n"+RawDeveloper.libraryVersion()).getBytes(StandardCharsets.UTF_8));
        File target=new File(directory,key+".jpg");
        if(Files.isSymbolicLink(target.toPath()))throw new IOException("RAW 预览路径无效。");
        if(validCache(target)){check(callbacks);runtime.validateSource(source.getPath(),sha);target.setLastModified(System.currentTimeMillis());return SharedRuntime.map("path",target.getPath(),"sourceSha",sha);}
        check(callbacks);RawDeveloper.Info info=RawDeveloper.inspect(source);
        Bitmap decoded=null,small=null,oriented=null;boolean embedded=false;int orientation=info.exifOrientation;File temporary=File.createTempFile("raw-thumb-",".part",directory);
        try {
            byte[] bytes=embeddedJpeg(source.getPath(),callbacks);check(callbacks);
            if(bytes!=null){
                BitmapFactory.Options options=new BitmapFactory.Options();options.inJustDecodeBounds=true;BitmapFactory.decodeByteArray(bytes,0,bytes.length,options);
                if(options.outWidth>0&&options.outHeight>0&&(long)options.outWidth*options.outHeight<=60_000_000){
                    options.inSampleSize=1;while(Math.max(options.outWidth,options.outHeight)/options.inSampleSize>768)options.inSampleSize*=2;
                    options.inJustDecodeBounds=false;options.inScaled=false;options.inPreferredConfig=Bitmap.Config.ARGB_8888;
                    options.inPreferredColorSpace=ColorSpace.get(ColorSpace.Named.SRGB);decoded=BitmapFactory.decodeByteArray(bytes,0,bytes.length,options);
                    if(decoded!=null){embedded=true;ExifInterface metadata=new ExifInterface(new ByteArrayInputStream(bytes));String tag=metadata.getAttribute(ExifInterface.TAG_ORIENTATION);if(tag!=null){int value=metadata.getAttributeInt(ExifInterface.TAG_ORIENTATION,1);if(value>=1&&value<=8)orientation=value;}}
                }
            }
            // A RAW without an embedded JPEG gets an isolated half-resolution
            // sensor pass; it never creates a full-size editing source/cache.
            if(decoded==null)decoded=preview(source.getPath(),0,5500,0,0,2,0,callbacks);
            if(decoded==null)throw new IOException("此 RAW 未返回可用预览。");check(callbacks);
            Matrix matrix=new Matrix();switch(orientation){
                case 2:matrix.setScale(-1,1);break;case 3:matrix.setRotate(180);break;
                case 4:matrix.setScale(1,-1);break;case 5:matrix.setRotate(90);matrix.postScale(-1,1);break;
                case 6:matrix.setRotate(90);break;case 7:matrix.setRotate(270);matrix.postScale(-1,1);break;
                case 8:matrix.setRotate(270);break;default:break;
            }
            oriented=Bitmap.createBitmap(decoded,0,0,decoded.getWidth(),decoded.getHeight(),matrix,true);
            double scale=Math.min(1,512.0/Math.max(oriented.getWidth(),oriented.getHeight()));
            small=Bitmap.createScaledBitmap(oriented,Math.max(1,(int)Math.round(oriented.getWidth()*scale)),Math.max(1,(int)Math.round(oriented.getHeight()*scale)),true);
            try(FileOutputStream out=new FileOutputStream(temporary)){if(!small.compress(Bitmap.CompressFormat.JPEG,88,out))throw new IOException("无法写入 RAW 预览。");out.getFD().sync();}
            check(callbacks);runtime.validateSource(source.getPath(),sha);Files.move(temporary.toPath(),target.toPath(),StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);
            File[] cached=directory.listFiles((d,name)->name.matches("[a-f0-9]{64}\\.jpg"));
            if(cached!=null&&cached.length>64){Arrays.sort(cached,Comparator.comparingLong(File::lastModified));for(int i=0;i<cached.length-64;i++)if(!cached[i].equals(target)&&!Files.isSymbolicLink(cached[i].toPath()))Files.deleteIfExists(cached[i].toPath());}
            return SharedRuntime.map("path",target.getPath(),"sourceSha",sha,"width",small.getWidth(),"height",small.getHeight(),"embeddedPreview",embedded);
        }catch(OutOfMemoryError memory){throw new IOException("RAW 预览内存不足，请稍后重试。",memory);}
        finally{Files.deleteIfExists(temporary.toPath());if(small!=null&&small!=oriented&&small!=decoded)small.recycle();if(oriented!=null&&oriented!=decoded)oriented.recycle();if(decoded!=null)decoded.recycle();}
    }
    private static boolean validCache(File file){
        if(!file.isFile()||file.length()<4||file.length()>=4*1024*1024)return false;
        try(RandomAccessFile input=new RandomAccessFile(file,"r")){
            if(input.readUnsignedShort()!=0xffd8)return false;input.seek(file.length()-2);if(input.readUnsignedShort()!=0xffd9)return false;
            BitmapFactory.Options options=new BitmapFactory.Options();options.inJustDecodeBounds=true;BitmapFactory.decodeFile(file.getPath(),options);
            if(options.outWidth<1||options.outHeight<1||Math.max(options.outWidth,options.outHeight)>512)return false;
            Bitmap decoded=BitmapFactory.decodeFile(file.getPath());if(decoded==null)return false;decoded.recycle();return true;
        }catch(IOException|RuntimeException ignored){return false;}
    }
    private static void check(Callbacks callbacks)throws InterruptedIOException{if(callbacks.cancelled())throw new InterruptedIOException("RAW 预览已取消。");}
}
