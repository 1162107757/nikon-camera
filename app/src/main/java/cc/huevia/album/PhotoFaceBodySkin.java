package cc.huevia.album;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import cc.huevia.ncp.PhotoPortrait;
import cc.huevia.ncp.SkinBodyRegions;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.function.BooleanSupplier;
import org.tensorflow.lite.DataType;
import org.tensorflow.lite.Interpreter;
import org.tensorflow.lite.InterpreterApi;

/** Full-image body-skin inference, reused only by the portrait skin-tone tool. */
public final class PhotoFaceBodySkin {
    private static final int INPUT=256,CLASSES=6,BODY_SKIN=2;
    private PhotoFaceBodySkin(){}
    public static List<PhotoPortrait.Face> refine(Context context,Bitmap analysis,List<PhotoPortrait.Face> faces,BooleanSupplier cancel)throws IOException{
        if(context==null||analysis==null||analysis.isRecycled()||faces==null||faces.size()>PhotoPortrait.MAX_FACES||cancel==null)
            throw new IllegalArgumentException("身体皮肤识别参数无效。");
        for(PhotoPortrait.Face f:faces)if(f==null)throw new IllegalArgumentException("人物位置缺失。");
        check(cancel);if(faces.isEmpty())return Collections.emptyList();
        Bitmap sample=null;
        try(Interpreter interpreter=new Interpreter(FaceSkinModel.load(context,cancel),new Interpreter.Options().setNumThreads(2).setUseNNAPI(false)
                .setRuntime(InterpreterApi.Options.TfLiteRuntime.FROM_APPLICATION_ONLY))){
            if(interpreter.getInputTensorCount()!=1||interpreter.getOutputTensorCount()!=1
                    ||interpreter.getInputTensor(0).dataType()!=DataType.FLOAT32||interpreter.getOutputTensor(0).dataType()!=DataType.FLOAT32
                    ||!Arrays.equals(interpreter.getInputTensor(0).shape(),new int[]{1,INPUT,INPUT,3})
                    ||!Arrays.equals(interpreter.getOutputTensor(0).shape(),new int[]{1,INPUT,INPUT,CLASSES}))throw new IOException("皮肤模型格式不符。");
            double scale=Math.min(INPUT/(double)analysis.getWidth(),INPUT/(double)analysis.getHeight());
            double w=analysis.getWidth()*scale,h=analysis.getHeight()*scale,left=(INPUT-w)/2,top=(INPUT-h)/2;
            sample=Bitmap.createBitmap(INPUT,INPUT,Bitmap.Config.ARGB_8888);Canvas canvas=new Canvas(sample);canvas.drawColor(Color.BLACK);
            canvas.drawBitmap(analysis,null,new RectF((float)left,(float)top,(float)(left+w),(float)(top+h)),new Paint(Paint.FILTER_BITMAP_FLAG));
            int[] pixels=new int[INPUT*INPUT];sample.getPixels(pixels,0,INPUT,0,0,INPUT,INPUT);
            ByteBuffer input=direct(INPUT*INPUT*3*4),output=direct(INPUT*INPUT*CLASSES*4);
            for(int y=0;y<INPUT;y++){check(cancel);for(int x=0;x<INPUT;x++){int rgb=pixels[y*INPUT+x];input.putFloat(((rgb>>>16)&255)/127.5f-1);input.putFloat(((rgb>>>8)&255)/127.5f-1);input.putFloat((rgb&255)/127.5f-1);}}
            input.rewind();check(cancel);interpreter.run(input,output);check(cancel);
            byte[] categories=new byte[INPUT*INPUT];float[] body=new float[categories.length];double[] values=new double[CLASSES];
            for(int y=0;y<INPUT;y++){check(cancel);for(int x=0;x<INPUT;x++){
                if(x+.5<left||x+.5>=left+w||y+.5<top||y+.5>=top+h)continue;
                int i=y*INPUT+x,offset=i*CLASSES*4,winner=0;double max=Double.NEGATIVE_INFINITY;
                for(int c=0;c<CLASSES;c++){double v=output.getFloat(offset+c*4);if(!Double.isFinite(v))throw new IOException("皮肤模型输出无效。");values[c]=v;if(v>max){max=v;winner=c;}}
                categories[i]=(byte)winner;double sum=0;for(int c=0;c<CLASSES;c++){values[c]=Math.exp(values[c]-max);sum+=values[c];}
                double p=values[BODY_SKIN]/sum,other=0;for(int c=0;c<CLASSES;c++)if(c!=BODY_SKIN)other=Math.max(other,values[c]/sum);
                if(p>other){double margin=Math.min(1,(p-other)/.25);body[i]=(float)(margin*margin*(3-2*margin));}
            }}
            double[] seeds=new double[faces.size()*2];for(int i=0;i<faces.size();i++){seeds[2*i]=(left+faces.get(i).cx*w)/INPUT;seeds[2*i+1]=(top+faces.get(i).cy*h)/INPUT;}
            int[] owners=SkinBodyRegions.owners(categories,INPUT,seeds,cancel);List<PhotoPortrait.Face> result=new ArrayList<>();
            int size=PhotoPortrait.BodySkinMask.SIZE;
            for(int face=0;face<faces.size();face++){
                byte[] coverage=new byte[size*size];
                for(int y=0;y<size;y++){check(cancel);for(int x=0;x<size;x++){
                    double gx=left+(x+.5)/size*w-.5,gy=top+(y+.5)/size*h-.5;
                    int ix=(int)Math.floor(gx),iy=(int)Math.floor(gy);double tx=gx-ix,ty=gy-iy,weight=0;
                    for(int dy=0;dy<2;dy++)for(int dx=0;dx<2;dx++){
                        int sx=Math.max(0,Math.min(INPUT-1,ix+dx)),sy=Math.max(0,Math.min(INPUT-1,iy+dy)),i=sy*INPUT+sx;
                        if(owners[i]==face)weight+=body[i]*(dx==0?1-tx:tx)*(dy==0?1-ty:ty);
                    }
                    coverage[y*size+x]=(byte)Math.round(Math.min(1,weight)*255);
                }}
                result.add(faces.get(face).withBodySkinMask(new PhotoPortrait.BodySkinMask(coverage)));
            }
            return Collections.unmodifiableList(result);
        }catch(LinkageError|RuntimeException failure){throw new IOException("全身皮肤识别未完成，请重试。",failure);}
        finally{if(sample!=null)sample.recycle();}
    }
    private static ByteBuffer direct(int size){return ByteBuffer.allocateDirect(size).order(ByteOrder.nativeOrder());}
    private static void check(BooleanSupplier cancel)throws IOException{if(cancel.getAsBoolean()||Thread.currentThread().isInterrupted())throw new IOException("身体皮肤识别已取消。");}
}
