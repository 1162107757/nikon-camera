package cc.huevia.sharedapp;

import android.content.Context;
import android.graphics.*;
import android.media.ExifInterface;
import cc.huevia.album.*;
import cc.huevia.ncp.*;
import java.io.*;
import java.util.function.*;

/** Codec adapter for non-JPEG originals and bounded previews; all effects remain original. */
final class NativeRaster {
    private static final String[] TAGS={"DateTime","DateTimeOriginal","DateTimeDigitized","SubSecTime","SubSecTimeOriginal","SubSecTimeDigitized","OffsetTime","OffsetTimeOriginal","OffsetTimeDigitized","Make","Model","LensMake","LensModel","ExposureTime","FNumber","ISOSpeedRatings","PhotographicSensitivity","ExposureProgram","ExposureBiasValue","MeteringMode","Flash","FocalLength","FocalLengthIn35mmFilm","WhiteBalance"};
    private NativeRaster(){}
    static void render(Context context,File source,File target,PresetPreviewProfile profile,PhotoExportSpec spec,boolean preview,BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        render(context,source,target,null,profile,spec,preview,cancel,progress);
    }
    static void render(Context context,File source,File target,File reference,PresetPreviewProfile profile,PhotoExportSpec spec,boolean preview,BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        Bitmap bitmap=null;
        try{
            check(cancel);BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;BitmapFactory.decodeFile(source.getPath(),bounds);
            if(bounds.outWidth<1||bounds.outHeight<1||(long)bounds.outWidth*bounds.outHeight>60_000_000)throw new IOException("原图尺寸无效或超过处理上限。");
            long needed=(long)bounds.outWidth*bounds.outHeight*(preview?1:12)+32L*1024*1024;
            long free=target.getParentFile().getUsableSpace();if(free>0&&free<needed)throw new IOException("存储空间不足，无法生成完整效果图。");
            ExifInterface original=new ExifInterface(source.getPath());int orientation=original.getAttributeInt(ExifInterface.TAG_ORIENTATION,1);if(orientation<1||orientation>8)orientation=1;
            BitmapFactory.Options options=new BitmapFactory.Options();options.inSampleSize=1;
            if(preview)while(Math.max(bounds.outWidth,bounds.outHeight)/options.inSampleSize>1280)options.inSampleSize*=2;
            options.inMutable=true;options.inScaled=false;options.inPreferredConfig=Bitmap.Config.ARGB_8888;options.inPreferredColorSpace=ColorSpace.get(ColorSpace.Named.SRGB);
            bitmap=BitmapFactory.decodeFile(source.getPath(),options);if(bitmap==null||!bitmap.isMutable()||bitmap.getConfig()!=Bitmap.Config.ARGB_8888||!ColorSpace.get(ColorSpace.Named.SRGB).equals(bitmap.getColorSpace()))throw new IOException("无法读取完整 sRGB 像素。");
            if(!preview&&(bitmap.getWidth()!=bounds.outWidth||bitmap.getHeight()!=bounds.outHeight))throw new IOException("原图尺寸不符，未缩小图片。");
            check(cancel);progress.accept(.1);final Bitmap working=bitmap;final int exif=orientation;
            profile.renderPixels(new SpatialPreviewFilter.Pixels(){
                public int width(){return working.getWidth();}public int height(){return working.getHeight();}
                public int exifOrientation(){return exif;}public File scratchDirectory(){return new File(context.getCacheDir(),"photo-adjustment-branches");}
                public void read(int[] pixels,int row,int rows){working.getPixels(pixels,0,width(),0,row,width(),rows);}
                public void write(int[] pixels,int row,int rows){working.setPixels(pixels,0,width(),0,row,width(),rows);}
            },cancel,value->progress.accept(.1+.7*value));
            check(cancel);Bitmap composed=PhotoComposition.apply(bitmap,GeometryPreviewProfile.geometry(profile),orientation);if(composed!=bitmap)bitmap.recycle();bitmap=composed;
            PhotoBorder border=BorderPreviewProfile.border(profile);
            if(!border.isNone()){Bitmap framed=new PhotoBorderRenderer(context.getAssets()).apply(bitmap,border,PhotoCaptureInfo.read(source));if(framed!=bitmap)bitmap.recycle();bitmap=framed;}
            PhotoExportSpec.Resolved resolved=spec.resolve(bitmap.getWidth(),bitmap.getHeight());check(cancel);
            if(bitmap.getWidth()!=resolved.width||bitmap.getHeight()!=resolved.height){Bitmap scaled=Bitmap.createScaledBitmap(bitmap,resolved.width,resolved.height,true);if(scaled!=bitmap)bitmap.recycle();bitmap=scaled;}
            if(reference!=null){try(FileOutputStream output=new FileOutputStream(reference)){if(!bitmap.compress(Bitmap.CompressFormat.PNG,100,output))throw new IOException("编码前像素保存失败。");output.flush();output.getFD().sync();}check(cancel);}
            try(FileOutputStream output=new FileOutputStream(target)){if(!bitmap.compress(Bitmap.CompressFormat.JPEG,resolved.quality,output))throw new IOException("效果图编码失败。");output.flush();output.getFD().sync();}
            check(cancel);ExifInterface result=new ExifInterface(target.getPath());for(String tag:TAGS){String value=original.getAttribute(tag);if(value!=null)result.setAttribute(tag,value);}
            result.setAttribute("Orientation","1");result.setAttribute("ColorSpace","1");result.setAttribute("ImageWidth",Integer.toString(bitmap.getWidth()));result.setAttribute("ImageLength",Integer.toString(bitmap.getHeight()));result.setAttribute("PixelXDimension",Integer.toString(bitmap.getWidth()));result.setAttribute("PixelYDimension",Integer.toString(bitmap.getHeight()));result.saveAttributes();PhotoExifRationals.preserve(source,target);
            try(FileOutputStream sync=new FileOutputStream(target,true)){sync.getFD().sync();}
            BitmapFactory.Options verify=new BitmapFactory.Options();verify.inJustDecodeBounds=true;BitmapFactory.decodeFile(target.getPath(),verify);
            if(verify.outWidth!=bitmap.getWidth()||verify.outHeight!=bitmap.getHeight()||!"image/jpeg".equals(verify.outMimeType))throw new IOException("效果图尺寸校验失败。");
            check(cancel);progress.accept(1);
        }catch(OutOfMemoryError exhausted){throw new IOException("完整尺寸处理内存不足，原文件已保留。",exhausted);}
        finally{if(bitmap!=null)bitmap.recycle();}
    }
    private static void check(BooleanSupplier cancel)throws InterruptedIOException{if(cancel.getAsBoolean()||Thread.currentThread().isInterrupted())throw new InterruptedIOException("照片处理已取消。");}
}
