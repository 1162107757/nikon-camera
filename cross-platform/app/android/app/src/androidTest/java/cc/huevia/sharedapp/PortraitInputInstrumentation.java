package cc.huevia.sharedapp;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.pm.ApplicationInfo;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.ColorSpace;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.PorterDuff;
import android.os.Bundle;
import cc.huevia.ncp.PhotoPortrait;
import cc.huevia.album.PhotoPortraitDetection;
import cc.huevia.shared.SharedPortraitInference;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.json.JSONArray;
import org.json.JSONObject;
import org.tensorflow.lite.Interpreter;
import org.tensorflow.lite.InterpreterApi;

/** Debug-target-only comparison of original Canvas and portable model input.
 * Optional argument roi is an iOS proposal JSON {cx,cy,rx,ry,roll}.
 * Only aggregate values and hashes leave the process; no photo or landmark data.
 */
public final class PortraitInputInstrumentation extends Instrumentation {
    private Bundle arguments;
    private int checks;
    @Override public void onCreate(Bundle args){super.onCreate(args);arguments=args==null?new Bundle():args;start();}
    @Override public void onStart(){
        Bundle result=new Bundle();Bitmap bitmap=null;Interpreter interpreter=null;
        JSONObject report=new JSONObject();
        try {
            yes((getTargetContext().getApplicationInfo().flags&ApplicationInfo.FLAG_DEBUGGABLE)!=0,"This direct-class probe requires the existing debug target, never R8 keep rules");
            byte[] jpeg=asset("preset-showcase/portrait-smile.jpg");
            yes(hash(jpeg).equals("b0757386f8ef131671e50da1014be2445311a191d0c2a7d20a4898ccf034be58"),"Fixed real portrait SHA matches iOS");
            BitmapFactory.Options decode=new BitmapFactory.Options();decode.inPreferredConfig=Bitmap.Config.ARGB_8888;decode.inScaled=false;decode.inPreferredColorSpace=ColorSpace.get(ColorSpace.Named.SRGB);
            bitmap=BitmapFactory.decodeByteArray(jpeg,0,jpeg.length,decode);yes(bitmap!=null,"Decode original portrait");
            int width=bitmap.getWidth(),height=bitmap.getHeight();int[] pixels=new int[width*height];bitmap.getPixels(pixels,0,width,0,0,width,height);
            report.put("imageWidth",width).put("imageHeight",height).put("rasterMeanARGB",means(pixels,width,0,height)).put("rasterFirstRowMeanARGB",means(pixels,width,0,1)).put("rasterLastRowMeanARGB",means(pixels,width,height-1,1));
            byte[] model=asset("portrait/face_landmarks_detector.tflite");yes(hash(model).equals("c7d54204ce0448474c7f3fa9af494787c0965cbdd6f20fc72867e43046bd43d5"),"Pinned actual mesh model");
            ByteBuffer modelBuffer=direct(model.length);modelBuffer.put(model).rewind();
            interpreter=new Interpreter(modelBuffer,new Interpreter.Options().setNumThreads(2).setUseNNAPI(false).setRuntime(InterpreterApi.Options.TfLiteRuntime.FROM_APPLICATION_ONLY));
            yes(Arrays.equals(interpreter.getInputTensor(0).shape(),new int[]{1,256,256,3})&&interpreter.getOutputTensor(1).numElements()==1,"Actual input and presence tensor dimensions");
            List<PhotoPortrait.Face> detected=PhotoPortraitDetection.detect(bitmap,()->false);yes(!detected.isEmpty(),"Original Android detector found the fixed portrait");
            PhotoPortrait.Face seed=detected.get(0);
            JSONObject original=compare(bitmap,pixels,seed,interpreter);
            report.put("androidProposal",original);
            yes(original.getDouble("canvasPresenceLogit")>=0,"Original Canvas crop passes original presence threshold");
            yes(original.getDouble("portablePresenceLogit")>=0,"Shared preprocessing retains presence for the same original proposal");
            String roi=arguments.getString("roi");
            if(roi!=null){JSONObject p=new JSONObject(roi);PhotoPortrait.Face supplied=seed.withBounds(p.getDouble("cx"),p.getDouble("cy"),p.getDouble("rx"),p.getDouble("ry"),p.getDouble("roll"));report.put("iosProposal",compare(bitmap,pixels,supplied,interpreter));}
            result.putString("stream","DIAGNOSTIC completed "+checks+" validity checks; proposal/input comparison below\n"+report+"\n");result.putString("evidence",report.toString());result.putInt("checks",checks);finish(Activity.RESULT_OK,result);
        }catch(Throwable failure){result.putString("evidence",report.toString());result.putString("stream","FAIL after "+checks+" portrait input checks: "+failure+"\n"+android.util.Log.getStackTraceString(failure)+"\n"+report+"\n");finish(Activity.RESULT_CANCELED,result);}
        finally{if(interpreter!=null)interpreter.close();if(bitmap!=null)bitmap.recycle();}
    }
    private JSONObject compare(Bitmap source,int[] pixels,PhotoPortrait.Face face,Interpreter interpreter)throws Exception {
        JSONObject frame=new JSONObject().put("cx",face.cx).put("cy",face.cy).put("rx",face.rx).put("ry",face.ry).put("roll",face.roll);
        float[] portable=SharedPortraitInference.input(pixels,source.getWidth(),source.getHeight(),frame.toString(),false,()->false);
        // Invoke the real original Crop implementation, not a copied matrix.
        Class<?> cropClass=Class.forName("cc.huevia.album.PhotoFaceLandmarks$Crop",true,getTargetContext().getClassLoader());
        Constructor<?> constructor=cropClass.getDeclaredConstructor(PhotoPortrait.Face.class,int.class,int.class);constructor.setAccessible(true);
        Method matrix=cropClass.getDeclaredMethod("matrix");matrix.setAccessible(true);Object geometry=constructor.newInstance(face,source.getWidth(),source.getHeight());
        Bitmap crop=Bitmap.createBitmap(256,256,Bitmap.Config.ARGB_8888);
        float[] original=new float[256*256*3];
        try {Canvas canvas=new Canvas(crop);canvas.drawColor(Color.BLACK,PorterDuff.Mode.SRC);canvas.drawBitmap(source,(Matrix)matrix.invoke(geometry),new Paint(Paint.FILTER_BITMAP_FLAG));int[] argb=new int[256*256];crop.getPixels(argb,0,256,0,0,256,256);for(int i=0;i<argb.length;i++)for(int c=0;c<3;c++)original[i*3+c]=((argb[i]>>>(16-c*8))&255)/255f;}finally{crop.recycle();}
        ByteBuffer legacy=encode(original),shared=encode(portable);double maximum=0,squared=0;for(int i=0;i<original.length;i++){double d=Math.abs(original[i]-portable[i]);maximum=Math.max(maximum,d);squared+=d*d;}
        JSONObject legacyModel=model(interpreter,legacy,frame,source.getWidth(),source.getHeight()),sharedModel=model(interpreter,shared,frame,source.getWidth(),source.getHeight());
        return new JSONObject().put("frame",frame).put("canvasInput",summary(original,legacy)).put("portableInput",summary(portable,shared)).put("maximumFloatDifference",maximum).put("rmsFloatDifference",Math.sqrt(squared/original.length)).put("canvasPresenceLogit",legacyModel.getDouble("presenceLogit")).put("portablePresenceLogit",sharedModel.getDouble("presenceLogit")).put("canvasMesh",legacyModel).put("portableMesh",sharedModel);
    }
    private JSONObject model(Interpreter interpreter,ByteBuffer input,JSONObject frame,int width,int height)throws Exception{ByteBuffer mesh=direct(interpreter.getOutputTensor(0).numBytes()),presence=direct(4);Map<Integer,Object> outputs=new HashMap<>();outputs.put(0,mesh);outputs.put(1,presence);input.rewind();interpreter.runForMultipleInputsOutputs(new Object[]{input},outputs);float value=presence.getFloat(0);yes(Float.isFinite(value),"Finite actual model presence");int coordinates=0;if(value>=0){float[] points=new float[mesh.capacity()/4];for(int i=0;i<points.length;i++)points[i]=mesh.getFloat(i*4);String refined=SharedPortraitInference.face(frame.toString(),width,height,points,value,null,()->false);coordinates=new JSONObject(refined).getJSONArray("landmarks").length();yes(coordinates==468*2,"Real mesh passes original finite, bounds and nondegenerate postprocessing");}return new JSONObject().put("presenceLogit",value).put("outputElements",mesh.capacity()/4).put("validatedLandmarkCoordinates",coordinates);}
    private static JSONObject summary(float[] input,ByteBuffer bytes)throws Exception{double[] sums=new double[3];float min=input[0],max=input[0];for(int i=0;i<input.length;i++){sums[i%3]+=input[i];min=Math.min(min,input[i]);max=Math.max(max,input[i]);}ByteBuffer copy=bytes.duplicate();copy.rewind();byte[] data=new byte[copy.remaining()];copy.get(data);return new JSONObject().put("sha256",hash(data)).put("meanRGB",new JSONArray().put(sums[0]/65536).put(sums[1]/65536).put(sums[2]/65536)).put("range",new JSONArray().put(min).put(max));}
    private static JSONArray means(int[] pixels,int width,int first,int rows)throws org.json.JSONException{long[] sums=new long[4];for(int y=first;y<first+rows;y++)for(int x=0;x<width;x++)for(int c=0;c<4;c++)sums[c]+=(pixels[y*width+x]>>>(24-c*8))&255;JSONArray values=new JSONArray();for(long value:sums)values.put(value/(double)(width*rows));return values;}
    private static ByteBuffer direct(int count){return ByteBuffer.allocateDirect(count).order(ByteOrder.nativeOrder());}
    private static ByteBuffer encode(float[] values){ByteBuffer buffer=direct(values.length*4);for(float value:values)buffer.putFloat(value);buffer.rewind();return buffer;}
    private byte[] asset(String path)throws Exception{try(InputStream input=getTargetContext().getAssets().open(path);ByteArrayOutputStream output=new ByteArrayOutputStream()){byte[] buffer=new byte[65536];for(int n;(n=input.read(buffer))!=-1;)output.write(buffer,0,n);return output.toByteArray();}}
    private static String hash(byte[] data)throws Exception{byte[] digest=MessageDigest.getInstance("SHA-256").digest(data);StringBuilder result=new StringBuilder();for(byte value:digest)result.append(String.format(java.util.Locale.ROOT,"%02x",value&255));return result.toString();}
    private void yes(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
}
