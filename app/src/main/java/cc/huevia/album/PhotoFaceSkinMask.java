package cc.huevia.album;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.PorterDuff;
import cc.huevia.ncp.PhotoPortrait;
import cc.huevia.ncp.PortraitPreviewFilter;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.function.BooleanSupplier;
import org.tensorflow.lite.DataType;
import org.tensorflow.lite.Interpreter;
import org.tensorflow.lite.InterpreterApi;

/** On-device semantic face-skin coverage. Hands/body skin and hair are different classes. */
public final class PhotoFaceSkinMask {
    private static final int INPUT=256,CLASSES=6,FACE_SKIN=3;
    private static final int[] SEEDS={1,4,50,101,205,280,330,425,151,9,199};
    private PhotoFaceSkinMask(){}

    public static java.util.List<PhotoPortrait.Face> refine(Context context,Bitmap analysis,
            java.util.List<PhotoPortrait.Face> faces,BooleanSupplier cancel)throws IOException{
        if(context==null||analysis==null||analysis.isRecycled()||faces==null||cancel==null||faces.size()>PhotoPortrait.MAX_FACES)
            throw new IllegalArgumentException("面部皮肤选区参数无效。");
        for(PhotoPortrait.Face face:faces)if(face==null||face.landmarks==null)throw new IllegalArgumentException("面部关键点缺失。");
        check(cancel);if(faces.isEmpty())return Collections.emptyList();
        ByteBuffer model=FaceSkinModel.load(context,cancel);Bitmap crop=null;
        try(Interpreter interpreter=new Interpreter(model,new Interpreter.Options().setNumThreads(2).setUseNNAPI(false)
                .setRuntime(InterpreterApi.Options.TfLiteRuntime.FROM_APPLICATION_ONLY))){
            if(interpreter.getInputTensorCount()!=1||interpreter.getOutputTensorCount()!=1
                    ||interpreter.getInputTensor(0).dataType()!=DataType.FLOAT32||interpreter.getOutputTensor(0).dataType()!=DataType.FLOAT32
                    ||!Arrays.equals(interpreter.getInputTensor(0).shape(),new int[]{1,INPUT,INPUT,3})
                    ||!Arrays.equals(interpreter.getOutputTensor(0).shape(),new int[]{1,INPUT,INPUT,CLASSES}))
                throw new IOException("面部皮肤模型格式不符。");
            ByteBuffer input=direct(INPUT*INPUT*3*Float.BYTES),output=direct(INPUT*INPUT*CLASSES*Float.BYTES);
            crop=Bitmap.createBitmap(INPUT,INPUT,Bitmap.Config.ARGB_8888);Canvas canvas=new Canvas(crop);
            Paint paint=new Paint(Paint.FILTER_BITMAP_FLAG);int[] pixels=new int[INPUT*INPUT];
            ArrayList<PhotoPortrait.Face> result=new ArrayList<>();
            for(PhotoPortrait.Face face:faces){
                check(cancel);PhotoFaceLandmarks.Crop frame=new PhotoFaceLandmarks.Crop(face,analysis.getWidth(),analysis.getHeight());
                canvas.drawColor(Color.BLACK,PorterDuff.Mode.SRC);canvas.drawBitmap(analysis,frame.matrix(),paint);
                crop.getPixels(pixels,0,INPUT,0,0,INPUT,INPUT);input.clear();
                for(int y=0;y<INPUT;y++){check(cancel);for(int x=0;x<INPUT;x++){
                    int argb=pixels[y*INPUT+x];input.putFloat(((argb>>>16)&255)/127.5f-1);
                    input.putFloat(((argb>>>8)&255)/127.5f-1);input.putFloat((argb&255)/127.5f-1);
                }}
                input.rewind();output.clear();check(cancel);interpreter.run(input,output);check(cancel);
                int size=PhotoPortrait.SkinMask.SIZE;float[] weights=new float[size*size];boolean[] candidate=new boolean[weights.length];
                double[] scores=new double[CLASSES];
                // SEGMENTER_METADATA requires SOFTMAX: the direct model output is logits.
                for(int y=0;y<size;y++){check(cancel);for(int x=0;x<size;x++){
                    double amount=0;int winners=0;
                    for(int dy=0;dy<2;dy++)for(int dx=0;dx<2;dx++){
                        int offset=((2*y+dy)*INPUT+2*x+dx)*CLASSES*Float.BYTES;double max=Double.NEGATIVE_INFINITY;
                        for(int c=0;c<CLASSES;c++){scores[c]=output.getFloat(offset+c*Float.BYTES);if(!Double.isFinite(scores[c]))throw new IOException("面部皮肤模型输出无效。");max=Math.max(max,scores[c]);}
                        double sum=0;for(int c=0;c<CLASSES;c++){scores[c]=Math.exp(scores[c]-max);sum+=scores[c];}
                        double faceProbability=scores[FACE_SKIN]/sum,other=0;
                        for(int c=0;c<CLASSES;c++)if(c!=FACE_SKIN)other=Math.max(other,scores[c]/sum);
                        if(faceProbability>other){winners++;double margin=Math.min(1,(faceProbability-other)/.25);amount+=margin*margin*(3-2*margin);}
                    }
                    int i=y*size+x;weights[i]=(float)(amount/4);candidate[i]=winners>0&&weights[i]>.01;
                }}
                double left=frame.localX(0),top=frame.localY(0),right=frame.localX(INPUT),bottom=frame.localY(INPUT);
                // Keep components anchored to this face. A second face in the generous crop
                // must not inherit the first person's adjustments.
                boolean[] retained=components(face.landmarks,candidate,size,left,top,right,bottom,cancel);
                byte[] coverage=new byte[size*size];int covered=0;
                for(int y=0;y<size;y++){check(cancel);for(int x=0;x<size;x++){
                    int i=y*size+x;if(!retained[i])continue;
                    double u=left+(x+.5)/size*(right-left),v=top+(y+.5)/size*(bottom-top);
                    double px=face.cx*analysis.getWidth()+frame.cos*u*frame.rx-frame.sin*v*frame.ry;
                    double py=face.cy*analysis.getHeight()+frame.sin*u*frame.rx+frame.cos*v*frame.ry;
                    boolean another=false;
                    for(PhotoPortrait.Face other:faces)if(other!=face&&PortraitPreviewFilter.faceContains(other,px/analysis.getWidth(),py/analysis.getHeight(),analysis.getWidth(),analysis.getHeight())){another=true;break;}
                    if(another)continue;int alpha=(int)Math.round(weights[i]*255);coverage[i]=(byte)alpha;if(alpha>16)covered++;
                }}
                if(covered<32)throw new IOException("未能确认面部皮肤，请手动补选。");
                result.add(face.withSkinMask(new PhotoPortrait.SkinMask(left,top,right,bottom,coverage)));
            }
            return Collections.unmodifiableList(result);
        }catch(LinkageError|RuntimeException failure){throw new IOException("面部皮肤选区暂不可用，请重试或手动补选。",failure);}
        finally{if(crop!=null)crop.recycle();}
    }

