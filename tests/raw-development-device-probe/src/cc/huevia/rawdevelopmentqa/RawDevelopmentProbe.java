package cc.huevia.rawdevelopmentqa;

import android.app.Instrumentation;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.Bundle;
import org.json.*;
import java.io.*;
import java.lang.reflect.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.BooleanSupplier;
import java.util.function.DoubleConsumer;

/** Reflection-only actual installed-app RAW engine and Activity verification. */
public final class RawDevelopmentProbe extends Instrumentation {
    public File output;
    private Bundle arguments;private Context context;private String runId,owner,owner2,stage="init";private File fixtureDirectory,externalFixtureDirectory;
    private final JSONArray checks=new JSONArray(),measurements=new JSONArray();private Class<?> developer,settings,whiteBalance;private Throwable failure;private boolean fixtureCleanup;
    @Override public void onCreate(Bundle arguments){super.onCreate(arguments);this.arguments=arguments;start();}
    @Override public void onStart(){
        context=getTargetContext();runId=arguments.getString("runId","");owner="raw-probe-"+runId;owner2=owner+"-isolated";
        if("true".equals(arguments.getString("cleanupOnly"))){cleanupOnly();return;}
        try{
            check(runId.matches("[A-Za-z0-9.-]{8,100}"),"safe-run-id");check("ranchu".equals(android.os.Build.HARDWARE)||"goldfish".equals(android.os.Build.HARDWARE),"emulator-only");
            output=new File(context.getExternalFilesDir(null),"raw-development-109/"+runId).getCanonicalFile();check(!output.exists()&&output.mkdirs(),"new-evidence-directory");
            fixtureDirectory=new File(context.getCacheDir(),"raw-development-qa/"+runId).getCanonicalFile();check(!fixtureDirectory.exists()&&fixtureDirectory.mkdirs(),"new-private-fixture-directory");
            externalFixtureDirectory=new File(context.getExternalCacheDir(),"raw-development-qa/"+runId).getCanonicalFile();
            developer=Class.forName("cc.huevia.album.RawDeveloper",true,context.getClassLoader());settings=Class.forName("cc.huevia.ncp.RawDevelopmentSettings",true,context.getClassLoader());whiteBalance=Class.forName("cc.huevia.ncp.RawDevelopmentSettings$WhiteBalance",true,context.getClassLoader());
            check((Boolean)call(developer.getMethod("available"),null),"native-engine-available");check(((String)call(developer.getMethod("libraryVersion"),null)).contains("0.22.3"),"pinned-libraw-version");writeReport();
            core();stage="raw-activity";RawActivityChecks.run(this,context,new File(fixtureDirectory,"bayer.dng"),checks);writeReport();stage="real-nef";realNef();stage="complete";
        }catch(Throwable error){failure=error;}
        finally{
            try{cleanupOwner(owner);cleanupOwner(owner2);if(fixtureDirectory!=null)deleteOwned(fixtureDirectory,new File(context.getCacheDir(),"raw-development-qa"));if(externalFixtureDirectory!=null&&externalFixtureDirectory.exists())deleteOwned(externalFixtureDirectory,new File(context.getExternalCacheDir(),"raw-development-qa"));fixtureCleanup=true;}catch(Throwable cleanup){if(failure==null)failure=cleanup;}
            try{writeReport();}catch(Throwable ignored){}
            Bundle result=new Bundle();result.putString("pass",String.valueOf(failure==null));result.putString("stage",stage);result.putString("checks",String.valueOf(checks.length()));result.putString("evidence",output==null?"":output.getAbsolutePath());if(failure!=null)result.putString("failure",failure.toString());finish(failure==null?0:1,result);
        }
    }
    private void cleanupOnly(){
        Bundle bundle=new Bundle();boolean pass=false;String error="";
        try{if(!runId.matches("[A-Za-z0-9.-]{8,100}"))throw new IOException("Unsafe cleanup run ID");cleanupOwner(owner);cleanupOwner(owner2);File privateRoot=new File(context.getCacheDir(),"raw-development-qa"),privateRun=new File(privateRoot,runId);if(privateRun.exists())deleteOwned(privateRun,privateRoot);File externalRoot=new File(context.getExternalCacheDir(),"raw-development-qa"),externalRun=new File(externalRoot,runId);if(externalRun.exists())deleteOwned(externalRun,externalRoot);pass=true;}catch(Throwable failure){error=failure.toString();}
        try{File directory=new File(context.getExternalFilesDir(null),"raw-development-109/"+runId).getCanonicalFile();if(directory.isDirectory())Files.write(new File(directory,"cleanup-only.json").toPath(),new JSONObject().put("pass",pass).put("runId",runId).put("error",error).put("scope","App UID removes only this run's generated private fixtures and unique probe-owner caches; no run-as or debuggable app required").toString(2).getBytes(StandardCharsets.UTF_8));}catch(Throwable failure){pass=false;error=failure.toString();}
        bundle.putString("cleanupOnly","true");bundle.putString("pass",String.valueOf(pass));bundle.putString("error",error);finish(pass?0:1,bundle);
    }
    private void core()throws Exception{
        stage="synthetic-dng";File source=new File(fixtureDirectory,"bayer.dng");SyntheticDng.write(source,96,64,1);String original=sha(source);Object info=inspect(source);check(integer(info,"width")==96&&integer(info,"height")==64&&integer(info,"rawWidth")==96&&integer(info,"rawHeight")==64,"full-active-dng-dimensions");check(integer(info,"bits")==12,"dng-sensor-white-level-bits");check(((String)field(info,"decoder")).length()>0,"actual-sensor-decoder-identified");
        Object defaults=settings.getField("DEFAULT").get(null);List<Double> progress=new ArrayList<>();long start=System.nanoTime();Object result=develop(source,owner,defaults,()->false,v->{if(!progress.isEmpty()&&v<progress.get(progress.size()-1))throw new AssertionError("progress went backwards");progress.add(v);});
        check(!(Boolean)field(result,"cached"),"first-raw-development-not-cached");check(sha(source).equals(original),"raw-original-bytes-preserved");check(dimensions(result,96,64),"full-size-srgb-png-without-embedded-jpeg");check(!progress.isEmpty()&&progress.get(progress.size()-1)==1,"raw-progress-completes-monotonically");
        File work=(File)field(result,"workingFile");String workingSha=(String)field(result,"workingSha");check(workingSha.equals(sha(work)),"workspace-png-checksum");double base=brightness(work);check(base>10&&base<245,"demosaic-output-is-visible-image");
        measurements.put(new JSONObject().put("case","synthetic-dng-default").put("elapsedMs",(System.nanoTime()-start)/1e6).put("width",96).put("height",64).put("workingBytes",work.length()).put("meanLuma",base).put("outputBits",8));
        Object cached=develop(source,owner,defaults,null,null);check((Boolean)field(cached,"cached")&&field(cached,"workingFile").equals(work),"exact-source-settings-cache-reuse");
        Object isolated=develop(source,owner2,defaults,null,null);check(!field(isolated,"workingFile").equals(work)&&field(isolated,"workingSha").equals(workingSha),"account-workspaces-isolated");
        Object brighter=develop(source,owner,with(defaults,"withExposure",10),null,null),darker=develop(source,owner,with(defaults,"withExposure",-10),null,null);check(brightness((File)field(brighter,"workingFile"))>base*1.10,"native-plus-one-ev-brightens");check(brightness((File)field(darker,"workingFile"))<base*.90,"native-minus-one-ev-darkens");check(!field(brighter,"cacheIdentity").equals(field(darker,"cacheIdentity")),"raw-exposure-cache-identity");
        Object cold=develop(source,owner,with(defaults,"withTemperature",3000),null,null),warm=develop(source,owner,with(defaults,"withTemperature",9000),null,null);check(redBlue((File)field(warm,"workingFile"))>redBlue((File)field(cold,"workingFile"))*1.1,"custom-camera-matrix-kelvin-changes-colour");
        @SuppressWarnings({"unchecked","rawtypes"}) Object auto=Enum.valueOf((Class)whiteBalance,"AUTO");Object autoSettings=call(settings.getMethod("withWhiteBalance",whiteBalance),defaults,auto);Object automatic=develop(source,owner,autoSettings,null,null);check(!field(automatic,"workingSha").equals(workingSha),"automatic-white-balance-processes-sensor-image");
        Object linear=develop(source,owner,with(defaults,"withDemosaicQuality",0),null,null);check(!field(linear,"workingSha").equals(workingSha),"linear-and-ahd-demosaic-produce-different-pixels");
        Object highlights=develop(source,owner,with(defaults,"withHighlights",3),null,null);check(!field(highlights,"cacheIdentity").equals(field(result,"cacheIdentity")),"raw-highlight-mode-participates-in-identity");
        for(int orientation:new int[]{6,8}){File rotated=new File(fixtureDirectory,"rotated-"+orientation+".dng");SyntheticDng.write(rotated,96,64,orientation);Object rotatedInfo=inspect(rotated),rotatedResult=develop(rotated,owner,defaults,null,null);check(integer(rotatedInfo,"width")==64&&integer(rotatedInfo,"height")==96&&dimensions(rotatedResult,64,96),"raw-orientation-"+orientation+"-full-dimensions");}
        boolean cancelled=false;try{develop(source,owner,with(defaults,"withExposure",11),()->true,null);}catch(InterruptedIOException expected){cancelled=true;}check(cancelled,"raw-pre-cancelled-no-result");AtomicBoolean flag=new AtomicBoolean();cancelled=false;try{develop(source,owner,with(defaults,"withExposure",12),flag::get,v->{if(v>.25)flag.set(true);});}catch(InterruptedIOException expected){cancelled=true;}check(cancelled,"raw-in-flight-callback-cancels");
        File bad=new File(fixtureDirectory,"not-a-raw.dng");byte[] invalid=new byte[256];new Random(14).nextBytes(invalid);Files.write(bad.toPath(),invalid);boolean rejected=false;try{inspect(bad);}catch(IOException expected){rejected=true;}check(rejected,"unsupported-or-damaged-raw-reports-error");
        Files.write(work.toPath(),new byte[]{1,2,3,4});Object rebuilt=develop(source,owner,defaults,null,null);check(!(Boolean)field(rebuilt,"cached")&&field(rebuilt,"workingSha").equals(workingSha),"corrupt-workspace-rebuilt-from-verified-raw");
        File mutating=new File(fixtureDirectory,"mutating.dng");SyntheticDng.write(mutating,96,64,1);AtomicBoolean changed=new AtomicBoolean();rejected=false;try{develop(mutating,owner,with(defaults,"withExposure",13),null,v->{if(v>.8&&changed.compareAndSet(false,true)){try(FileOutputStream append=new FileOutputStream(mutating,true)){append.write(0);}catch(IOException error){throw new RuntimeException(error);}}});}catch(IOException expected){rejected=true;}check(rejected&&changed.get(),"source-change-during-development-prevents-result");check(sha(source).equals(original),"all-raw-controls-preserve-source");writeReport();
    }
    private void realNef()throws Exception{
        String path=arguments.getString("sampleNef","");if(path.isEmpty()){measurements.put(new JSONObject().put("case","real-nef").put("skipped","host did not provide licensed NEF"));return;}
        File source=new File(path).getCanonicalFile();check(source.toPath().startsWith(externalFixtureDirectory.toPath())&&source.isFile(),"owned-real-nef-fixture-path");String expected=arguments.getString("sampleNefSha","");check(expected.matches("[a-f0-9]{64}")&&sha(source).equals(expected),"licensed-nef-fixture-checksum");Object info=inspect(source);check(((String)field(info,"make")).toUpperCase(Locale.ROOT).contains("NIKON"),"real-nikon-header");long pixels=(long)integer(info,"width")*integer(info,"height");check(pixels>20_000_000,"real-nef-inspected-full-active-size");
        long start=System.nanoTime();Object result=develop(source,owner,settings.getField("DEFAULT").get(null),null,null);check(dimensions(result,integer(info,"width"),integer(info,"height")),"real-nef-full-size-png-no-half-size");check(sha(source).equals(expected),"real-nef-original-preserved");measurements.put(new JSONObject().put("case","real-nef").put("make",field(info,"make")).put("model",field(info,"model")).put("decoder",field(info,"decoder")).put("width",integer(info,"width")).put("height",integer(info,"height")).put("sourceSha256",expected).put("workingSha256",field(result,"workingSha")).put("workingBytes",((File)field(result,"workingFile")).length()).put("elapsedMs",(System.nanoTime()-start)/1e6).put("outputBits",8));writeReport();
    }
    private Object inspect(File source)throws Exception{return call(developer.getMethod("inspect",File.class),null,source);}
    private Object develop(File source,String owner,Object settings,BooleanSupplier cancel,DoubleConsumer progress)throws Exception{return call(developer.getMethod("develop",Context.class,File.class,String.class,this.settings,BooleanSupplier.class,DoubleConsumer.class),null,context,source,owner,settings,cancel,progress);}
    private Object with(Object value,String method,int amount)throws Exception{return call(settings.getMethod(method,int.class),value,amount);}
    private static Object call(Method method,Object target,Object...args)throws Exception{try{return method.invoke(target,args);}catch(InvocationTargetException wrapped){Throwable cause=wrapped.getCause();if(cause instanceof Exception)throw (Exception)cause;if(cause instanceof Error)throw (Error)cause;throw new AssertionError(cause);}}
    private static Object field(Object target,String name)throws Exception{return target.getClass().getField(name).get(target);}private static int integer(Object target,String name)throws Exception{return ((Number)field(target,name)).intValue();}
    private boolean dimensions(Object result,int width,int height)throws Exception{Object info=field(result,"info");BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;BitmapFactory.decodeFile(((File)field(result,"workingFile")).getPath(),bounds);return integer(info,"width")==width&&integer(info,"height")==height&&bounds.outWidth==width&&bounds.outHeight==height&&"image/png".equals(bounds.outMimeType);}
    private static double brightness(File file){Bitmap b=BitmapFactory.decodeFile(file.getPath());if(b==null)throw new AssertionError("PNG failed to decode");try{double sum=0;for(int y=0;y<b.getHeight();y++)for(int x=0;x<b.getWidth();x++){int p=b.getPixel(x,y);sum+=(54*((p>>>16)&255)+183*((p>>>8)&255)+19*(p&255))/256.0;}return sum/(b.getWidth()*b.getHeight());}finally{b.recycle();}}
    private static double redBlue(File file){Bitmap b=BitmapFactory.decodeFile(file.getPath());if(b==null)throw new AssertionError("PNG failed to decode");try{double red=0,blue=0;for(int y=0;y<b.getHeight();y++)for(int x=0;x<b.getWidth();x++){int p=b.getPixel(x,y);red+=(p>>>16)&255;blue+=p&255;}return red/Math.max(1,blue);}finally{b.recycle();}}
    private void check(boolean passed,String name)throws JSONException{checks.put(new JSONObject().put("name",name).put("passed",passed));if(!passed)throw new AssertionError(name);}
    private void writeReport()throws Exception{if(output==null)return;JSONObject report=new JSONObject().put("pass",failure==null&&stage.equals("complete")).put("stage",stage).put("apkSha256",arguments.getString("candidateSha256","")).put("checks",checks).put("measurements",measurements).put("fixtureCleanup",fixtureCleanup).put("failure",failure==null?JSONObject.NULL:failure.toString()).put("scope","Actual installed LibRaw native decoding and RAW Activity; generated Bayer DNG has no embedded JPEG. Full active-pixel sRGB PNG output is 8-bit, not a 16-bit Java edit chain. Real NEF optional and explicitly reported. Emulator only.");Files.write(new File(output,"report.json").toPath(),report.toString(2).getBytes(StandardCharsets.UTF_8));}
    private void cleanupOwner(String owner)throws Exception{File root=new File(context.getFilesDir(),"raw-development");File directory=new File(root,hash(owner.getBytes(StandardCharsets.UTF_8)));if(directory.exists())deleteOwned(directory,root);}
    private static void deleteOwned(File file,File root)throws IOException{File canonical=file.getCanonicalFile(),base=root.getCanonicalFile();if(canonical.equals(base)||!canonical.toPath().startsWith(base.toPath()))throw new IOException("Cleanup escaped own fixture root");if(file.isDirectory()&&!Files.isSymbolicLink(file.toPath())){File[] children=file.listFiles();if(children==null)throw new IOException("Cannot list fixture directory");for(File child:children)deleteOwned(child,root);}if(!file.delete()&&file.exists())throw new IOException("Cannot remove own fixture: "+file.getName());}
    private static String sha(File file)throws Exception{MessageDigest digest=MessageDigest.getInstance("SHA-256");byte[] buffer=new byte[65536];try(InputStream input=Files.newInputStream(file.toPath())){int n;while((n=input.read(buffer))!=-1)digest.update(buffer,0,n);}return hex(digest.digest());}private static String hash(byte[] value)throws Exception{return hex(MessageDigest.getInstance("SHA-256").digest(value));}private static String hex(byte[] value){StringBuilder text=new StringBuilder();for(byte b:value)text.append(String.format(Locale.ROOT,"%02x",b&255));return text.toString();}
}
