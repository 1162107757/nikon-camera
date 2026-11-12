package cc.huevia.shared;

import cc.huevia.library.SharedJson;
import cc.huevia.ncp.*;
import java.io.*;
import java.util.*;
import java.util.function.BooleanSupplier;

/** Original estimator, using a bounded overview and independent full-resolution patches. */
public final class SharedCleanup {
    private SharedCleanup(){}
    public static String analyze(SpatialPreviewFilter.Pixels original,SpatialPreviewFilter.Pixels overview,BooleanSupplier cancel)throws IOException{
        return analyze(original,overview,null,cancel);
    }
    public static String analyze(SpatialPreviewFilter.Pixels original,SpatialPreviewFilter.Pixels overview,AdjustmentRegion region,BooleanSupplier cancel)throws IOException{
        check(cancel);
        int width=original.width(),height=original.height(),sw=overview.width(),sh=overview.height();
        if(width<1||height<1||sw<1||sh<1||sw>512||sh>512)throw new IOException("去灰分析尺寸无效。");
        int[] sample=new int[sw*sh];overview.read(sample,0,sh);
        PhotoGeometry.Plan oriented=PhotoGeometry.NONE.plan(width,height,original.exifOrientation());
        AdjustmentRegion.Brush brush=region==null?null:region.compileBrush(oriented.width,oriented.height);
        byte[] coverage=null;
        if(brush!=null){
            coverage=new byte[sw*sh];
            for(int y=0;y<sh;y++){check(cancel);for(int x=0;x<sw;x++)coverage[y*sw+x]=(byte)Math.round(brush.weight((x+.5)/sw,(y+.5)/sh)*255);}
        }
        List<double[]> centres=centres(brush,coverage,sw,sh,cancel);
        List<PhotoCleanupEstimator.Patch> patches=new ArrayList<>();Set<String> seen=new HashSet<>();
        if(width>=3&&height>=3){
            int pw=Math.min(96,width),ph=Math.min(96,height);int[] row=new int[width];
            for(double[] centre:centres){
                check(cancel);double[] point=oriented.inverse(centre[0]*oriented.width,centre[1]*oriented.height);
                int left=Math.max(0,Math.min(width-pw,(int)Math.round(point[0]-pw*.5))),top=Math.max(0,Math.min(height-ph,(int)Math.round(point[1]-ph*.5)));
                if(!seen.add(left+":"+top))continue;
                int[] pixels=new int[pw*ph];for(int j=0;j<ph;j++){check(cancel);original.read(row,top+j,1);System.arraycopy(row,left,pixels,j*pw,pw);}
                byte[] mask=null;
                if(brush!=null){
                    mask=new byte[pixels.length];
                    for(int y=0;y<ph;y++){
                        check(cancel);
                        for(int x=0;x<pw;x++){
                            double sx=left+x+.5,sy=top+y+.5;
                            double nx=(oriented.a*sx+oriented.b*sy+oriented.c)/oriented.width;
                            double ny=(oriented.d*sx+oriented.e*sy+oriented.f)/oriented.height;
                            mask[y*pw+x]=(byte)Math.round(brush.weight(nx,ny)*255);
                        }
                    }
                }
                patches.add(new PhotoCleanupEstimator.Patch(pixels,pw,ph,mask));
            }
        }
        return result(PhotoCleanupEstimator.analyze(sample,sw,sh,oriented.width,oriented.height,patches,coverage,cancel));
    }
    private static List<double[]> centres(AdjustmentRegion.Brush brush,byte[] mask,int width,int height,BooleanSupplier cancel)throws IOException{
        List<double[]> centres=new ArrayList<>();
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
    public static String result(PhotoCleanup.Analysis analysis)throws IOException{
        ByteArrayOutputStream output=new ByteArrayOutputStream();new PhotoCleanup(100,100,100,analysis).write(new DataOutputStream(output));
        return SharedJson.encode(SharedRuntime.map("cleanupData",Base64.getEncoder().encodeToString(output.toByteArray()),"hazeConfidence",analysis.hazeConfidence,"noiseConfidence",analysis.noiseConfidence,"patchCount",analysis.patchCount,"sourceWidth",analysis.sourceWidth,"sourceHeight",analysis.sourceHeight));
    }
    private static void check(BooleanSupplier cancel)throws IOException{if(Thread.currentThread().isInterrupted()||cancel!=null&&cancel.getAsBoolean())throw new InterruptedIOException("去灰分析已取消。");}
}
