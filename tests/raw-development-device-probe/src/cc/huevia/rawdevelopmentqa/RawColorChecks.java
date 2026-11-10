package cc.huevia.rawdevelopmentqa;

import android.content.Context;
import android.graphics.*;
import org.json.*;
import java.io.*;
import java.lang.reflect.*;
import java.util.*;
import java.util.function.*;

/** Runs against classes and JNI in the SHA-bound installed product, never a copied engine. */
final class RawColorChecks {
    private final Context context;private final Class<?> developer,settings,callback,colorMode;
    private final JSONArray checks,measurements;private final File output;
    RawColorChecks(Context context,JSONArray checks,JSONArray measurements,File output)throws Exception {
        this.context=context;this.checks=checks;this.measurements=measurements;this.output=output;
        ClassLoader loader=context.getClassLoader();developer=Class.forName("cc.huevia.album.RawDeveloper",true,loader);
        settings=Class.forName("cc.huevia.ncp.RawDevelopmentSettings",true,loader);
        callback=Class.forName("cc.huevia.album.RawDeveloper$NativeCallbacks",true,loader);
        colorMode=Class.forName("cc.huevia.ncp.RawDevelopmentSettings$ColorMode",true,loader);
    }
    void nativeLut(File noJpeg)throws Exception {
        check(nativeCall("nativeEmbeddedJpeg",new Class<?>[]{String.class,callback},noJpeg.getPath(),callbacks(null))==null,"jpeg-reference-absent-on-generated-dng");
        int w=79,h=67;int[] input=new int[w*h];Random random=new Random(1141);
        for(int i=0;i<input.length;i++)input[i]=0xff000000|random.nextInt(0x1000000);
        Bitmap bitmap=Bitmap.createBitmap(w,h,Bitmap.Config.ARGB_8888);bitmap.setPixels(input,0,w,0,0,w,h);
        float[] table=new float[17*17*17*3];for(int r=0;r<17;r++)for(int g=0;g<17;g++)for(int b=0;b<17;b++){int i=((r*17+g)*17+b)*3;table[i]=1-b/16f;table[i+1]=r/16f;table[i+2]=g/16f;}
        try {
            nativeCall("nativeApplyColor",new Class<?>[]{Bitmap.class,float[].class,callback},bitmap,table,callbacks(null));
            int[] pixels=new int[input.length];bitmap.getPixels(pixels,0,w,0,0,w,h);int maxError=0;
            for(int i=0;i<pixels.length;i++){int p=input[i],expected=0xff000000|(255-(p&255))<<16|((p>>>16)&255)<<8|((p>>>8)&255);for(int shift:new int[]{0,8,16,24})maxError=Math.max(maxError,Math.abs(((pixels[i]>>>shift)&255)-((expected>>>shift)&255)));}
            check(maxError<=1&&bitmap.getWidth()==w&&bitmap.getHeight()==h,"native-LUT-index-interpolation-RGB-alpha-dimensions");
            check(Arrays.equals(input,originalPixels(w,h)),"native-LUT-analysis-source-array-unchanged");
            boolean cancelled=false;try{nativeCall("nativeApplyColor",new Class<?>[]{Bitmap.class,float[].class,callback},bitmap,table,callbacks(()->true));}catch(InterruptedIOException expected){cancelled=true;}check(cancelled,"native-LUT-pre-cancelled");
            float saved=table[2];table[2]=Float.NaN;boolean rejected=false;try{nativeCall("nativeApplyColor",new Class<?>[]{Bitmap.class,float[].class,callback},bitmap,table,callbacks(null));}catch(IOException expected){rejected=true;}check(rejected,"native-LUT-NaN-rejected");table[2]=saved;
            rejected=false;try{nativeCall("nativeApplyColor",new Class<?>[]{Bitmap.class,float[].class,callback},bitmap,new float[3],callbacks(null));}catch(IOException expected){rejected=true;}check(rejected,"native-LUT-invalid-length-rejected");
            nativeCall("nativeApplyColor",new Class<?>[]{Bitmap.class,float[].class,callback},bitmap,table,callbacks(null));check(!bitmap.isRecycled(),"native-LUT-lock-reusable-after-error");
        }finally{bitmap.recycle();}
    }
    void real(File source,String owner,Object cameraResult)throws Exception {
        byte[] jpeg=(byte[])nativeCall("nativeEmbeddedJpeg",new Class<?>[]{String.class,callback},source.getPath(),callbacks(null));check(jpeg!=null&&jpeg.length>4,"real-nef-has-native-camera-JPEG-reference");
        BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;BitmapFactory.decodeByteArray(jpeg,0,jpeg.length,bounds);
        check(bounds.outWidth>=320&&bounds.outHeight>=200,"real-nef-JPEG-reference-useful-size");
        Object defaults=settings.getField("DEFAULT").get(null);@SuppressWarnings({"unchecked","rawtypes"}) Object neutralMode=Enum.valueOf((Class)colorMode,"NEUTRAL");
        Object neutralSettings=invoke(settings.getMethod("withColorMode",colorMode),defaults,neutralMode);
        long start=System.nanoTime();Object neutral=develop(source,owner,neutralSettings);
        check(!(Boolean)get(neutral,"cameraColorApplied")&&"中性色彩".equals(get(neutral,"colorStatus")),"neutral-mode-has-no-JPEG-match");
        check(!get(neutral,"cacheIdentity").equals(get(cameraResult,"cacheIdentity")),"camera-and-neutral-work-cache-separated");
        Object cached=develop(source,owner,defaults);
        check((Boolean)get(cached,"cached")&&get(cached,"colorStatus").equals(get(cameraResult,"colorStatus"))&&get(cached,"cameraColorApplied").equals(get(cameraResult,"cameraColorApplied")),"camera-color-cache-restores-status-and-match");
        Bitmap neutralSmall=decodeSmall((File)get(neutral,"workingFile")),cameraSmall=decodeSmall((File)get(cameraResult,"workingFile")),reference=decodeSmall(jpeg);
        try {
            Class<?> matcher=Class.forName("cc.huevia.ncp.RawJpegColorMatch",true,context.getClassLoader());
            Object fit=invoke(matcher.getMethod("fit",int[].class,int.class,int.class,int[].class,int.class,int.class,BooleanSupplier.class),null,pixels(neutralSmall),neutralSmall.getWidth(),neutralSmall.getHeight(),pixels(reference),reference.getWidth(),reference.getHeight(),null);
            boolean applied=(Boolean)get(cameraResult,"cameraColorApplied");double before=((Number)get(cameraResult,"colorErrorBefore")).doubleValue(),after=((Number)get(cameraResult,"colorErrorAfter")).doubleValue();
            measurements.put(new JSONObject().put("case","real-nef-camera-JPEG-color").put("applied",applied).put("status",get(cameraResult,"colorStatus")).put("beforeRgbRmse",before).put("afterRgbRmse",after).put("fitReason",get(fit,"reason")).put("correlation",get(fit,"correlation")).put("orientation",get(fit,"orientation")).put("referenceScale",get(fit,"referenceScale")).put("samples",get(fit,"samples")).put("referenceWidth",bounds.outWidth).put("referenceHeight",bounds.outHeight).put("referenceBytes",jpeg.length).put("neutralExtraElapsedMs",(System.nanoTime()-start)/1e6));
            save(neutralSmall,"real-nef-neutral.png");save(cameraSmall,"real-nef-camera-color.png");save(reference,"real-nef-camera-jpeg-reference.png");
            // Pinned Nikon Z6 fixture is a normal color JPEG; it must improve, not silently fall back.
            check(applied&&after<before*.92&&after<=.10,"real-nef-heldout-color-error-improved");
            double independentBefore=error(neutralSmall,reference),independentAfter=error(cameraSmall,reference);
            measurements.put(new JSONObject().put("case","independent-full-raster-unaligned-reference").put("beforeRgbRmse",independentBefore).put("afterRgbRmse",independentAfter));
            check(independentAfter<independentBefore*.92,"real-nef-independent-all-pixel-color-improvement");
            Object exposedSettings=invoke(settings.getMethod("withExposure",int.class),defaults,10);Object exposed=develop(source,owner,exposedSettings);Bitmap exposedSmall=decodeSmall((File)get(exposed,"workingFile"));
            try{check((Boolean)get(exposed,"cameraColorApplied")&&mean(exposedSmall)>mean(cameraSmall)*1.05,"camera-color-match-preserves-user-plus-one-EV");check(get(exposed,"colorErrorBefore").equals(get(cameraResult,"colorErrorBefore")),"user-edit-reuses-independent-calibration");}finally{exposedSmall.recycle();}
        }finally{neutralSmall.recycle();cameraSmall.recycle();reference.recycle();}
    }
    private static int[] originalPixels(int w,int h){int[] pixels=new int[w*h];Random random=new Random(1141);for(int i=0;i<pixels.length;i++)pixels[i]=0xff000000|random.nextInt(0x1000000);return pixels;}
    private Object callbacks(BooleanSupplier cancel)throws Exception{Constructor<?> constructor=callback.getDeclaredConstructor(BooleanSupplier.class,DoubleConsumer.class);constructor.setAccessible(true);return constructor.newInstance(cancel,null);}
    private Object nativeCall(String name,Class<?>[] types,Object...args)throws Exception{Method method=developer.getDeclaredMethod(name,types);method.setAccessible(true);return invoke(method,null,args);}
    private Object develop(File source,String owner,Object value)throws Exception{return invoke(developer.getMethod("develop",Context.class,File.class,String.class,settings,BooleanSupplier.class,DoubleConsumer.class),null,context,source,owner,value,null,null);}
    private static Object get(Object object,String name)throws Exception{return object.getClass().getField(name).get(object);}
    private static Object invoke(Method method,Object object,Object...args)throws Exception{try{return method.invoke(object,args);}catch(InvocationTargetException wrapper){Throwable t=wrapper.getCause();if(t instanceof Exception)throw (Exception)t;if(t instanceof Error)throw (Error)t;throw wrapper;}}
    private static int[] pixels(Bitmap b){int[] p=new int[b.getWidth()*b.getHeight()];b.getPixels(p,0,b.getWidth(),0,0,b.getWidth(),b.getHeight());return p;}
    private static Bitmap decodeSmall(File file){BitmapFactory.Options o=new BitmapFactory.Options();o.inJustDecodeBounds=true;BitmapFactory.decodeFile(file.getPath(),o);o.inSampleSize=sample(o);o.inJustDecodeBounds=false;return sized(BitmapFactory.decodeFile(file.getPath(),o));}
    private static Bitmap decodeSmall(byte[] bytes){BitmapFactory.Options o=new BitmapFactory.Options();o.inJustDecodeBounds=true;BitmapFactory.decodeByteArray(bytes,0,bytes.length,o);o.inSampleSize=sample(o);o.inJustDecodeBounds=false;return sized(BitmapFactory.decodeByteArray(bytes,0,bytes.length,o));}
    private static int sample(BitmapFactory.Options o){int sample=1;while(Math.max(o.outWidth,o.outHeight)/(double)sample>640)sample*=2;return sample;}
    private static Bitmap sized(Bitmap b){if(b==null)throw new AssertionError("reference decode failed");double scale=Math.min(1,320.0/Math.max(b.getWidth(),b.getHeight()));Bitmap small=Bitmap.createScaledBitmap(b,(int)Math.round(b.getWidth()*scale),(int)Math.round(b.getHeight()*scale),true);if(small!=b)b.recycle();return small;}
    private static double error(Bitmap a,Bitmap b){Bitmap aligned=Bitmap.createScaledBitmap(b,a.getWidth(),a.getHeight(),true);double sum=0;int[] aa=pixels(a),bb=pixels(aligned);if(aligned!=b)aligned.recycle();for(int i=0;i<aa.length;i++)for(int shift:new int[]{0,8,16}){double d=(((aa[i]>>>shift)&255)-((bb[i]>>>shift)&255))/255.0;sum+=d*d;}return Math.sqrt(sum/(aa.length*3.0));}
    private static double mean(Bitmap b){double sum=0;int[] p=pixels(b);for(int c:p)sum+=.2126*((c>>>16)&255)+.7152*((c>>>8)&255)+.0722*(c&255);return sum/p.length;}
    private void save(Bitmap b,String name)throws IOException{try(FileOutputStream stream=new FileOutputStream(new File(output,name))){if(!b.compress(Bitmap.CompressFormat.PNG,100,stream))throw new IOException("Evidence PNG failed");}}
    private void check(boolean pass,String name)throws Exception{checks.put(new JSONObject().put("name",name).put("passed",pass));if(!pass)throw new AssertionError(name);}
}
