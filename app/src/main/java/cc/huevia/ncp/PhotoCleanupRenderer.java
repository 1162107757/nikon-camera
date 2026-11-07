package cc.huevia.ncp;

import java.io.*;
import java.util.function.*;

/** Bounded row buffers: denoise original pixels before restoring the estimated atmospheric veil. */
public final class PhotoCleanupRenderer {
    private PhotoCleanupRenderer(){}
    public static void apply(SpatialPreviewFilter.Pixels pixels,PhotoCleanup settings,BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        if(pixels==null||settings==null)throw new IllegalArgumentException("去灰照片无效。");
        if(pixels.width()<1||pixels.height()<1||pixels.width()>65535||pixels.height()>65535)throw new IOException("去灰照片尺寸无效。");
        PhotoCleanupEstimator.check(cancel);if(settings.isNeutral()){if(progress!=null)progress.accept(1);return;}
        boolean haze=settings.hasHazeEffect();
        if(settings.hasNoiseEffect()){
            double scale=Math.sqrt(Math.min(1,Math.max(pixels.width(),pixels.height())/(double)Math.max(settings.analysis.sourceWidth,settings.analysis.sourceHeight)));
            double amount=settings.amount/100.0*settings.noise/100.0*settings.analysis.noiseConfidence/100.0*scale;
            PhotoDetailEffects.denoise(pixels,(int)Math.round(settings.analysis.lumaNoise*amount),(int)Math.round(settings.analysis.chromaNoise*amount),cancel,progress==null?null:v->progress.accept(v*(haze?.65:1)));
        }
        if(haze){int width=pixels.width(),height=pixels.height();int[] row=new int[width];for(int y=0;y<height;y++){PhotoCleanupEstimator.check(cancel);pixels.read(row,y,1);for(int x=0;x<width;x++){if((x&255)==0)PhotoCleanupEstimator.check(cancel);row[x]=settings.applyArgb(row[x]);}pixels.write(row,y,1);if(progress!=null)progress.accept(.65+.35*(y+1)/height);}}
        if(progress!=null)progress.accept(1);
    }
}
