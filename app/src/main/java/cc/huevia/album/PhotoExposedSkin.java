package cc.huevia.album;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import cc.huevia.ncp.PhotoPortrait;
import cc.huevia.ncp.PortraitPreviewFilter;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.function.BooleanSupplier;
import org.tensorflow.lite.DataType;
import org.tensorflow.lite.Interpreter;
import org.tensorflow.lite.InterpreterApi;

/** Detects every exposed-skin region. A visible or selected face is never required. */
public final class PhotoExposedSkin {
    private static final int INPUT=256,CLASSES=6;
    private PhotoExposedSkin(){}
    public static PhotoPortrait.BodySkinMask detect(Context context,Bitmap analysis,List<PhotoPortrait.Face> knownFaces,BooleanSupplier cancel)throws IOException{
        PhotoPortrait.BodySkinMask ready=PhotoPersonAnalysis.analyze(context,analysis,cancel).skin;
        if(knownFaces==null||knownFaces.isEmpty())return ready;byte[] coverage=ready.copyCoverage();int size=PhotoPortrait.BodySkinMask.SIZE;
        for(int y=0;y<size;y++){check(cancel);for(int x=0;x<size;x++){int i=y*size+x;if((coverage[i]&255)==0)continue;double protection=1;for(PhotoPortrait.Face face:knownFaces)if(face.landmarks!=null)protection=Math.min(protection,PortraitPreviewFilter.featureProtection(face,(x+.5)/size,(y+.5)/size,analysis.getWidth(),analysis.getHeight()));coverage[i]=(byte)Math.round(Math.min(coverage[i]&255,255*protection));}}
        return new PhotoPortrait.BodySkinMask(coverage);
    }

    private static ByteBuffer direct(int size){return ByteBuffer.allocateDirect(size).order(ByteOrder.nativeOrder());}
    private static void check(BooleanSupplier cancel)throws IOException{if(cancel.getAsBoolean()||Thread.currentThread().isInterrupted())throw new IOException("皮肤识别已取消。");}
}
