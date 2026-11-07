package cc.huevia.album;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.BitmapRegionDecoder;
import android.graphics.ColorSpace;
import android.graphics.Rect;
import android.media.ExifInterface;
import cc.huevia.ncp.AdjustmentRegion;
import cc.huevia.ncp.PhotoCleanup;
import cc.huevia.ncp.PhotoCleanupEstimator;
import cc.huevia.ncp.PhotoGeometry;
import cc.huevia.ncp.PhotoPortrait;
import java.io.DataOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InterruptedIOException;
import java.io.OutputStream;
import java.security.DigestOutputStream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.BooleanSupplier;

/** Worker-only, bounded source analysis. Noise patches are decoded at real 100% resolution. */
public final class PhotoCleanupAnalyzer {
    private static final String MODEL="cleanup-source-sampling-v1";
    private static final int SAMPLE_EDGE=512, PATCH_EDGE=96;
    private static final Map<String,PhotoCleanup.Analysis> CACHE=
            new LinkedHashMap<String,PhotoCleanup.Analysis>(8,.75f,true){
                @Override protected boolean removeEldestEntry(Map.Entry<String,PhotoCleanup.Analysis> entry){return size()>8;}
            };
    private PhotoCleanupAnalyzer(){}

    @SuppressWarnings("deprecation")
    public static PhotoCleanup.Analysis analyze(File source,String sourceSha,AdjustmentRegion region,
                                                BooleanSupplier cancel)throws IOException{
        check(cancel);
        if(source==null||!source.isFile()||!validSha(sourceSha))throw new IOException("原图分析信息不完整。");
        long length=source.length(),modified=source.lastModified();
        if(length==0)throw new IOException("原图为空，无法分析。");
        verifySha(source,sourceSha,cancel);
        unchanged(source,length,modified);
        String key=cacheKey(source,sourceSha,length,modified,region,cancel);
        PhotoCleanup.Analysis cached;
        synchronized(CACHE){cached=CACHE.get(key);}
        check(cancel);
        if(cached!=null){unchanged(source,length,modified);return cached;}
        BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;
        BitmapFactory.decodeFile(source.getPath(),bounds);
        int rawWidth=bounds.outWidth,rawHeight=bounds.outHeight;
        if(rawWidth<1||rawHeight<1||rawWidth>65535||rawHeight>65535)throw new IOException("照片格式或尺寸暂不支持自动分析。");
        int exif=new ExifInterface(source.getPath()).getAttributeInt(ExifInterface.TAG_ORIENTATION,ExifInterface.ORIENTATION_NORMAL);
        if(exif<1||exif>8)exif=1;
        PhotoGeometry.Plan oriented=PhotoGeometry.NONE.plan(rawWidth,rawHeight,exif);
        AdjustmentRegion.Brush brush=region==null?null:region.compileBrush(oriented.width,oriented.height);
        Bitmap rawSample=null,sample=null;
        BitmapRegionDecoder decoder=null;
        try{
            BitmapFactory.Options options=options();
            while((Math.max(rawWidth,rawHeight)+options.inSampleSize-1)/options.inSampleSize>SAMPLE_EDGE)options.inSampleSize*=2;
            check(cancel);rawSample=BitmapFactory.decodeFile(source.getPath(),options);
            if(rawSample==null)throw new IOException("无法读取原图分析小样。");
            check(cancel);sample=PhotoComposition.apply(rawSample,PhotoGeometry.NONE,exif);
            if(sample!=rawSample){rawSample.recycle();rawSample=null;}
            int width=sample.getWidth(),height=sample.getHeight();
            if(Math.max(width,height)>SAMPLE_EDGE)throw new IOException("分析小样尺寸异常。");
            int[] pixels=new int[width*height];sample.getPixels(pixels,0,width,0,0,width,height);
            byte[] coverage=coverage(brush,width,height,cancel);
            List<double[]> centres=centres(brush,coverage,width,height,cancel);
            List<PhotoCleanupEstimator.Patch> patches=new ArrayList<>();int decodedPixels=0;
            if(!centres.isEmpty()&&rawWidth>=3&&rawHeight>=3){
                check(cancel);decoder=BitmapRegionDecoder.newInstance(source.getPath(),false);
                if(decoder==null||decoder.getWidth()!=rawWidth||decoder.getHeight()!=rawHeight)throw new IOException("原图暂不支持真实像素降噪分析。");
                Set<String> seen=new HashSet<>();
                for(double[] centre:centres){
                    check(cancel);double[] point=oriented.inverse(centre[0]*oriented.width,centre[1]*oriented.height);
                    int patchWidth=Math.min(PATCH_EDGE,rawWidth),patchHeight=Math.min(PATCH_EDGE,rawHeight);
                    int left=Math.max(0,Math.min(rawWidth-patchWidth,(int)Math.round(point[0]-patchWidth*.5)));
                    int top=Math.max(0,Math.min(rawHeight-patchHeight,(int)Math.round(point[1]-patchHeight*.5)));
                    Rect rect=new Rect(left,top,left+patchWidth,top+patchHeight);
                    if(!seen.add(rect.toShortString()))continue;
                    Bitmap patch=null;
                    try{
                        // Every patch gets independent options: never inherit the overview's inSampleSize.
                        patch=decoder.decodeRegion(rect,options());
                        if(patch==null||patch.getWidth()!=patchWidth||patch.getHeight()!=patchHeight)throw new IOException("原像素采样失败。");
                        check(cancel);int[] values=new int[patchWidth*patchHeight];patch.getPixels(values,0,patchWidth,0,0,patchWidth,patchHeight);
                        byte[] mask=null;
                        if(brush!=null){
                            mask=new byte[values.length];
                            for(int y=0;y<patchHeight;y++){
                                check(cancel);
                                for(int x=0;x<patchWidth;x++){
                                    double sx=left+x+.5,sy=top+y+.5;
                                    double nx=(oriented.a*sx+oriented.b*sy+oriented.c)/oriented.width;
                                    double ny=(oriented.d*sx+oriented.e*sy+oriented.f)/oriented.height;
                                    mask[y*patchWidth+x]=(byte)Math.round(brush.weight(nx,ny)*255);
                                }
                            }
                        }
                        patches.add(new PhotoCleanupEstimator.Patch(values,patchWidth,patchHeight,mask));decodedPixels+=values.length;
                    }finally{if(patch!=null)patch.recycle();}
                }
            }
            check(cancel);
            PhotoCleanup.Analysis result=PhotoCleanupEstimator.analyze(pixels,width,height,oriented.width,oriented.height,patches,coverage,cancel);
            if(result.sourceWidth!=oriented.width||result.sourceHeight!=oriented.height||result.patchCount!=patches.size()||result.patchPixels!=decodedPixels)throw new IOException("分析采样记录不一致。");
            check(cancel);unchanged(source,length,modified);
            synchronized(CACHE){CACHE.put(key,result);}
            return result;
        }finally{
            if(decoder!=null)decoder.recycle();
            if(sample!=null)sample.recycle();
            if(rawSample!=null&&rawSample!=sample)rawSample.recycle();
        }
    }

