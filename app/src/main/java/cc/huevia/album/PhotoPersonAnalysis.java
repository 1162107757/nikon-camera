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
public final class PhotoPersonAnalysis {
    public static final class Result {
        public final PhotoPortrait.BodySkinMask skin,person;
        public final List<PhotoPortrait.Face> faces;
        private Result(PhotoPortrait.BodySkinMask skin,PhotoPortrait.BodySkinMask person,List<PhotoPortrait.Face> faces){this.skin=skin;this.person=person;this.faces=java.util.Collections.unmodifiableList(new ArrayList<>(faces));}
    }
    private static final java.util.LinkedHashMap<String,Result> CACHE=new java.util.LinkedHashMap<String,Result>(4,.75f,true){protected boolean removeEldestEntry(java.util.Map.Entry<String,Result> entry){return size()>4;}};
    public static Result analyze(Context context,Bitmap bitmap,BooleanSupplier cancel)throws IOException{
        check(cancel);String key=key(bitmap,cancel);synchronized(CACHE){Result ready=CACHE.get(key);if(ready!=null)return ready;}
        Result result=compute(context,bitmap,java.util.Collections.emptyList(),cancel);check(cancel);synchronized(CACHE){CACHE.put(key,result);}return result;
    }
    private static String key(Bitmap b,BooleanSupplier cancel)throws IOException{
        if(b==null||b.isRecycled())throw new IOException("人物照片无效。");
        try{java.security.MessageDigest d=java.security.MessageDigest.getInstance("SHA-256");d.update((b.getWidth()+"x"+b.getHeight()+":person-v2").getBytes(java.nio.charset.StandardCharsets.UTF_8));int[] row=new int[b.getWidth()];byte[] bytes=new byte[row.length*4];for(int y=0;y<b.getHeight();y++){check(cancel);b.getPixels(row,0,row.length,0,y,row.length,1);for(int x=0;x<row.length;x++){int v=row[x],i=x*4;bytes[i]=(byte)(v>>>24);bytes[i+1]=(byte)(v>>>16);bytes[i+2]=(byte)(v>>>8);bytes[i+3]=(byte)v;}d.update(bytes);}StringBuilder s=new StringBuilder();for(byte v:d.digest())s.append(String.format(java.util.Locale.US,"%02x",v&255));return s.toString();}catch(java.security.NoSuchAlgorithmException e){throw new IOException(e);}
    }
    private static final int INPUT=256,CLASSES=6;
    private PhotoPersonAnalysis(){}
    private static Result compute(Context context,Bitmap analysis,List<PhotoPortrait.Face> knownFaces,BooleanSupplier cancel)throws IOException{
        if(context==null||analysis==null||analysis.isRecycled()||cancel==null)throw new IllegalArgumentException("皮肤识别参数无效。");
        check(cancel);Bitmap sample=null;byte[] coverage,foreground;int size=PhotoPortrait.BodySkinMask.SIZE;
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
            float[] skin=new float[INPUT*INPUT],person=new float[INPUT*INPUT];double[] values=new double[CLASSES];
            for(int y=0;y<INPUT;y++){check(cancel);for(int x=0;x<INPUT;x++){
                if(x+.5<left||x+.5>=left+w||y+.5<top||y+.5>=top+h)continue;
                int i=y*INPUT+x,offset=i*CLASSES*4;double max=Double.NEGATIVE_INFINITY;
                for(int c=0;c<CLASSES;c++){double v=output.getFloat(offset+c*4);if(!Double.isFinite(v))throw new IOException("皮肤模型输出无效。");values[c]=v;max=Math.max(max,v);}
                double sum=0;for(int c=0;c<CLASSES;c++){values[c]=Math.exp(values[c]-max);sum+=values[c];}
                person[i]=(float)((values[1]+values[2]+values[3]+values[4])/sum);
                double p=(values[2]+values[3])/sum,other=0;for(int c=0;c<CLASSES;c++)if(c!=2&&c!=3)other=Math.max(other,values[c]/sum);
                if(p>other){double margin=Math.min(1,(p-other)/.25);skin[i]=(float)(margin*margin*(3-2*margin));}
            }}
            coverage=new byte[size*size];foreground=new byte[size*size];
            for(int y=0;y<size;y++){check(cancel);for(int x=0;x<size;x++){
                double gx=left+(x+.5)/size*w-.5,gy=top+(y+.5)/size*h-.5;int ix=(int)Math.floor(gx),iy=(int)Math.floor(gy);
                double tx=gx-ix,ty=gy-iy,weight=0,bodyWeight=0;
                for(int dy=0;dy<2;dy++)for(int dx=0;dx<2;dx++){
                    int sx=Math.max(0,Math.min(INPUT-1,ix+dx)),sy=Math.max(0,Math.min(INPUT-1,iy+dy));
                    double kernel=(dx==0?1-tx:tx)*(dy==0?1-ty:ty);weight+=skin[sy*INPUT+sx]*kernel;bodyWeight+=person[sy*INPUT+sx]*kernel;
                }
                coverage[y*size+x]=(byte)Math.round(Math.min(1,weight)*255);foreground[y*size+x]=(byte)Math.round(Math.min(1,Math.max(0,(bodyWeight-.25)/.6))*255);
            }}
        }catch(LinkageError|RuntimeException failure){throw new IOException("自动识别皮肤未完成，请重试。",failure);}
        finally{if(sample!=null)sample.recycle();}
        // Five-feature protection is optional refinement, never a prerequisite for skin.
        List<PhotoPortrait.Face> features=new ArrayList<>();
        if(knownFaces!=null)for(PhotoPortrait.Face f:knownFaces)if(f!=null&&f.landmarks!=null)features.add(f);
        try{
            List<PhotoPortrait.Face> detected=PhotoPortraitDetection.detect(analysis,cancel);
            if(!detected.isEmpty())features=new ArrayList<>(PhotoFaceSkinMask.refine(context,analysis,PhotoFaceLandmarks.refine(context,analysis,detected,cancel),cancel));
        }catch(Exception|LinkageError|OutOfMemoryError optionalFailure){check(cancel);}
        check(cancel);
        if(!features.isEmpty())for(int y=0;y<size;y++){check(cancel);for(int x=0;x<size;x++){
            int i=y*size+x,alpha=coverage[i]&255;if(alpha==0)continue;double protection=1,nx=(x+.5)/size,ny=(y+.5)/size;
            for(PhotoPortrait.Face f:features)protection=Math.min(protection,PortraitPreviewFilter.featureProtection(f,nx,ny,analysis.getWidth(),analysis.getHeight()));
            coverage[i]=(byte)Math.round(alpha*protection);
        }}
        for(PhotoPortrait.Face f:features)if(f.skinMask!=null){
            cc.huevia.ncp.PortraitPreviewFilter.Mask faceMask=PortraitPreviewFilter.mask(f,analysis.getWidth(),analysis.getHeight());
            for(int y=0;y<size;y++){check(cancel);for(int x=0;x<size;x++){double nx=(x+.5)/size,ny=(y+.5)/size;if(!PortraitPreviewFilter.faceContains(f,nx,ny,analysis.getWidth(),analysis.getHeight()))continue;int rgb=analysis.getPixel(Math.min(analysis.getWidth()-1,(int)(nx*analysis.getWidth())),Math.min(analysis.getHeight()-1,(int)(ny*analysis.getHeight())));coverage[y*size+x]=(byte)Math.round(255*faceMask.weight(rgb,nx,ny));}}
        }
        return new Result(new PhotoPortrait.BodySkinMask(coverage),new PhotoPortrait.BodySkinMask(foreground),features);
    }
    private static ByteBuffer direct(int size){return ByteBuffer.allocateDirect(size).order(ByteOrder.nativeOrder());}
    private static void check(BooleanSupplier cancel)throws IOException{if(cancel.getAsBoolean()||Thread.currentThread().isInterrupted())throw new IOException("皮肤识别已取消。");}
}
