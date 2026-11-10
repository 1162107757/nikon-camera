package cc.huevia.shared;

import cc.huevia.library.SharedJson;
import cc.huevia.ncp.*;
import java.io.*;
import java.util.*;

public final class CleanupBoundaryTest {
    private static int checks;
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Cleanup boundary "+checks);}
    private static final class Surface implements SpatialPreviewFilter.Pixels{
        final int width,height,exif;final int[] values;int reads;
        Surface(int w,int h,int exif){width=w;height=h;this.exif=exif;values=new int[w*h];for(int y=0;y<h;y++)for(int x=0;x<w;x++)values[y*w+x]=0xff000000|((90+x%45)<<16)|((100+y%45)<<8)|120;}
        public int width(){return width;}public int height(){return height;}public int exifOrientation(){return exif;}
        public void read(int[] output,int first,int rows){reads++;System.arraycopy(values,first*width,output,0,width*rows);}
        public void write(int[] values,int first,int rows){throw new AssertionError("Analysis modified original");}
    }
    public static int run()throws Exception{
        checks=0;Surface original=new Surface(320,240,6),overview=new Surface(120,160,1);int[] before=original.values.clone();
        Map<String,Object> result=SharedJson.object(SharedCleanup.analyze(original,overview,()->false));
        yes(((Number)result.get("sourceWidth")).intValue()==240&&((Number)result.get("sourceHeight")).intValue()==320);
        yes(((Number)result.get("patchCount")).intValue()==9);yes(original.reads==9*96);yes(Arrays.equals(before,original.values));
        SharedRecipe recipe=new SharedRecipe(SharedJson.encode(result));yes(recipe.adjustments.cleanup.analysis!=null);yes(recipe.adjustments.cleanup.amount==100);
        result.put("cleanup",SharedRuntime.map("amount",40,"haze",50,"noise",0));SharedRecipe adjusted=new SharedRecipe(SharedJson.encode(result));
        yes(adjusted.adjustments.cleanup.amount==40&&adjusted.adjustments.cleanup.haze==50&&adjusted.adjustments.cleanup.noise==0);
        yes(adjusted.adjustments.cleanup.analysis.equals(recipe.adjustments.cleanup.analysis));
        Surface tiny=new Surface(2,2,1);Map<String,Object> small=SharedJson.object(SharedCleanup.analyze(tiny,tiny,()->false));yes(((Number)small.get("patchCount")).intValue()==0);
        boolean cancelled=false;try{SharedCleanup.analyze(original,overview,()->true);}catch(InterruptedIOException expected){cancelled=true;}yes(cancelled);
        return checks;
    }
}
