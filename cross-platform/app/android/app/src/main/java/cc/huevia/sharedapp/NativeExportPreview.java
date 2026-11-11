package cc.huevia.sharedapp;

import android.content.Context;
import android.graphics.*;
import android.media.ExifInterface;
import cc.huevia.album.*;
import cc.huevia.library.SharedJson;
import cc.huevia.ncp.*;
import cc.huevia.shared.*;
import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.function.*;

/** Owns one frozen, real JPEG and the exact bitmap before its encoder. */
final class NativeExportPreview {
    private final Context context; private final SharedRuntime runtime;
    private Session session;
    private static final class Session {
        String id,owner,source,model,spec; PhotoEditStore.Draft draft;
        File folder,jpeg,reference,jpegDisplay,referenceDisplay;
        BitmapRegionDecoder before,after; int width,height;
        long length,modified;
    }
    NativeExportPreview(Context context,SharedRuntime runtime){
        this.context=context;this.runtime=runtime;
        // Only known, direct children of this app's own private preview root.
        File[] stale=new File(runtime.root(),"previews").listFiles();
        if(!Files.isSymbolicLink(new File(runtime.root(),"previews").toPath())&&stale!=null)for(File f:stale)if(f.getName().matches("export-[a-f0-9-]{36}"))remove(f);
    }
    private static void remove(File folder){
        if(Files.isSymbolicLink(folder.toPath()))return;
        File[] files=folder.listFiles();if(files!=null)for(File file:files)if(file.isFile()&&!Files.isSymbolicLink(file.toPath()))file.delete();
        folder.delete();
    }
    private void close(){Session s=session;session=null;if(s==null)return;
        if(s.before!=null)s.before.recycle();if(s.after!=null)s.after.recycle();remove(s.folder);
    }
    private static void check(BooleanSupplier cancel)throws InterruptedIOException{
        if(cancel.getAsBoolean()||Thread.currentThread().isInterrupted())throw new InterruptedIOException("成品预览已取消。");
    }
    private void valid(Session s)throws IOException{
        runtime.guardOwner(s.owner);File source=runtime.privateFile(s.source);
        if(source.length()!=s.length||source.lastModified()!=s.modified)throw new IOException("原图已变化，请重新打开成品预览。");
    }
    private static BitmapFactory.Options options(int sample){
        BitmapFactory.Options p=new BitmapFactory.Options();p.inSampleSize=sample;p.inScaled=false;
        p.inPreferredConfig=Bitmap.Config.ARGB_8888;p.inPreferredColorSpace=ColorSpace.get(ColorSpace.Named.SRGB);return p;
    }
    private static void normalize(File source,File target,int orientation,BooleanSupplier cancel)throws IOException{
        Bitmap bitmap=null;try{
            bitmap=BitmapFactory.decodeFile(source.getPath(),options(1));if(bitmap==null)throw new IOException("成品方向读取失败。");
            Bitmap next=PhotoComposition.apply(bitmap,PhotoGeometry.NONE,orientation);if(next!=bitmap)bitmap.recycle();bitmap=next;
            check(cancel);try(FileOutputStream out=new FileOutputStream(target)){if(!bitmap.compress(Bitmap.CompressFormat.PNG,100,out))throw new IOException("成品方向归一失败。");out.getFD().sync();}
        }finally{if(bitmap!=null)bitmap.recycle();}
    }
    String request(String operation,Map<String,Object> p,BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        check(cancel);
        if(operation.equals("media.exportPreview"))return create(p,cancel,progress);
        String id=SharedRuntime.text(p,"id",64);Session s=session;
        if(operation.equals("media.exportPreviewClose")){
            if(s!=null&&s.id.equals(id))close();return "{}";
        }
        if(s==null||!s.id.equals(id))throw new IOException("成品预览已失效，请重新打开。");
        valid(s);
        if(operation.equals("media.exportPreviewFrame"))return frame(s,p,cancel);
        if(operation.equals("media.exportPreviewCommit")){
            runtime.validateSource(s.source,s.draft.sourceSha);
            Map<String,Object> result=SharedRuntime.map("path",s.jpeg.getPath(),"width",s.width,"height",s.height,
                "bytes",s.jpeg.length(),"preview",false,"model",s.model,"exportSpec",s.spec);
            File exports=new File(runtime.root(),"exports");
            if(!exports.getCanonicalFile().equals(exports)||!exports.isDirectory()&&!exports.mkdirs())throw new IOException("成品输出目录不可用。");
            File staged=File.createTempFile("preview-confirm-",".jpg",exports);
            String expected=PhotoEditStore.hashFile(s.jpeg),saved;
            try{Files.copy(s.jpeg.toPath(),staged.toPath(),StandardCopyOption.REPLACE_EXISTING);
                saved=runtime.commitVersion(s.source,s.owner,s.draft,staged.getPath(),SharedJson.encode(result),cancel);
            }finally{Files.deleteIfExists(staged.toPath());}
            if(!expected.equals(SharedJson.object(saved).get("sha256")))throw new IOException("已有同设置成品与本次预览不同，请先在成品版本中核对旧结果。");
            runtime.markEditExported(s.owner,s.draft);close();return saved;
        }
        throw new IOException("未知的成品预览操作。");
    }
    private String create(Map<String,Object> p,BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        close();Session s=new Session();s.owner=SharedRuntime.text(p,"owner",64);s.source=SharedRuntime.text(p,"path",4096);
        File source=runtime.privateFile(s.source);s.draft=runtime.freezeEdit(s.source,s.owner,SharedJson.encode(SharedRuntime.object(p.get("recipe"))));
        runtime.validateSource(s.source,s.draft.sourceSha);s.length=source.length();s.modified=source.lastModified();
        if(source.getName().toLowerCase(Locale.ROOT).matches(".*\\.(nef|nrw|dng|arw|cr2|cr3|raf|rw2|orf|pef|srw)$"))throw new IOException("请完成 RAW 显影后预览成品。");
        s.id=UUID.randomUUID().toString();s.folder=new File(new File(runtime.root(),"previews"),"export-"+s.id);
        if(!s.folder.getCanonicalFile().equals(s.folder)||Files.isSymbolicLink(s.folder.toPath())||!s.folder.mkdirs())throw new IOException("无法创建成品预览目录。");
        s.jpeg=new File(s.folder,"encoded.jpg");s.reference=new File(s.folder,"reference.png");
        boolean ready=false;
        try{
            String size=SharedRuntime.text(p,"size",16);
            PhotoExportSpec spec=size.equals("custom")?PhotoExportSpec.custom(SharedRuntime.integer(p,"longEdge",2048),SharedRuntime.integer(p,"quality",95)):size.equals("share")?PhotoExportSpec.share():PhotoExportSpec.full();
            PresetPreviewProfile profile=s.draft.profile();BitmapFactory.Options info=new BitmapFactory.Options();info.inJustDecodeBounds=true;BitmapFactory.decodeFile(source.getPath(),info);
            if("image/jpeg".equals(info.outMimeType))PhotoPresetRenderer.forContext(context).renderWithReference(source,s.jpeg,s.reference,profile,spec,cancel,progress::accept);
            else NativeRaster.render(context,source,s.jpeg,s.reference,profile,spec,false,cancel,progress);
            check(cancel);valid(s);runtime.validateSource(s.source,s.draft.sourceSha);
            int orientation=new ExifInterface(s.jpeg.getPath()).getAttributeInt(ExifInterface.TAG_ORIENTATION,1);
            s.jpegDisplay=s.jpeg;s.referenceDisplay=s.reference;
            if(orientation>=2&&orientation<=8){
                s.jpegDisplay=new File(s.folder,"jpeg-oriented.png");s.referenceDisplay=new File(s.folder,"reference-oriented.png");
                normalize(s.jpeg,s.jpegDisplay,orientation,cancel);normalize(s.reference,s.referenceDisplay,orientation,cancel);
            }
            s.before=BitmapRegionDecoder.newInstance(s.referenceDisplay.getPath(),false);s.after=BitmapRegionDecoder.newInstance(s.jpegDisplay.getPath(),false);
            if(s.before==null||s.after==null)throw new IOException("成品区域读取不可用。");
            s.width=s.before.getWidth();s.height=s.before.getHeight();
            if(s.width!=s.after.getWidth()||s.height!=s.after.getHeight())throw new IOException("成品与编码前尺寸不符。");
            PhotoExportSpec.Resolved resolved=spec.resolve(s.width,s.height);s.spec=resolved.identity();s.model=SharedExportModel.of(profile,resolved);
            double overviewScale=Math.min(1,256.0/Math.max(s.width,s.height));
            int overviewWidth=Math.max(1,(int)Math.round(s.width*overviewScale)),overviewHeight=Math.max(1,(int)Math.round(s.height*overviewScale));
            File overview=new File(s.folder,"overview.png");
            surface(s.after,overview,overviewWidth,overviewHeight,Math.min(overviewWidth/(double)s.width,overviewHeight/(double)s.height),s.width/2.0,s.height/2.0,cancel);
            session=s;ready=true;return SharedJson.encode(SharedRuntime.map("id",s.id,"width",s.width,"height",s.height,
                "overview",overview.getPath(),"bytes",s.jpeg.length(),"sha256",PhotoEditStore.hashFile(s.jpeg),"quality",resolved.quality,"exportSpec",s.spec));
        }finally{if(!ready){if(s.before!=null)s.before.recycle();if(s.after!=null)s.after.recycle();remove(s.folder);}}
    }
    private static double number(Map<String,Object> p,String key,double fallback,double min,double max)throws IOException{
        Object v=p.get(key);if(v==null)return fallback;if(!(v instanceof Number))throw new IOException("预览视口数据无效。");
        double n=((Number)v).doubleValue();if(!Double.isFinite(n)||n<min||n>max)throw new IOException("预览视口数据超出范围。");return n;
    }
    private String frame(Session s,Map<String,Object> p,BooleanSupplier cancel)throws IOException{
        int w=SharedRuntime.integer(p,"width",0),h=SharedRuntime.integer(p,"height",0);
        if(w<1||h<1||w>4096||h>4096||(long)w*h>12000000)throw new IOException("预览视口尺寸过大。");
        double fit=Math.min(w/(double)s.width,h/(double)s.height);
        double scale=number(p,"scale",fit,Math.min(fit,.00001),32),cx=number(p,"cx",.5,0,1)*s.width,cy=number(p,"cy",.5,0,1)*s.height;
        File before=new File(s.folder,UUID.randomUUID()+".png"),after=new File(s.folder,UUID.randomUUID()+".png");boolean ready=false;
        try{
            surface(s.before,before,w,h,scale,cx,cy,cancel);surface(s.after,after,w,h,scale,cx,cy,cancel);
            check(cancel);valid(s);ready=true;return SharedJson.encode(SharedRuntime.map("before",before.getPath(),"jpeg",after.getPath(),"width",w,"height",h));
        }finally{if(!ready){before.delete();after.delete();}}
    }
    private static void surface(BitmapRegionDecoder decoder,File file,int w,int h,double scale,double cx,double cy,BooleanSupplier cancel)throws IOException{
        Bitmap canvasBitmap=null,tile=null;
        try{
            check(cancel);canvasBitmap=Bitmap.createBitmap(w,h,Bitmap.Config.ARGB_8888);Canvas canvas=new Canvas(canvasBitmap);canvas.drawColor(0xff0a0908);
            int sample=1;while(sample<64&&sample*2*scale<=1)sample*=2;
            // Include JPEG chroma neighbours, preserving all real pixels at 100%.
            int halo=32*sample;
            Rect region=new Rect(Math.max(0,(int)Math.floor(cx-w/(2*scale))-halo),Math.max(0,(int)Math.floor(cy-h/(2*scale))-halo),
                Math.min(decoder.getWidth(),(int)Math.ceil(cx+w/(2*scale))+halo),Math.min(decoder.getHeight(),(int)Math.ceil(cy+h/(2*scale))+halo));
            if(!region.isEmpty()){
                tile=decoder.decodeRegion(region,options(sample));if(tile==null)throw new IOException("成品区域解码失败。");
                RectF dest=new RectF((float)(w/2.0+(region.left-cx)*scale),(float)(h/2.0+(region.top-cy)*scale),
                    (float)(w/2.0+(region.right-cx)*scale),(float)(h/2.0+(region.bottom-cy)*scale));
                canvas.drawBitmap(tile,null,dest,new Paint(scale!=1?Paint.FILTER_BITMAP_FLAG:0));
            }
            check(cancel);try(FileOutputStream out=new FileOutputStream(file)){if(!canvasBitmap.compress(Bitmap.CompressFormat.PNG,100,out))throw new IOException("视口保存失败。");}
        }finally{if(tile!=null)tile.recycle();if(canvasBitmap!=null)canvasBitmap.recycle();}
    }
}