    private static BitmapFactory.Options options(){
        BitmapFactory.Options options=new BitmapFactory.Options();options.inSampleSize=1;options.inScaled=false;
        options.inPreferredConfig=Bitmap.Config.ARGB_8888;options.inPreferredColorSpace=ColorSpace.get(ColorSpace.Named.SRGB);
        return options;
    }
    private static byte[] coverage(AdjustmentRegion.Brush brush,int width,int height,BooleanSupplier cancel)throws IOException{
        if(brush==null)return null;
        byte[] values=new byte[width*height];
        for(int y=0;y<height;y++){check(cancel);for(int x=0;x<width;x++)values[y*width+x]=(byte)Math.round(brush.weight((x+.5)/width,(y+.5)/height)*255);}
        return values;
    }
    private static List<double[]> centres(AdjustmentRegion.Brush brush,byte[] mask,int width,int height,BooleanSupplier cancel)throws IOException{
        ArrayList<double[]> centres=new ArrayList<>();
        if(brush==null){for(int y=0;y<3;y++)for(int x=0;x<3;x++)centres.add(new double[]{(x+.5)/3,(y+.5)/3});return centres;}
        double spanX=brush.right-brush.left,spanY=brush.bottom-brush.top;
        if(spanX<=0||spanY<=0)return centres;
        double[] distances=new double[9];Arrays.fill(distances,Double.POSITIVE_INFINITY);double[][] points=new double[9][];
        for(int y=0;y<height;y++){
            check(cancel);
            for(int x=0;x<width;x++)if((mask[y*width+x]&255)>=192){
                double nx=(x+.5)/width,ny=(y+.5)/height;
                int col=Math.max(0,Math.min(2,(int)((nx-brush.left)/spanX*3))),row=Math.max(0,Math.min(2,(int)((ny-brush.top)/spanY*3))),index=row*3+col;
                double dx=nx-(brush.left+(col+.5)*spanX/3),dy=ny-(brush.top+(row+.5)*spanY/3),distance=dx*dx+dy*dy;
                if(distance<distances[index]){distances[index]=distance;points[index]=new double[]{nx,ny};}
            }
        }
        for(double[] point:points)if(point!=null)centres.add(point);
        return centres;
    }
    private static String cacheKey(File source,String sha,long length,long modified,AdjustmentRegion region,BooleanSupplier cancel)throws IOException{
        MessageDigest digest=digest();
        try(DataOutputStream out=new DataOutputStream(new DigestOutputStream(new OutputStream(){@Override public void write(int value){}},digest))){
            out.writeUTF(MODEL);out.writeUTF(PhotoCleanup.MODEL);out.writeUTF(sha.toLowerCase(java.util.Locale.ROOT));out.writeUTF(source.getCanonicalPath());out.writeLong(length);out.writeLong(modified);
            out.writeBoolean(region!=null);
            if(region!=null)for(PhotoPortrait.Stroke stroke:region.strokes){
                check(cancel);out.writeBoolean(stroke.erase);out.writeDouble(stroke.radius);out.writeDouble(stroke.feather);double[] points=stroke.points();out.writeInt(points.length);for(double value:points)out.writeDouble(value);
            }
        }
        return hex(digest.digest());
    }
    private static void verifySha(File source,String expected,BooleanSupplier cancel)throws IOException{
        MessageDigest digest=digest();byte[] buffer=new byte[65536];
        try(FileInputStream in=new FileInputStream(source)){int size;while((size=in.read(buffer))!=-1){check(cancel);digest.update(buffer,0,size);}}
        check(cancel);if(!hex(digest.digest()).equalsIgnoreCase(expected))throw new IOException("原图已变化，请重新打开后分析。");
    }
    private static boolean validSha(String value){if(value==null||value.length()!=64)return false;for(int i=0;i<value.length();i++){char c=value.charAt(i);if(!(c>='0'&&c<='9'||c>='a'&&c<='f'||c>='A'&&c<='F'))return false;}return true;}
    private static MessageDigest digest()throws IOException{try{return MessageDigest.getInstance("SHA-256");}catch(NoSuchAlgorithmException impossible){throw new IOException(impossible);}}
    private static String hex(byte[] bytes){char[] digits="0123456789abcdef".toCharArray(),value=new char[bytes.length*2];for(int i=0;i<bytes.length;i++){value[i*2]=digits[(bytes[i]>>>4)&15];value[i*2+1]=digits[bytes[i]&15];}return new String(value);}
    private static void unchanged(File source,long length,long modified)throws IOException{if(!source.isFile()||source.length()!=length||source.lastModified()!=modified)throw new IOException("原图已变化，请重新打开后分析。");}
    private static void check(BooleanSupplier cancel)throws InterruptedIOException{if(Thread.currentThread().isInterrupted()||cancel!=null&&cancel.getAsBoolean())throw new InterruptedIOException("已取消照片分析。");}
}