    private static boolean[] components(PhotoPortrait.Landmarks landmarks,boolean[] candidate,int size,
            double left,double top,double right,double bottom,BooleanSupplier cancel)throws IOException{
        boolean[] keep=new boolean[candidate.length];int[] queue=new int[candidate.length];int tail=0;
        for(int point:SEEDS){check(cancel);
            int cx=(int)((landmarks.x(point)-left)/(right-left)*size),cy=(int)((landmarks.y(point)-top)/(bottom-top)*size),chosen=-1,best=Integer.MAX_VALUE;
            for(int y=Math.max(0,cy-3);y<=Math.min(size-1,cy+3);y++)for(int x=Math.max(0,cx-3);x<=Math.min(size-1,cx+3);x++){
                int i=y*size+x,d=(x-cx)*(x-cx)+(y-cy)*(y-cy);if(candidate[i]&&d<best){chosen=i;best=d;}
            }
            if(chosen>=0&&!keep[chosen]){keep[chosen]=true;queue[tail++]=chosen;}
        }
        for(int head=0;head<tail;head++){if((head&255)==0)check(cancel);int i=queue[head],cx=i%size,cy=i/size;
            for(int y=Math.max(0,cy-1);y<=Math.min(size-1,cy+1);y++)for(int x=Math.max(0,cx-1);x<=Math.min(size-1,cx+1);x++){
                int next=y*size+x;if(candidate[next]&&!keep[next]){keep[next]=true;queue[tail++]=next;}
            }
        }
        return keep;
    }
    private static ByteBuffer direct(int bytes){return ByteBuffer.allocateDirect(bytes).order(ByteOrder.nativeOrder());}
    private static void check(BooleanSupplier cancel)throws IOException{if(cancel.getAsBoolean()||Thread.currentThread().isInterrupted())throw new IOException("人脸识别已取消。");}
}
