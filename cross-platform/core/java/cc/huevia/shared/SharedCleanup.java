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
        check(cancel);
        int width=original.width(),height=original.height(),sw=overview.width(),sh=overview.height();
        if(width<1||height<1||sw<1||sh<1||sw>512||sh>512)throw new IOException("去灰分析尺寸无效。");
        int[] sample=new int[sw*sh];overview.read(sample,0,sh);
        PhotoGeometry.Plan oriented=PhotoGeometry.NONE.plan(width,height,original.exifOrientation());
        List<PhotoCleanupEstimator.Patch> patches=new ArrayList<>();Set<String> seen=new HashSet<>();
        if(width>=3&&height>=3){
            int pw=Math.min(96,width),ph=Math.min(96,height);int[] row=new int[width];
            for(int y=0;y<3;y++)for(int x=0;x<3;x++){
                check(cancel);double[] point=oriented.inverse((x+.5)*oriented.width/3,(y+.5)*oriented.height/3);
                int left=Math.max(0,Math.min(width-pw,(int)Math.round(point[0]-pw*.5))),top=Math.max(0,Math.min(height-ph,(int)Math.round(point[1]-ph*.5)));
                if(!seen.add(left+":"+top))continue;
                int[] pixels=new int[pw*ph];for(int j=0;j<ph;j++){check(cancel);original.read(row,top+j,1);System.arraycopy(row,left,pixels,j*pw,pw);}
                patches.add(new PhotoCleanupEstimator.Patch(pixels,pw,ph,null));
            }
        }
        return result(PhotoCleanupEstimator.analyze(sample,sw,sh,oriented.width,oriented.height,patches,null,cancel));
    }
    public static String result(PhotoCleanup.Analysis analysis)throws IOException{
        ByteArrayOutputStream output=new ByteArrayOutputStream();new PhotoCleanup(100,100,100,analysis).write(new DataOutputStream(output));
        return SharedJson.encode(SharedRuntime.map("cleanupData",Base64.getEncoder().encodeToString(output.toByteArray()),"hazeConfidence",analysis.hazeConfidence,"noiseConfidence",analysis.noiseConfidence,"patchCount",analysis.patchCount,"sourceWidth",analysis.sourceWidth,"sourceHeight",analysis.sourceHeight));
    }
    private static void check(BooleanSupplier cancel)throws IOException{if(Thread.currentThread().isInterrupted()||cancel!=null&&cancel.getAsBoolean())throw new InterruptedIOException("去灰分析已取消。");}
}
