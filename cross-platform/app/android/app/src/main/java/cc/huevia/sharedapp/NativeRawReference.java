package cc.huevia.sharedapp;

import android.content.Context;
import android.graphics.*;
import cc.huevia.album.RawDeveloper;
import cc.huevia.ncp.RawDevelopmentSettings;
import cc.huevia.ncp.RawJpegColorMatch;
import cc.huevia.shared.SharedRawReference;
import java.io.*;
import java.util.LinkedHashMap;
import java.util.function.BooleanSupplier;

/** Fits only bounded analysis pixels; applies colour to the decoded RAW copy. */
final class NativeRawReference {
    private static final LinkedHashMap<String,RawJpegColorMatch.Fit> FITS=new LinkedHashMap<>(8,.75f,true);
    private NativeRawReference(){}
    static void validate(File file)throws IOException{analysis(file);}
    static RawJpegColorMatch.Fit fit(Context context,File source,String owner,String sourceSha,SharedRawReference.Reference reference,BooleanSupplier cancel)throws IOException{
        reference.verifySource(sourceSha);
        String identity=owner+":"+sourceSha+":"+reference.sha256+":"+RawJpegColorMatch.MODEL;
        synchronized(FITS){RawJpegColorMatch.Fit previous=FITS.get(identity);if(previous!=null)return previous;}
        RawDeveloper.Result baseline=RawDeveloper.develop(context,source,owner,RawDevelopmentSettings.DEFAULT.withColorMode(RawDevelopmentSettings.ColorMode.NEUTRAL),cancel,v->{});
        reference.verifySource(baseline.sourceSha);
        Analysis raw=analysis(baseline.workingFile),jpeg=analysis(reference.file);
        RawJpegColorMatch.Fit fit;
        try{fit=RawJpegColorMatch.fit(raw.pixels,raw.width,raw.height,jpeg.pixels,jpeg.width,jpeg.height,cancel);}
        catch(InterruptedIOException stopped){throw stopped;}
        catch(IOException unreliable){fit=RawJpegColorMatch.unavailable("UNRELIABLE_FIT");}
        reference.verify(cancel);
        synchronized(FITS){FITS.put(identity,fit);while(FITS.size()>8)FITS.remove(FITS.keySet().iterator().next());}
        return fit;
    }
    static void apply(Bitmap bitmap,RawJpegColorMatch.Fit fit,BooleanSupplier cancel)throws IOException{
        if(!fit.accepted||fit.table().length==0)return;
        int width=bitmap.getWidth();int[] row=new int[width];
        for(int y=0;y<bitmap.getHeight();y++){
            if(cancel.getAsBoolean())throw new InterruptedIOException("JPEG 色彩匹配已取消。");
            bitmap.getPixels(row,0,width,0,y,width,1);for(int x=0;x<width;x++)row[x]=fit.applyArgb(row[x]);bitmap.setPixels(row,0,width,0,y,width,1);
        }
    }
    static String status(RawJpegColorMatch.Fit fit){return fit.accepted?"EXTERNAL_MATCHED":"EXTERNAL_"+fit.reason;}
    private static final class Analysis {final int[] pixels;final int width,height;Analysis(int[] p,int w,int h){pixels=p;width=w;height=h;}}
    private static Analysis analysis(File file)throws IOException{
        BitmapFactory.Options options=new BitmapFactory.Options();options.inJustDecodeBounds=true;BitmapFactory.decodeFile(file.getPath(),options);
        if(options.outWidth<48||options.outHeight<48||options.outWidth>65535||options.outHeight>65535||(long)options.outWidth*options.outHeight>120_000_000)throw new IOException("JPEG 参考尺寸无效，请选择同一张照片的完整 JPEG。");
        options.inSampleSize=1;while(Math.max(options.outWidth,options.outHeight)/(double)options.inSampleSize>640)options.inSampleSize*=2;
        options.inJustDecodeBounds=false;options.inScaled=false;options.inMutable=true;options.inPreferredConfig=Bitmap.Config.ARGB_8888;options.inPreferredColorSpace=ColorSpace.get(ColorSpace.Named.SRGB);
        Bitmap decoded=BitmapFactory.decodeFile(file.getPath(),options),small=null;
        if(decoded==null)throw new IOException("JPEG 参考无法解码。");
        try{double scale=Math.min(1,320.0/Math.max(decoded.getWidth(),decoded.getHeight()));int width=Math.max(1,(int)Math.round(decoded.getWidth()*scale)),height=Math.max(1,(int)Math.round(decoded.getHeight()*scale));small=Bitmap.createScaledBitmap(decoded,width,height,true);int[] pixels=new int[width*height];small.getPixels(pixels,0,width,0,0,width,height);return new Analysis(pixels,width,height);}
        finally{if(small!=null&&small!=decoded)small.recycle();decoded.recycle();}
    }
}
