package cc.huevia.album;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import cc.huevia.ncp.RawDevelopmentSettings;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.*;
import java.util.Arrays;
import java.util.function.BooleanSupplier;
import java.util.function.DoubleConsumer;

/** Worker-only, full active-pixel LibRaw development into an immutable 8-bit sRGB PNG workspace. */
public final class RawDeveloper {
    private static final Object LOCK=new Object();
    private static final int RECORD_MAGIC=0x52445731,MAX_RECORD_BYTES=8192;
    private static final long MAX_SOURCE_BYTES=1024L*1024*1024,MAX_PIXELS=60_000_000;
    private static final Throwable LOAD_FAILURE;
    static{Throwable failure=null;try{System.loadLibrary("raw");System.loadLibrary("huevia_raw");}catch(LinkageError|SecurityException missing){failure=missing;}LOAD_FAILURE=failure;}
    private RawDeveloper(){}
    public static boolean available(){return LOAD_FAILURE==null;}
    public static String libraryVersion(){return available()?nativeVersion():"unavailable";}
    private static void requireNative()throws IOException{if(!available())throw new IOException("此安装包缺少可用的 RAW 显影引擎。",LOAD_FAILURE);}
    public static final class Info {
        public final int width,height,rawWidth,rawHeight,bits,exifOrientation;
        public final String make,model,decoder,libRawVersion;
        public Info(int width,int height,int rawWidth,int rawHeight,int bits,int exifOrientation,String make,String model,String decoder,String libRawVersion){
            this.width=width;this.height=height;this.rawWidth=rawWidth;this.rawHeight=rawHeight;this.bits=bits;this.exifOrientation=exifOrientation;
            this.make=make==null?"":make;this.model=model==null?"":model;this.decoder=decoder==null?"":decoder;this.libRawVersion=libRawVersion==null?"":libRawVersion;
        }
        Info dimensions(int width,int height){return new Info(width,height,rawWidth,rawHeight,bits,exifOrientation,make,model,decoder,libRawVersion);}
    }
    public static final class Result {
        public final File workingFile;
        public final Info info;
        public final String sourceSha,cacheIdentity,workingSha;
        public final boolean cached;
        Result(File file,Info info,String sourceSha,String identity,String workingSha,boolean cached){workingFile=file;this.info=info;this.sourceSha=sourceSha;cacheIdentity=identity;this.workingSha=workingSha;this.cached=cached;}
    }
    public static Info inspect(File source)throws IOException{
        requireNative();File checked=source(source);Info info=nativeInspect(checked.getPath());validate(info);return info;
    }
    public static Result develop(Context context,File source,String owner,RawDevelopmentSettings settings,BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        if(context==null||settings==null)throw new IOException("缺少 RAW 显影环境或设置。");requireNative();NativeCallbacks callbacks=new NativeCallbacks(cancel,progress);callbacks.check();
        File original=source(source);String sourceSha=hashFile(original,callbacks),identity=hash(("raw-development-v1\0"+sourceSha+"\0"+settings.identity()+"\0"+nativeVersion()).getBytes(StandardCharsets.UTF_8));
        File root=directory(new File(context.getFilesDir(),"raw-development/"+hash((owner==null?"":owner).getBytes(StandardCharsets.UTF_8))),context.getFilesDir());
        File png=child(root,identity+".png"),record=child(root,identity+".record");if(original.equals(png)||original.equals(record))throw new IOException("RAW 原图不能作为显影输出。");
        synchronized(LOCK){
            callbacks.check();Result cached=readCache(png,record,sourceSha,identity,settings,callbacks);if(cached!=null){if(!sourceSha.equals(hashFile(original,callbacks)))throw new IOException("RAW 原图发生变化，未复用旧显影结果。");callbacks.onProgress(1);return cached;}
            Info info=inspect(original);callbacks.onProgress(.02);File temporary=File.createTempFile("develop-",".part",root);Bitmap bitmap=null;
            try{
                callbacks.check();bitmap=nativeDevelop(original.getPath(),settings.whiteBalance.ordinal(),settings.temperatureKelvin,settings.tint,settings.exposureTenths,settings.highlightMode,settings.demosaicQuality,callbacks);
                callbacks.check();if(bitmap==null)throw new IOException("RAW 显影未返回完整图像。");info=info.dimensions(bitmap.getWidth(),bitmap.getHeight());validate(info);callbacks.onProgress(.91);
                try(FileOutputStream file=new FileOutputStream(temporary);OutputStream checked=new CancellableOutputStream(file,callbacks)){
                    if(!bitmap.compress(Bitmap.CompressFormat.PNG,100,checked))throw new IOException("无法写入 RAW 显影工作图。");checked.flush();file.getFD().sync();
                }
                callbacks.check();if(!sourceSha.equals(hashFile(original,callbacks)))throw new IOException("显影期间 RAW 原图发生变化，未保存结果。");String workingSha=hashFile(temporary,callbacks);
                callbacks.onProgress(.97);move(temporary,png);writeRecord(record,sourceSha,identity,workingSha,info,settings,callbacks);callbacks.check();callbacks.onProgress(1);return new Result(png,info,sourceSha,identity,workingSha,false);
            }catch(OutOfMemoryError memory){throw new IOException("内存不足，无法显影这张完整尺寸 RAW。请关闭其他应用后重试。",memory);}
            finally{if(bitmap!=null&&!bitmap.isRecycled())bitmap.recycle();Files.deleteIfExists(temporary.toPath());}
        }
    }
    private static Result readCache(File png,File record,String sourceSha,String identity,RawDevelopmentSettings settings,NativeCallbacks callbacks)throws IOException{
        if(!png.isFile()||!record.isFile())return null;if(record.length()<32||record.length()>MAX_RECORD_BYTES)return null;
        byte[] all=Files.readAllBytes(record.toPath()),body=Arrays.copyOf(all,all.length-32);if(!MessageDigest.isEqual(digest(body),Arrays.copyOfRange(all,body.length,all.length)))return null;
        try(DataInputStream input=new DataInputStream(new ByteArrayInputStream(body))){
            if(input.readInt()!=RECORD_MAGIC||!sourceSha.equals(input.readUTF())||!identity.equals(input.readUTF()))return null;
            String sha=input.readUTF();Info info=new Info(input.readInt(),input.readInt(),input.readInt(),input.readInt(),input.readInt(),input.readInt(),input.readUTF(),input.readUTF(),input.readUTF(),input.readUTF());
            if(!settings.equals(RawDevelopmentSettings.read(input))||input.available()!=0||!sha.equals(hashFile(png,callbacks)))return null;validate(info);
            BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;BitmapFactory.decodeFile(png.getPath(),bounds);
            if(bounds.outWidth!=info.width||bounds.outHeight!=info.height||!"image/png".equals(bounds.outMimeType))return null;return new Result(png,info,sourceSha,identity,sha,true);
        }catch(EOFException|IllegalArgumentException invalid){return null;}
    }
    private static void writeRecord(File record,String sourceSha,String identity,String workingSha,Info info,RawDevelopmentSettings settings,NativeCallbacks callbacks)throws IOException{
        ByteArrayOutputStream body=new ByteArrayOutputStream();try(DataOutputStream output=new DataOutputStream(body)){
            output.writeInt(RECORD_MAGIC);output.writeUTF(sourceSha);output.writeUTF(identity);output.writeUTF(workingSha);output.writeInt(info.width);output.writeInt(info.height);output.writeInt(info.rawWidth);output.writeInt(info.rawHeight);output.writeInt(info.bits);output.writeInt(info.exifOrientation);output.writeUTF(info.make);output.writeUTF(info.model);output.writeUTF(info.decoder);output.writeUTF(info.libRawVersion);settings.write(output);
        }
        byte[] bytes=body.toByteArray();if(bytes.length+32>MAX_RECORD_BYTES)throw new IOException("RAW 显影记录过大。");File temp=File.createTempFile("record-",".part",record.getParentFile());
        try{try(FileOutputStream output=new FileOutputStream(temp)){output.write(bytes);output.write(digest(bytes));output.getFD().sync();}callbacks.check();move(temp,record);}finally{Files.deleteIfExists(temp.toPath());}
    }
    private static void move(File source,File target)throws IOException{try{Files.move(source.toPath(),target.toPath(),StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);}catch(AtomicMoveNotSupportedException unsupported){Files.move(source.toPath(),target.toPath(),StandardCopyOption.REPLACE_EXISTING);}}
    private static File source(File source)throws IOException{if(source==null||!source.isFile()||Files.isSymbolicLink(source.toPath()))throw new IOException("RAW 原图不存在或路径无效。");File checked=source.getCanonicalFile();if(checked.length()<64||checked.length()>MAX_SOURCE_BYTES)throw new IOException("RAW 原图大小无效或超出 1GB 限制。");return checked;}
    private static File directory(File directory,File base)throws IOException{File canonicalBase=base.getCanonicalFile(),checked=directory.getCanonicalFile();if(!checked.toPath().startsWith(canonicalBase.toPath())||checked.equals(canonicalBase)||!checked.isDirectory()&&!checked.mkdirs())throw new IOException("无法创建 RAW 显影工作目录。");return checked;}
    private static File child(File directory,String name)throws IOException{File file=new File(directory,name);if(!file.getCanonicalFile().equals(file)||Files.isSymbolicLink(file.toPath()))throw new IOException("RAW 显影输出路径无效。");return file;}
    private static void validate(Info info)throws IOException{if(info==null||info.width<1||info.height<1||info.width>65535||info.height>65535||((long)info.width)*info.height>MAX_PIXELS||info.rawWidth<1||info.rawHeight<1)throw new IOException("RAW 完整尺寸不支持或超出 6000 万像素限制。");}
    private static String hashFile(File file,NativeCallbacks callbacks)throws IOException{MessageDigest hash=algorithm();byte[] buffer=new byte[65536];try(InputStream input=Files.newInputStream(file.toPath())){int n;while((n=input.read(buffer))!=-1){callbacks.check();hash.update(buffer,0,n);}}return hex(hash.digest());}
    private static String hash(byte[] bytes){return hex(digest(bytes));}private static byte[] digest(byte[] bytes){return algorithm().digest(bytes);}private static MessageDigest algorithm(){try{return MessageDigest.getInstance("SHA-256");}catch(NoSuchAlgorithmException impossible){throw new AssertionError(impossible);}}private static String hex(byte[] bytes){StringBuilder text=new StringBuilder(64);for(byte b:bytes)text.append(Character.forDigit((b>>>4)&15,16)).append(Character.forDigit(b&15,16));return text.toString();}
    private static final class CancellableOutputStream extends FilterOutputStream {
        final NativeCallbacks callbacks;CancellableOutputStream(OutputStream output,NativeCallbacks callbacks){super(output);this.callbacks=callbacks;}
        @Override public void write(byte[] bytes,int offset,int count)throws IOException{callbacks.check();out.write(bytes,offset,count);}
        @Override public void write(int value)throws IOException{callbacks.check();out.write(value);}
    }
    /** JNI calls remain on the initiating worker; OpenMP is not enabled in this build. */
    private static final class NativeCallbacks {
        final BooleanSupplier cancel;final DoubleConsumer progress;double last;
        NativeCallbacks(BooleanSupplier cancel,DoubleConsumer progress){this.cancel=cancel;this.progress=progress;}
        public boolean cancelled(){return Thread.currentThread().isInterrupted()||cancel!=null&&cancel.getAsBoolean();}
        void check()throws InterruptedIOException{if(cancelled())throw new InterruptedIOException("RAW 显影已取消。");}
        public void onProgress(double value){double next=Math.max(last,Math.max(0,Math.min(1,value)));if(next!=last){last=next;if(progress!=null)progress.accept(next);}}
    }
    private static native String nativeVersion();
    private static native Info nativeInspect(String path)throws IOException;
    private static native Bitmap nativeDevelop(String path,int wbMode,int kelvin,int tint,int exposureTenths,int highlights,int quality,NativeCallbacks callbacks)throws IOException;
}
