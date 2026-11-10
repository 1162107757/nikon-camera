package cc.huevia.album;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.ColorSpace;
import cc.huevia.ncp.RawDevelopmentSettings;
import cc.huevia.ncp.RawJpegColorMatch;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.*;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.function.BooleanSupplier;
import java.util.function.DoubleConsumer;

/** Worker-only, full active-pixel LibRaw development into an immutable 8-bit sRGB PNG workspace. */
public final class RawDeveloper {
    private static final Object LOCK=new Object();
    private static final int RECORD_MAGIC=0x52445732,MAX_RECORD_BYTES=8192;
    private static final LinkedHashMap<String,RawJpegColorMatch.Fit> COLOR_FITS=new LinkedHashMap<>(8,.75f,true);
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
        public final boolean cameraColorApplied;
        public final String colorStatus;
        public final double colorErrorBefore,colorErrorAfter;
        Result(File file,Info info,String sourceSha,String identity,String workingSha,boolean cached,boolean applied,String status,double before,double after){workingFile=file;this.info=info;this.sourceSha=sourceSha;cacheIdentity=identity;this.workingSha=workingSha;this.cached=cached;cameraColorApplied=applied;colorStatus=status;colorErrorBefore=before;colorErrorAfter=after;}
    }
    public static Info inspect(File source)throws IOException{
        requireNative();File checked=source(source);Info info=nativeInspect(checked.getPath());validate(info);return info;
    }
    public static Result develop(Context context,File source,String owner,RawDevelopmentSettings settings,BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        if(context==null||settings==null)throw new IOException("缺少 RAW 显影环境或设置。");requireNative();NativeCallbacks callbacks=new NativeCallbacks(cancel,progress);callbacks.check();
        File original=source(source);String sourceSha=hashFile(original,callbacks),identity=cacheIdentity(sourceSha,settings);
        File root=directory(new File(context.getFilesDir(),"raw-development/"+hash((owner==null?"":owner).getBytes(StandardCharsets.UTF_8))),context.getFilesDir());
        File png=child(root,identity+".png"),record=child(root,identity+".record");if(original.equals(png)||original.equals(record))throw new IOException("RAW 原图不能作为显影输出。");
        synchronized(LOCK){
            callbacks.check();Result cached=readCache(png,record,sourceSha,identity,settings,callbacks);if(cached!=null){if(!sourceSha.equals(hashFile(original,callbacks)))throw new IOException("RAW 原图发生变化，未复用旧显影结果。");callbacks.onProgress(1);return cached;}
            Info info=inspect(original);callbacks.onProgress(.02);File temporary=File.createTempFile("develop-",".part",root);Bitmap bitmap=null;
            try{
                callbacks.check();Development developed=developPixels(original,owner,sourceSha,settings,callbacks);bitmap=developed.bitmap;
                callbacks.check();if(bitmap==null)throw new IOException("RAW 显影未返回完整图像。");info=info.dimensions(bitmap.getWidth(),bitmap.getHeight());validate(info);callbacks.onProgress(.95);
                MessageDigest workingDigest=algorithm();
                try(FileOutputStream file=new FileOutputStream(temporary);OutputStream checked=new CancellableOutputStream(new DigestOutputStream(file,workingDigest),callbacks)){
                    RawPngWriter.write(bitmap,checked,callbacks::cancelled,value->callbacks.onProgress(.95+.04*value));checked.flush();file.getFD().sync();
                }
                callbacks.check();if(!sourceSha.equals(hashFile(original,callbacks)))throw new IOException("显影期间 RAW 原图发生变化，未保存结果。");String workingSha=hex(workingDigest.digest());
                callbacks.onProgress(.995);move(temporary,png);writeRecord(record,sourceSha,identity,workingSha,info,settings,developed,callbacks);callbacks.check();callbacks.onProgress(1);return new Result(png,info,sourceSha,identity,workingSha,false,developed.applied,developed.status,developed.before,developed.after);
            }catch(OutOfMemoryError memory){throw new IOException("内存不足，无法显影这张完整尺寸 RAW。请关闭其他应用后重试。",memory);}
            finally{if(bitmap!=null&&!bitmap.isRecycled())bitmap.recycle();Files.deleteIfExists(temporary.toPath());}
        }
    }
    static String cacheIdentity(String sourceSha,RawDevelopmentSettings settings)throws IOException{
        requireNative();if(sourceSha==null||!sourceSha.matches("[a-f0-9]{64}")||settings==null)throw new IOException("RAW 缓存身份无效。");
        return hash(("raw-development-v2\0"+sourceSha+"\0"+settings.identity()+"\0"+RawJpegColorMatch.MODEL+"\0"+nativeVersion()).getBytes(StandardCharsets.UTF_8));
    }
    private static final class Development {
        final Bitmap bitmap;final boolean applied;final String status;final double before,after;
        Development(Bitmap bitmap,boolean applied,String status,double before,double after){this.bitmap=bitmap;this.applied=applied;this.status=status;this.before=before;this.after=after;}
    }
    private static Development developPixels(File source,String owner,String sourceSha,RawDevelopmentSettings settings,NativeCallbacks callbacks)throws IOException{
        Bitmap bitmap=null,baseline=null;
        try{
            RawJpegColorMatch.Fit fit=null;
            if(settings.colorMode==RawDevelopmentSettings.ColorMode.CAMERA_JPEG){
                String key=(owner==null?"":owner)+":"+sourceSha+":"+RawJpegColorMatch.MODEL+":"+nativeVersion();fit=COLOR_FITS.get(key);
                if(fit==null){
                    byte[] jpeg=nativeEmbeddedJpeg(source.getPath(),callbacks);callbacks.check();
                    Analysis reference=reference(jpeg);
                    if(reference==null)fit=RawJpegColorMatch.unavailable("NO_REFERENCE");
                    else{
                        // Always learn from camera WB / zero exposure, independently of user edits.
                        NativeCallbacks calibration=new NativeCallbacks(callbacks::cancelled,p->callbacks.onProgress(.02+.45*p));
                        baseline=nativeDevelop(source.getPath(),0,5500,0,0,2,3,calibration);
                        if(baseline==null)throw new IOException("RAW 色彩参考显影失败。");
                        callbacks.check();Analysis neutral=analysis(baseline);callbacks.onProgress(.47);
                        try{fit=RawJpegColorMatch.fit(neutral.pixels,neutral.width,neutral.height,reference.pixels,reference.width,reference.height,callbacks::cancelled);}
                        catch(InterruptedIOException cancelled){throw cancelled;}
                        catch(IOException unstable){fit=RawJpegColorMatch.unavailable("UNRELIABLE_FIT");}
                        callbacks.check();
                    }
                    if(!sourceSha.equals(hashFile(source,callbacks)))throw new IOException("RAW 原图发生变化，未保存色彩参考。");
                    COLOR_FITS.put(key,fit);while(COLOR_FITS.size()>8)COLOR_FITS.remove(COLOR_FITS.keySet().iterator().next());
                }
            }
            if(baseline!=null&&settings.whiteBalance==RawDevelopmentSettings.WhiteBalance.CAMERA&&settings.exposureTenths==0&&settings.highlightMode==2&&settings.demosaicQuality==3){bitmap=baseline;baseline=null;}
            else{
                if(baseline!=null){baseline.recycle();baseline=null;}
                NativeCallbacks actual=fit!=null?new NativeCallbacks(callbacks::cancelled,p->callbacks.onProgress(.50+.40*p)):callbacks;
                bitmap=nativeDevelop(source.getPath(),settings.whiteBalance.ordinal(),settings.temperatureKelvin,settings.tint,settings.exposureTenths,settings.highlightMode,settings.demosaicQuality,actual);
            }
            callbacks.check();if(bitmap==null)throw new IOException("RAW 显影未返回完整图像。");
            boolean applied=fit!=null&&fit.accepted;String status="中性色彩";double before=0,after=0;
            if(fit!=null){
                before=fit.beforeError;after=fit.afterError;
                if(applied){float[] table=fit.table();if(table.length>0)nativeApplyColor(bitmap,table,callbacks);status="相机 JPEG 色彩 · 近似还原";}
                else status=fit.reason.equals("NO_REFERENCE")?"无相机 JPEG 参考 · 已用中性色彩":"JPEG 色彩匹配不可靠 · 已用中性色彩";
            }
            callbacks.check();Bitmap output=bitmap;bitmap=null;return new Development(output,applied,status,before,after);
        }finally{if(bitmap!=null&&!bitmap.isRecycled())bitmap.recycle();if(baseline!=null&&!baseline.isRecycled())baseline.recycle();}
    }
    private static final class Analysis {final int width,height;final int[] pixels;Analysis(int width,int height,int[] pixels){this.width=width;this.height=height;this.pixels=pixels;}}
    private static Analysis analysis(Bitmap bitmap){
        double scale=Math.min(1,320.0/Math.max(bitmap.getWidth(),bitmap.getHeight()));int width=Math.max(1,(int)Math.round(bitmap.getWidth()*scale)),height=Math.max(1,(int)Math.round(bitmap.getHeight()*scale));
        Bitmap small=Bitmap.createScaledBitmap(bitmap,width,height,true);try{int[] pixels=new int[width*height];small.getPixels(pixels,0,width,0,0,width,height);return new Analysis(width,height,pixels);}finally{if(small!=bitmap)small.recycle();}
    }
    private static Analysis reference(byte[] jpeg){
        if(jpeg==null||jpeg.length<4||jpeg.length>16*1024*1024)return null;
        BitmapFactory.Options options=new BitmapFactory.Options();options.inJustDecodeBounds=true;BitmapFactory.decodeByteArray(jpeg,0,jpeg.length,options);
        if(options.outWidth<48||options.outHeight<48||options.outWidth>65535||options.outHeight>65535||(long)options.outWidth*options.outHeight>120_000_000)return null;
        int sample=1;while(Math.max(options.outWidth,options.outHeight)/(double)sample>640)sample*=2;
        options.inJustDecodeBounds=false;options.inSampleSize=sample;options.inScaled=false;options.inPreferredConfig=Bitmap.Config.ARGB_8888;options.inPreferredColorSpace=ColorSpace.get(ColorSpace.Named.SRGB);
        Bitmap bitmap=BitmapFactory.decodeByteArray(jpeg,0,jpeg.length,options);if(bitmap==null)return null;try{return analysis(bitmap);}finally{bitmap.recycle();}
    }
    private static Result readCache(File png,File record,String sourceSha,String identity,RawDevelopmentSettings settings,NativeCallbacks callbacks)throws IOException{
        if(!png.isFile()||!record.isFile())return null;if(record.length()<32||record.length()>MAX_RECORD_BYTES)return null;
        byte[] all=Files.readAllBytes(record.toPath()),body=Arrays.copyOf(all,all.length-32);if(!MessageDigest.isEqual(digest(body),Arrays.copyOfRange(all,body.length,all.length)))return null;
        try(DataInputStream input=new DataInputStream(new ByteArrayInputStream(body))){
            if(input.readInt()!=RECORD_MAGIC||!sourceSha.equals(input.readUTF())||!identity.equals(input.readUTF()))return null;
            String sha=input.readUTF();Info info=new Info(input.readInt(),input.readInt(),input.readInt(),input.readInt(),input.readInt(),input.readInt(),input.readUTF(),input.readUTF(),input.readUTF(),input.readUTF());
            if(!settings.equals(RawDevelopmentSettings.read(input)))return null;boolean applied=input.readBoolean();String status=input.readUTF();double before=input.readDouble(),after=input.readDouble();
            if(input.available()!=0||status.length()>160||!Double.isFinite(before)||!Double.isFinite(after)||before<0||after<0||!sha.equals(hashFile(png,callbacks)))return null;validate(info);
            BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;BitmapFactory.decodeFile(png.getPath(),bounds);
            if(bounds.outWidth!=info.width||bounds.outHeight!=info.height||!"image/png".equals(bounds.outMimeType))return null;return new Result(png,info,sourceSha,identity,sha,true,applied,status,before,after);
        }catch(EOFException|IllegalArgumentException invalid){return null;}
    }
    private static void writeRecord(File record,String sourceSha,String identity,String workingSha,Info info,RawDevelopmentSettings settings,Development developed,NativeCallbacks callbacks)throws IOException{
        ByteArrayOutputStream body=new ByteArrayOutputStream();try(DataOutputStream output=new DataOutputStream(body)){
            output.writeInt(RECORD_MAGIC);output.writeUTF(sourceSha);output.writeUTF(identity);output.writeUTF(workingSha);output.writeInt(info.width);output.writeInt(info.height);output.writeInt(info.rawWidth);output.writeInt(info.rawHeight);output.writeInt(info.bits);output.writeInt(info.exifOrientation);output.writeUTF(info.make);output.writeUTF(info.model);output.writeUTF(info.decoder);output.writeUTF(info.libRawVersion);settings.write(output);output.writeBoolean(developed.applied);output.writeUTF(developed.status);output.writeDouble(developed.before);output.writeDouble(developed.after);
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
    private static native byte[] nativeEmbeddedJpeg(String path,NativeCallbacks callbacks)throws IOException;
    private static native void nativeApplyColor(Bitmap bitmap,float[] table,NativeCallbacks callbacks)throws IOException;
    private static native Bitmap nativeDevelop(String path,int wbMode,int kelvin,int tint,int exposureTenths,int highlights,int quality,NativeCallbacks callbacks)throws IOException;
}
