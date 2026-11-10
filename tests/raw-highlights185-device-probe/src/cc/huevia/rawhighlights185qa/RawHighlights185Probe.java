package cc.huevia.rawhighlights185qa;

import android.app.Instrumentation;
import android.content.Context;
import android.graphics.*;
import android.os.*;
import java.io.*;
import java.lang.reflect.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.*;
import java.util.function.*;
import org.json.*;

/** Runs installed production Java/JNI code. Only own generated or licensed fixtures. */
public final class RawHighlights185Probe extends Instrumentation {
    private Bundle args;private Context context;private File fixtures,output;private String owner;
    private final JSONObject report=new JSONObject();private final JSONArray cases=new JSONArray(),checks=new JSONArray();
    private Class<?> developer,settings,mode;private Object defaults;
    @Override public void onCreate(Bundle args){super.onCreate(args);this.args=args;start();}
    @Override public void onStart(){
        if(args.getString("stageLegacyFixture")!=null){stageLegacyFixture();return;}
        Throwable failure=null;
        try{
            context=getTargetContext();String run=args.getString("runId");
            if(run==null||!run.matches("[A-Za-z0-9.-]{8,100}"))throw new AssertionError("safe run");
            if(!"ranchu".equals(Build.HARDWARE)&&!"goldfish".equals(Build.HARDWARE))throw new AssertionError("owned emulator only");
            owner="raw-highlights185-"+run;fixtures=new File(context.getCacheDir(),owner);output=new File(context.getExternalFilesDir(null),"raw-highlights185/"+run);
            if(!fixtures.mkdirs()||!output.mkdirs())throw new AssertionError("new evidence directories");
            developer=Class.forName("cc.huevia.album.RawDeveloper",true,context.getClassLoader());settings=Class.forName("cc.huevia.ncp.RawDevelopmentSettings",true,context.getClassLoader());mode=Class.forName("cc.huevia.ncp.RawDevelopmentSettings$ColorMode",true,context.getClassLoader());defaults=settings.getField("DEFAULT").get(null);
            report.put("apkSha256",args.getString("candidateSha256")).put("sdk",Build.VERSION.SDK_INT).put("versionCode",context.getPackageManager().getPackageInfo("cc.huevia",0).getLongVersionCode());
            syntheticWhiteFit();
            File supplied=new File(fixtures,"licensed-sample.NEF");
            try(InputStream in=getContext().getAssets().open("qa185-sample.NEF");OutputStream out=new FileOutputStream(supplied)){byte[] bytes=new byte[65536];int n;while((n=in.read(bytes))!=-1)out.write(bytes,0,n);}
            report.put("sampleOrigin","pinned CC0 NEF in local QA APK, copied into own private cache");
            File ramp=new File(fixtures,"neutral-white-ramp.dng");SyntheticDng.whiteRamp(ramp,256,128);String original=sha(ramp);
            Object neutral=withMode(defaults,"NEUTRAL");
            for(int highlight:new int[]{0,1,2,3})render(ramp,"ramp-neutral-H"+highlight,with(neutral,"withHighlights",highlight));
            render(ramp,"ramp-camera-default",defaults);
            if(!original.equals(sha(ramp)))throw new AssertionError("original DNG changed");
            File nef=supplied;
            if(!nef.isFile()||!sha(nef).equals("c079345fc93f53a4f0d322f8ddaae505f920c36015f25b58befccaa61db1af31"))throw new AssertionError("licensed NEF missing/changed");
            render(nef,"nef-neutral-default",neutral);render(nef,"nef-camera-default",defaults);
            fitEvidence(nef,"nef");
            if(!sha(nef).equals("c079345fc93f53a4f0d322f8ddaae505f920c36015f25b58befccaa61db1af31"))throw new AssertionError("original NEF changed");
            File localReference=new File(fixtures,"local-reference.NEF");
            try(InputStream in=getContext().getAssets().open("qa185-local-reference.NEF");OutputStream out=new FileOutputStream(localReference)){byte[] bytes=new byte[65536];int n;while((n=in.read(bytes))!=-1)out.write(bytes,0,n);}
            if(!sha(localReference).equals("142656e30e8735fa29684a3b46145eba0a7b219a947ce6bf45d68a387ceb72e5"))throw new AssertionError("local reference changed");
            render(localReference,"z6ii-neutral-default",neutral);render(localReference,"z6ii-camera-default",defaults);fitEvidence(localReference,"z6ii");
        }catch(Throwable error){failure=error;try{report.put("failure",android.util.Log.getStackTraceString(error));}catch(Exception ignored){}}
        finally{
            try{delete(fixtures,context.getCacheDir());File workspace=new File(new File(context.getFilesDir(),"raw-development"),hex(MessageDigest.getInstance("SHA-256").digest(owner.getBytes(StandardCharsets.UTF_8))));delete(workspace,new File(context.getFilesDir(),"raw-development"));report.put("fixtureCleanup",true);}catch(Throwable error){if(failure==null)failure=error;}
            try{report.put("pass",failure==null).put("cases",cases).put("checks",checks);if(output!=null)Files.write(new File(output,"report.json").toPath(),report.toString(2).getBytes(StandardCharsets.UTF_8));}catch(Throwable ignored){}
            Bundle result=new Bundle();result.putString("pass",String.valueOf(failure==null));if(failure!=null)result.putString("failure",failure.toString());finish(failure==null?0:1,result);
        }
    }
    private void stageLegacyFixture(){
        Bundle result=new Bundle();
        try{
            Context target=getTargetContext();String run=args.getString("stageLegacyFixture");
            if(!run.matches("[A-Za-z0-9.-]{8,100}")||(!"ranchu".equals(Build.HARDWARE)&&!"goldfish".equals(Build.HARDWARE)))throw new IOException("unsafe fixture request");
            File base=new File(target.getExternalCacheDir(),"raw-development-qa").getCanonicalFile(),dir=new File(base,run).getCanonicalFile();
            if(!dir.toPath().startsWith(base.toPath())||dir.equals(base)||dir.exists()||!dir.mkdirs())throw new IOException("new own fixture directory required");
            File nef=new File(dir,"sample.NEF");
            try(InputStream in=getContext().getAssets().open("qa185-sample.NEF");OutputStream out=new FileOutputStream(nef)){byte[] bytes=new byte[65536];int n;while((n=in.read(bytes))!=-1)out.write(bytes,0,n);}
            if(!sha(nef).equals("c079345fc93f53a4f0d322f8ddaae505f920c36015f25b58befccaa61db1af31"))throw new IOException("licensed fixture checksum");
            result.putString("fixturePath",nef.getPath());result.putString("pass","true");finish(0,result);
        }catch(Throwable failure){result.putString("failure",failure.toString());finish(1,result);}
    }
    private void render(File source,String label,Object controls)throws Exception{
        String sourceBefore=sha(source);
        Object result=invoke(developer.getMethod("develop",Context.class,File.class,String.class,settings,BooleanSupplier.class,DoubleConsumer.class),null,context,source,owner,controls,null,null);
        File file=(File)field(result,"workingFile");Bitmap bitmap=small(file);
        try{
            JSONObject row=new JSONObject().put("case",label).put("sourceSha256",sha(source)).put("outputSha256",sha(file)).put("cameraColorApplied",field(result,"cameraColorApplied")).put("colorStatus",field(result,"colorStatus")).put("identity",field(result,"cacheIdentity"));
            row.put("width",bitmap.getWidth()).put("height",bitmap.getHeight()).put("stats",stats(bitmap));
            BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;BitmapFactory.decodeFile(file.getPath(),bounds);
            row.put("fullWidth",bounds.outWidth).put("fullHeight",bounds.outHeight);
            check(sourceBefore.equals(sha(source)),label+"-source-byte-preserved");
            check(bounds.outWidth==(Integer)field(field(result,"info"),"width")&&bounds.outHeight==(Integer)field(field(result,"info"),"height"),label+"-full-size-output");
            if(label.startsWith("ramp-"))row.put("clippedWhite",region(bitmap,.88,.1,.97,.4));
            if(label.equals("ramp-neutral-H2")||label.equals("ramp-camera-default")){JSONObject white=row.getJSONObject("clippedWhite");check(Math.abs(white.getDouble("meanR")-white.getDouble("meanG"))<=1&&Math.abs(white.getDouble("meanB")-white.getDouble("meanG"))<=1,label+"-default-native-white-neutral");}
            cases.put(row);save(bitmap,label+".png");
        }finally{bitmap.recycle();}
    }
    private void fitEvidence(File source,String label)throws Exception{
        Class<?> callback=Class.forName("cc.huevia.album.RawDeveloper$NativeCallbacks",true,context.getClassLoader());Constructor<?> ctor=callback.getDeclaredConstructor(BooleanSupplier.class,DoubleConsumer.class);ctor.setAccessible(true);Object cb=ctor.newInstance((BooleanSupplier)()->false,(DoubleConsumer)v->{});
        Method nativeDevelop=developer.getDeclaredMethod("nativeDevelop",String.class,int.class,int.class,int.class,int.class,int.class,int.class,callback);nativeDevelop.setAccessible(true);
        Bitmap base=(Bitmap)invoke(nativeDevelop,null,source.getPath(),0,5500,0,0,2,3,cb);Object analysis;
        try{Method m=developer.getDeclaredMethod("analysis",Bitmap.class);m.setAccessible(true);analysis=invoke(m,null,base);}finally{base.recycle();}
        Method embedded=developer.getDeclaredMethod("nativeEmbeddedJpeg",String.class,callback);embedded.setAccessible(true);byte[] jpeg=(byte[])invoke(embedded,null,source.getPath(),cb);
        Method reference=developer.getDeclaredMethod("reference",byte[].class);reference.setAccessible(true);Object ref=invoke(reference,null,(Object)jpeg);
        Class<?> matcher=Class.forName("cc.huevia.ncp.RawJpegColorMatch",true,context.getClassLoader());
        Object fit=invoke(matcher.getMethod("fit",int[].class,int.class,int.class,int[].class,int.class,int.class,BooleanSupplier.class),null,field(analysis,"pixels"),field(analysis,"width"),field(analysis,"height"),field(ref,"pixels"),field(ref,"width"),field(ref,"height"),null);
        try(DataOutputStream data=new DataOutputStream(new FileOutputStream(new File(output,label+"-exact-fit-inputs.bin")))){for(Object a:new Object[]{analysis,ref}){data.writeInt((Integer)field(a,"width"));data.writeInt((Integer)field(a,"height"));for(int p:(int[])field(a,"pixels"))data.writeInt(p);}}
        Method apply=fit.getClass().getMethod("applyArgb",int.class);JSONArray axis=new JSONArray();for(int n:new int[]{128,180,200,220,230,240,248,252,255}){int p=0xff000000|n<<16|n<<8|n;int value=(Integer)invoke(apply,fit,p);axis.put(new JSONObject().put("input",n).put("rgb",new JSONArray(new int[]{value>>>16&255,value>>>8&255,value&255})));}
        JSONObject value=new JSONObject().put("accepted",field(fit,"accepted")).put("reason",field(fit,"reason")).put("correlation",field(fit,"correlation")).put("before",field(fit,"beforeError")).put("after",field(fit,"afterError")).put("neutralAxis",axis);
        report.put(label+"ExactProductionCalibration",value);
        if(report.getLong("versionCode")>=185){
            check(((Integer)invoke(apply,fit,0x73ffffff))==0x73ffffff,label+"-display-white-and-alpha-preserved");
            double maximum=0;
            for(int n=128;n<=255;n++){int p=(Integer)invoke(apply,fit,0xff000000|n<<16|n<<8|n),r=p>>>16&255,g=p>>>8&255,b=p&255;double light=.2126*r+.7152*g+.0722*b;if(light+3<maximum)throw new AssertionError(label+"-highlight-foldback");maximum=Math.max(maximum,light);if(n>=220&&Math.min(r,b)-g>8)throw new AssertionError(label+"-neutral-highlight-magenta");}
            check(true,label+"-neutral-highlight-gradient-safe");
        }
        int[] pixels=(int[])field(analysis,"pixels");int w=(Integer)field(analysis,"width"),h=(Integer)field(analysis,"height");Bitmap b=Bitmap.createBitmap(pixels,w,h,Bitmap.Config.ARGB_8888);try{save(b,label+"-native-calibration.png");}finally{b.recycle();}
    }
    private void syntheticWhiteFit()throws Exception{
        int w=192,h=128;int[] source=new int[w*h],reference=new int[w*h];
        for(int y=0;y<h;y++)for(int x=0;x<w;x++){
            double u=x/(double)(w-1),v=y/(double)(h-1);
            int r=channel(.42+.21*Math.sin(u*8.3+v*2.6)+.11*Math.cos(v*13.1-u*3.7)),g=channel(.46+.19*Math.cos(u*5.2-v*7.3)+.12*Math.sin(v*11.4+u*2.3)),b=channel(.43+.22*Math.sin(u*11.3-v*4.1)+.12*Math.cos(v*8.8+u*1.9));int i=y*w+x;
            source[i]=0xff000000|r<<16|g<<8|b;reference[i]=0xff000000|channel(.1+1.15*r/255.0)<<16|channel(.1+.74*g/255.0)<<8|channel(.1+1.15*b/255.0);
            if(x>140&&y<30){int n=220+(x-141)*35/50;source[i]=0xff000000|n<<16|n<<8|n;reference[i]=0xffffffff;}
        }
        Class<?> matcher=Class.forName("cc.huevia.ncp.RawJpegColorMatch",true,context.getClassLoader());Object fit=invoke(matcher.getMethod("fit",int[].class,int.class,int.class,int[].class,int.class,int.class,BooleanSupplier.class),null,source,w,h,reference,w,h,null);
        Bitmap bitmap=Bitmap.createBitmap(source,w,h,Bitmap.Config.ARGB_8888);
        try{
            float[] table=(float[])invoke(fit.getClass().getMethod("table"),fit);
            if((Boolean)field(fit,"accepted")&&table.length>0){Class<?> callback=Class.forName("cc.huevia.album.RawDeveloper$NativeCallbacks",true,context.getClassLoader());Constructor<?> ctor=callback.getDeclaredConstructor(BooleanSupplier.class,DoubleConsumer.class);ctor.setAccessible(true);Object cb=ctor.newInstance((BooleanSupplier)()->false,(DoubleConsumer)value->{});Method apply=developer.getDeclaredMethod("nativeApplyColor",Bitmap.class,float[].class,callback);apply.setAccessible(true);invoke(apply,null,bitmap,table,cb);}
            int maxPink=0;for(int y=5;y<25;y++)for(int x=145;x<187;x++){int p=bitmap.getPixel(x,y);maxPink=Math.max(maxPink,Math.min(p>>>16&255,p&255)-(p>>>8&255));}
            boolean baseline=report.getLong("versionCode")==184;
            check(baseline?maxPink>=30:maxPink<=3,baseline?"baseline184-confident-fit-turns-white-magenta":"fixed185-native-color-path-keeps-white-neutral");
            report.put("syntheticWhiteReference",new JSONObject().put("accepted",field(fit,"accepted")).put("reason",field(fit,"reason")).put("maxPinkDelta",maxPink).put("nativeLutApplied",table.length>0));
            save(bitmap,"generated-camera-white.png");Bitmap ref=Bitmap.createBitmap(reference,w,h,Bitmap.Config.ARGB_8888);try{save(ref,"generated-jpeg-reference.png");}finally{ref.recycle();}
        }finally{bitmap.recycle();}
    }
    private static int channel(double v){return Math.max(0,Math.min(255,(int)Math.round(v*255)));}
    private void check(boolean passed,String name)throws Exception{checks.put(new JSONObject().put("name",name).put("passed",passed));if(!passed)throw new AssertionError(name);}
    private static JSONObject region(Bitmap b,double x0,double y0,double x1,double y1)throws Exception{double[] s=new double[3];int n=0;for(int y=(int)(b.getHeight()*y0);y<(int)(b.getHeight()*y1);y++)for(int x=(int)(b.getWidth()*x0);x<(int)(b.getWidth()*x1);x++){int p=b.getPixel(x,y);s[0]+=p>>>16&255;s[1]+=p>>>8&255;s[2]+=p&255;n++;}return new JSONObject().put("meanR",s[0]/n).put("meanG",s[1]/n).put("meanB",s[2]/n).put("pixels",n);}
    private static JSONObject stats(Bitmap b)throws Exception{int white=0,pink=0,maxPink=0;for(int y=0;y<b.getHeight();y++)for(int x=0;x<b.getWidth();x++){int p=b.getPixel(x,y),r=p>>>16&255,g=p>>>8&255,blue=p&255;if(Math.min(r,Math.min(g,blue))>=220){white++;int d=(r+blue)/2-g;maxPink=Math.max(maxPink,d);if(d>=10)pink++;}}return new JSONObject().put("brightPixels",white).put("pinkBrightPixels",pink).put("maxPinkDelta",maxPink);}
    @SuppressWarnings({"unchecked","rawtypes"})private Object withMode(Object value,String name)throws Exception{return invoke(settings.getMethod("withColorMode",mode),value,Enum.valueOf((Class)mode,name));}
    private Object with(Object value,String method,int n)throws Exception{return invoke(settings.getMethod(method,int.class),value,n);}
    private static Bitmap small(File file){BitmapFactory.Options o=new BitmapFactory.Options();o.inJustDecodeBounds=true;BitmapFactory.decodeFile(file.getPath(),o);o.inSampleSize=1;while(Math.max(o.outWidth,o.outHeight)/o.inSampleSize>640)o.inSampleSize*=2;o.inJustDecodeBounds=false;Bitmap b=BitmapFactory.decodeFile(file.getPath(),o);if(b==null)throw new AssertionError("PNG decode");double scale=Math.min(1,320.0/Math.max(b.getWidth(),b.getHeight()));Bitmap s=Bitmap.createScaledBitmap(b,Math.max(1,(int)Math.round(b.getWidth()*scale)),Math.max(1,(int)Math.round(b.getHeight()*scale)),true);if(s!=b)b.recycle();return s;}
    private void save(Bitmap bitmap,String name)throws IOException{try(OutputStream stream=new FileOutputStream(new File(output,name))){if(!bitmap.compress(Bitmap.CompressFormat.PNG,100,stream))throw new IOException("PNG evidence");}}
    private static Object field(Object target,String name)throws Exception{Field f=target.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(target);}
    private static Object invoke(Method m,Object target,Object...args)throws Exception{try{return m.invoke(target,args);}catch(InvocationTargetException e){Throwable t=e.getCause();if(t instanceof Exception)throw (Exception)t;if(t instanceof Error)throw (Error)t;throw new AssertionError(t);}}
    private static String sha(File f)throws Exception{MessageDigest d=MessageDigest.getInstance("SHA-256");try(InputStream in=new FileInputStream(f)){byte[] b=new byte[65536];int n;while((n=in.read(b))!=-1)d.update(b,0,n);}return hex(d.digest());}
    private static String hex(byte[] bytes){StringBuilder b=new StringBuilder();for(byte v:bytes)b.append(String.format(Locale.ROOT,"%02x",v&255));return b.toString();}
    private static void delete(File f,File base)throws IOException{if(f==null||!f.exists())return;File p=f.getCanonicalFile(),root=base.getCanonicalFile();if(p.equals(root)||!p.toPath().startsWith(root.toPath()))throw new IOException("fixture cleanup boundary");if(p.isDirectory()){File[] children=p.listFiles();if(children==null)throw new IOException("fixture list");for(File c:children)delete(c,base);}if(!p.delete()&&p.exists())throw new IOException("fixture delete");}
}
