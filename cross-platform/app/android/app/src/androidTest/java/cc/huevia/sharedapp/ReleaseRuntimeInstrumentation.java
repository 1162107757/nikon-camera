package cc.huevia.sharedapp;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.Bundle;
import android.os.SystemClock;
import android.util.Log;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.*;
import java.lang.reflect.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.function.DoubleConsumer;

/** Exercises the installed R8 APK. No target DTO, implementation class or keep rule is required. */
public final class ReleaseRuntimeInstrumentation extends Instrumentation {
    private static final String TAG="HueviaR8Runtime";
    private Bundle arguments;
    private int checks;
    private Activity activity;
    private Object media;
    private Method request;
    private Class<?> cancelType,progressType;
    private Constructor<?> cancelConstructor,progressConstructor;
    private Method cancelReader;
    private int cancelClassId;
    private ExecutorService worker;
    private File root;
    private String owner;
    private final LinkedHashSet<File> owned=new LinkedHashSet<>();
    private final Map<String,Set<String>> priorCaches=new HashMap<>();
    private final JSONObject evidence=new JSONObject();

    @Override public void onCreate(Bundle value){super.onCreate(value);arguments=value==null?new Bundle():value;start();}
    @Override public void onStart(){
        Bundle result=new Bundle();Throwable failure=null;
        try {
            final String mediaField=required("mediaField"),mediaMethod=required("mediaMethod"),workerField=required("workerField");
            owner=arguments.getString("owner","");
            yes((getTargetContext().getApplicationInfo().flags&ApplicationInfo.FLAG_DEBUGGABLE)==0,"installed target is a non-debuggable release APK");
            Intent intent=new Intent().setClassName(getTargetContext(),"cc.huevia.sharedapp.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            activity=startActivitySync(intent);
            yes(activity!=null,"release MainActivity started through instrumentation");
            root=new File(getTargetContext().getFilesDir(),"huevia-shared").getCanonicalFile();
            for(String name:new String[]{"preset-previews","previews","raw-thumbnails"})priorCaches.put(name,snapshot(new File(root,name)));
            bind(mediaField,mediaMethod,workerField);
            evidence.put("mediaField",mediaField).put("mediaMethod",mediaMethod).put("workerField",workerField).put("mediaRuntimeClass",media.getClass().getName());
            portraitChecks();
            rawChecks();
        }catch(Throwable value){failure=unwrap(value);}
        finally {
            try {cleanup();}catch(Throwable value){if(failure==null)failure=value;else failure.addSuppressed(value);}
            if(activity!=null){try{runOnMainSync(()->activity.finish());}catch(Throwable value){if(failure==null)failure=value;else failure.addSuppressed(value);}}
        }
        result.putInt("checks",checks);result.putString("evidence",evidence.toString());
        if(failure==null){
            String summary="PASS "+checks+" R8 release runtime checks; real mesh, semantic skin, renderer, patch, cancellation and RAW JNI callbacks\n";
            Log.i(TAG,summary);result.putString("stream",summary);finish(Activity.RESULT_OK,result);
        }else{
            String summary="FAIL after "+checks+" R8 release runtime checks: "+failure+"\n"+Log.getStackTraceString(failure)+"\n";
            Log.e(TAG,summary);result.putString("stream",summary);finish(Activity.RESULT_CANCELED,result);
        }
    }
    private String required(String name){String value=arguments.getString(name);if(value==null||value.isEmpty())throw new AssertionError("Pass the current release mapping argument "+name+"; production keep rules must not be changed for this test");return value;}
    private void yes(boolean value,String label){checks++;if(!value)throw new AssertionError(label);Log.i(TAG,"check "+checks+": "+label);}
    private static Field field(Class<?> type,String name)throws NoSuchFieldException{
        for(Class<?> current=type;current!=null;current=current.getSuperclass()){try{Field value=current.getDeclaredField(name);value.setAccessible(true);return value;}catch(NoSuchFieldException ignored){}}
        throw new NoSuchFieldException("Release mapping field "+name+" is absent in "+type.getName());
    }
    private void bind(String mediaField,String mediaMethod,String workerField)throws Exception {
        Field executor=field(activity.getClass(),workerField),backend=field(activity.getClass(),mediaField);
        Object value=executor.get(activity);yes(value instanceof ExecutorService,"mapped activity worker is an ExecutorService");worker=(ExecutorService)value;
        long deadline=SystemClock.elapsedRealtime()+60_000;
        do {
            media=await(worker.submit(()->backend.get(activity)));
            if(media!=null)break;SystemClock.sleep(25);
        }while(SystemClock.elapsedRealtime()<deadline);
        yes(media!=null,"Flutter initialization created the release native media backend");
        JSONArray declared=new JSONArray(),named=new JSONArray();List<Method> candidates=new ArrayList<>();
        for(Method method:media.getClass().getDeclaredMethods()){
            declared.put(method.toGenericString());
            if(!method.getName().equals(mediaMethod))continue;
            named.put(method.toGenericString());Log.i(TAG,"mapped request candidate: "+method.toGenericString());
            Class<?>[] types=method.getParameterTypes();
            if(types.length==4&&types[0]==String.class&&types[1]==String.class&&method.getReturnType()==String.class&&!Modifier.isStatic(method.getModifiers()))candidates.add(method);
        }
        evidence.put("requestCandidates",named);
        if(candidates.size()!=1)throw new NoSuchMethodException("Expected one mapped instance JSON entry named "+mediaMethod+" with four parameters beginning String,String; found "+candidates.size()+". Actual declarations: "+declared);
        request=candidates.get(0);request.setAccessible(true);cancelType=request.getParameterTypes()[2];progressType=request.getParameterTypes()[3];
        yes(request.getReturnType()==String.class,"mapped media entry retains its JSON String return");
        evidence.put("cancelType",cancelType.getName()).put("progressType",progressType.getName());
        bindCallbacks();
    }
    private void bindCallbacks()throws Exception {
        for(Method method:cancelType.getDeclaredMethods())if(method.getReturnType()==boolean.class&&method.getParameterTypes().length==0&&!Modifier.isStatic(method.getModifiers())){
            if(cancelReader!=null)throw new NoSuchMethodException("Ambiguous release cancellation readers in "+cancelType.getName());
            cancelReader=method;cancelReader.setAccessible(true);
        }
        if(cancelReader==null)for(Method method:cancelType.getMethods())if(method.getReturnType()==boolean.class&&method.getParameterTypes().length==0&&!Modifier.isStatic(method.getModifiers())){cancelReader=method;break;}
        if(cancelReader==null)throw new NoSuchMethodException("No boolean() cancellation reader in "+cancelType.getName());
        if(cancelType.isInterface())evidence.put("cancelAdapter","runtime-interface-proxy");
        else {
            JSONArray attempts=new JSONArray();Constructor<?> constructor=cancelType.getDeclaredConstructor(int.class,Object.class);constructor.setAccessible(true);
            // R8 can merge synthetic AtomicBoolean captures. Only a bounded,
            // behavior-verified variant may be passed to the release backend.
            for(int classId=0;classId<8;classId++){
                AtomicBoolean probe=new AtomicBoolean();
                try {
                    Object instance=constructor.newInstance(classId,probe);
                    boolean initial=(Boolean)cancelReader.invoke(instance);probe.set(true);boolean signaled=(Boolean)cancelReader.invoke(instance);probe.set(false);boolean reset=(Boolean)cancelReader.invoke(instance);
                    if(!initial&&signaled&&!reset){cancelConstructor=constructor;cancelClassId=classId;break;}
                    attempts.put(new JSONObject().put("classId",classId).put("initial",initial).put("signaled",signaled).put("reset",reset));
                }catch(ReflectiveOperationException|RuntimeException failure){attempts.put(new JSONObject().put("classId",classId).put("error",unwrap(failure).toString()));}
                finally{probe.set(false);}
            }
            if(cancelConstructor==null)throw new ReflectiveOperationException("No bounded synthetic cancellation variant captured AtomicBoolean correctly: "+attempts);
            evidence.put("cancelAdapter","verified-atomic-boolean-capture").put("cancelClassId",cancelClassId).put("cancelConstructor",cancelConstructor.toGenericString());
        }
        yes(cancelType.isInterface()||cancelConstructor!=null,"release cancellation callback is supported and false/true/reset verified");
        if(progressType.isInterface())evidence.put("progressAdapter","runtime-interface-proxy");
        else {
            JSONArray constructors=new JSONArray();
            for(Constructor<?> constructor:progressType.getDeclaredConstructors()){
                constructors.put(constructor.toGenericString());Class<?>[] parameters=constructor.getParameterTypes();
                if(parameters.length==4&&parameters[0].isInstance(activity)&&parameters[1]==double[].class&&parameters[2]==long[].class&&parameters[3]==String.class){
                    if(progressConstructor!=null)throw new NoSuchMethodException("Ambiguous activity progress captures in "+progressType.getName());
                    progressConstructor=constructor;progressConstructor.setAccessible(true);
                }
            }
            if(progressConstructor==null)throw new NoSuchMethodException("No release activity progress capture constructor: "+constructors);
            evidence.put("progressAdapter","activity-progress-capture").put("progressConstructor",progressConstructor.toGenericString());
        }
        yes(progressType.isInterface()||progressConstructor!=null,"release progress callback supports the actual runtime parameter type");
        Log.i(TAG,"release callback adapters: "+evidence);
    }
    private JSONObject call(String operation,JSONObject payload)throws Exception {
        final String frozen=payload.toString();
        return await(worker.submit(()->invoke(operation,frozen,new AtomicBoolean(),value->{if(!Double.isFinite(value)||value<0||value>1)throw new AssertionError("Invalid native progress "+value);})));
    }
    private JSONObject invoke(String operation,String json,AtomicBoolean cancel,DoubleConsumer progress)throws Exception {
        return invokePrepared(operation,json,cancelCallback(cancel),progressCallback(progress));
    }
    private JSONObject invokePrepared(String operation,String json,Object cancel,Object progress)throws Exception {
        try {
            Object value=request.invoke(media,operation,json,cancel,progress);
            if(!(value instanceof String))throw new AssertionError("Native media returned a non-JSON result for "+operation);
            return new JSONObject((String)value);
        }catch(InvocationTargetException wrapped){throwException(unwrap(wrapped));return null;}
    }
    private Object cancelCallback(AtomicBoolean flag)throws ReflectiveOperationException {
        if(cancelConstructor!=null)return cancelConstructor.newInstance(cancelClassId,flag);
        return Proxy.newProxyInstance(cancelType.getClassLoader(),new Class<?>[]{cancelType},(proxy,method,args)->{
            if(method.getDeclaringClass()==Object.class)return objectMethod(proxy,method,args,"Release cancellation adapter");
            if(method.getReturnType()==boolean.class&&method.getParameterTypes().length==0)return flag.get();
            throw new UnsupportedOperationException("Unexpected release cancellation interface method: "+method.toGenericString());
        });
    }
    private Object progressCallback(DoubleConsumer callback)throws ReflectiveOperationException {
        if(progressConstructor!=null)return progressConstructor.newInstance(activity,new double[]{-1},new long[]{0},"r8-runtime-"+UUID.randomUUID());
        return progressProxy(callback);
    }
    private Object progressProxy(DoubleConsumer callback){
        return Proxy.newProxyInstance(progressType.getClassLoader(),new Class<?>[]{progressType},(proxy,method,args)->{
            if(method.getDeclaringClass()==Object.class)return objectMethod(proxy,method,args,"Release progress adapter");
            Class<?>[] parameters=method.getParameterTypes();
            if(method.getReturnType()==void.class&&parameters.length==1&&parameters[0]==double.class){callback.accept(((Number)args[0]).doubleValue());return null;}
            if(method.getReturnType()==progressType&&parameters.length==1&&parameters[0]==progressType){
                final Object after=Objects.requireNonNull(args[0]);final Method accept=progressAccept();
                return progressProxy(value->{callback.accept(value);try{accept.invoke(after,value);}catch(InvocationTargetException failure){Throwable cause=unwrap(failure);if(cause instanceof RuntimeException)throw (RuntimeException)cause;if(cause instanceof Error)throw (Error)cause;throw new AssertionError(cause);}catch(ReflectiveOperationException failure){throw new AssertionError(failure);}});
            }
            throw new UnsupportedOperationException("Unexpected release progress interface method: "+method.toGenericString());
        });
    }
    private Method progressAccept()throws NoSuchMethodException{
        for(Method method:progressType.getMethods()){Class<?>[] parameters=method.getParameterTypes();if(method.getReturnType()==void.class&&parameters.length==1&&parameters[0]==double.class)return method;}
        throw new NoSuchMethodException("No void(double) callback in actual release interface "+progressType.getName());
    }
    private static Object objectMethod(Object proxy,Method method,Object[] args,String label){
        switch(method.getName()){case "equals":return args!=null&&args.length==1&&proxy==args[0];case "hashCode":return System.identityHashCode(proxy);case "toString":return label;default:throw new UnsupportedOperationException(method.toGenericString());}
    }
    private static <T>T await(Future<T> pending)throws Exception {
        try{return pending.get(3,TimeUnit.MINUTES);}catch(ExecutionException wrapped){throwException(unwrap(wrapped));return null;}catch(TimeoutException timeout){pending.cancel(true);throw new IOException("Timed out on the release serial media worker",timeout);}
    }
    private static Throwable unwrap(Throwable value){while((value instanceof InvocationTargetException||value instanceof ExecutionException)&&value.getCause()!=null)value=value.getCause();return value;}
    private static void throwException(Throwable value)throws Exception{if(value instanceof Exception)throw (Exception)value;if(value instanceof Error)throw (Error)value;throw new AssertionError(value);}
    private JSONObject payload(File source,String local)throws Exception{return new JSONObject().put("path",source.getPath()).put("owner",owner).put("localData",local);}
    private JSONObject preview(File source,String local)throws Exception {
        JSONObject value=call("media.reviewPreview",new JSONObject().put("path",source.getPath()).put("owner",owner).put("maxEdge",640).put("recipe",new JSONObject().put("schema",1).put("localData",local)));
        File output=remember(value,"previews");yes(output.isFile()&&output.length()>1000,"release renderer wrote a separate JPEG preview");
        yes(!output.equals(source),"preview never replaces its source");return value;
    }
    private void portraitChecks()throws Exception {
        JSONObject sample=call("media.templateSource",new JSONObject().put("index",0));
        File template=remember(sample,"preset-previews");String templateSha=hash(template);
        File source=createSource("jpg");copy(new FileInputStream(template),source,null);String original=hash(source);
        yes(templateSha.equals(original),"owned portrait is an exact copy of the real built-in sample");
        JSONObject faces=call("media.retouchAnalyze",payload(source,"").put("mode","face"));
        JSONArray found=faces.getJSONObject("portrait").getJSONArray("faces");yes(found.length()>0,"release runtime detected a real face");
        for(int i=0;i<found.length();i++)yes(found.getJSONObject(i).getBoolean("hasLandmarks"),"release runtime produced real face mesh "+i);
        JSONObject skin=call("media.retouchAnalyze",payload(source,faces.getString("localData")).put("mode","skin"));
        JSONObject portrait=skin.getJSONObject("portrait");yes(portrait.getBoolean("hasSkinMask")&&portrait.getInt("skinPixels")>=32,"release original semantic model produced nonempty skin coverage");
        JSONObject neutral=preview(source,skin.getString("localData"));
        JSONObject changed=call("media.retouchChange",payload(source,skin.getString("localData")).put("action","face").put("index",0).put("value",new JSONObject().put("brightness",28).put("smoothing",35).put("EYE_DETAIL",30).put("TEETH",20).put("NATURAL",20)));
        JSONObject selected=changed.getJSONObject("portrait").getJSONArray("faces").getJSONObject(0);
        yes(selected.getInt("brightness")==28&&selected.getInt("EYE_DETAIL")==30&&selected.getInt("TEETH")==20,"release DTO retains applied portrait and eye/teeth controls");
        JSONObject rendered=preview(source,changed.getString("localData"));
        int differences=pixelDifferences(new File(neutral.getString("path")),new File(rendered.getString("path")));
        yes(differences>0,"release original renderer changed sampled RGB pixels");
        JSONObject patched=call("media.retouchPatch",payload(source,changed.getString("localData")).put("points",new JSONArray().put(.70).put(.30).put(.71).put(.30)).put("radius",.01));
        yes(patched.getInt("patchCount")==1,"release sampler created a real frozen donor patch");
        preview(source,patched.getString("localData"));
        JSONObject undone=call("media.retouchDescribe",payload(source,changed.getString("localData")));
        yes(undone.getInt("patchCount")==0,"immutable pre-patch data remains available for undo");
        cancellation(source,changed.getString("localData"));
        yes(original.equals(hash(source)),"portrait source SHA is unchanged after inference, render, patch and cancel");
        yes(templateSha.equals(hash(template)),"built-in template bytes are unchanged");
        evidence.put("portraitSha256",original).put("faceCount",found.length()).put("skinPixels",portrait.getInt("skinPixels")).put("changedPixelSamples",differences);
    }
    private void cancellation(File source,String local)throws Exception {
        AtomicBoolean cancel=new AtomicBoolean(),running=new AtomicBoolean();AtomicLong signaledAt=new AtomicLong();
        ScheduledExecutorService timer=Executors.newSingleThreadScheduledExecutor();
        Throwable failure=null;final Object callback=cancelCallback(cancel),progress=progressCallback(value->{});
        yes(!(Boolean)cancelReader.invoke(callback),"actual release cancellation capture initially reads false");
        try {
            // Face refinement executes fresh detector/mesh work; the whole-skin
            // analyzer may legitimately reuse its previously verified result.
            final String frozen=payload(source,local).put("mode","face").toString();
            Future<JSONObject> pending=worker.submit(()->{
                running.set(true);
                ScheduledFuture<?> signal=timer.schedule(()->{if(running.get()){signaledAt.set(SystemClock.elapsedRealtime());cancel.set(true);}},25,TimeUnit.MILLISECONDS);
                try{return invokePrepared("media.retouchAnalyze",frozen,callback,progress);}finally{running.set(false);signal.cancel(false);}
            });
            try{await(pending);}catch(Throwable value){failure=unwrap(value);}
        }finally{timer.shutdownNow();timer.awaitTermination(5,TimeUnit.SECONDS);}
        yes(cancel.get()&&signaledAt.get()>0&&(Boolean)cancelReader.invoke(callback),"cancellation was signaled during the release request and its actual capture reads true");
        boolean canceled=false;for(Throwable value=failure;value!=null;value=value.getCause()){String message=String.valueOf(value.getMessage());if(value instanceof InterruptedIOException||message.contains("取消")||message.contains("停止")){canceled=true;break;}}
        yes(canceled,"release in-flight portrait computation rejected the canceled result");
        cancel.set(false);yes(!(Boolean)cancelReader.invoke(callback),"actual release cancellation capture resets to false");
    }
    private void rawChecks()throws Exception {
        File source=createSource("dng");
        // TIFF readers follow referenced IFD/strip offsets. This unreferenced
        // trailer changes only this owned fixture's SHA and guarantees a cache miss.
        byte[] marker=("\nHuevia-R8-owned-fixture:"+UUID.randomUUID()+"\n").getBytes(StandardCharsets.UTF_8);
        copy(getContext().getAssets().open("raw-stack.dng"),source,marker);String original=hash(source);long bytes=source.length();
        JSONObject info=call("media.info",new JSONObject().put("path",source.getPath()));yes(info.getBoolean("raw"),"uniquely marked owned DNG remains a real RAW");
        JSONObject thumbnail=call("media.rawThumbnail",new JSONObject().put("path",source.getPath()).put("owner",owner));
        File output=remember(thumbnail,"raw-thumbnails");
        yes(thumbnail.has("width")&&thumbnail.has("height"),"release RAW executed the fresh native/JNI branch rather than an old display cache");
        yes(original.equals(thumbnail.getString("sourceSha")),"RAW thumbnail identifies the exact uniquely owned source");
        BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;BitmapFactory.decodeFile(output.getPath(),bounds);
        yes(bounds.outWidth>0&&bounds.outHeight>0&&Math.max(bounds.outWidth,bounds.outHeight)<=512,"release RAW JNI produced a bounded <=512px encoded preview");
        Bitmap decoded=BitmapFactory.decodeFile(output.getPath());yes(decoded!=null,"release RAW JNI output is a decodable JPEG");if(decoded!=null)decoded.recycle();
        yes(source.length()==bytes&&original.equals(hash(source)),"RAW source length and SHA remain unchanged after actual JNI callbacks");
        evidence.put("rawSha256",original).put("rawBytes",bytes).put("rawWidth",bounds.outWidth).put("rawHeight",bounds.outHeight).put("rawEmbedded",thumbnail.optBoolean("embeddedPreview",false));
    }
    private File createSource(String extension)throws Exception {
        File directory=new File(root,"originals").getCanonicalFile();yes(directory.getParentFile().equals(root),"owned source directory stays in the target private root");
        if(Files.isSymbolicLink(directory.toPath())||!directory.isDirectory()&&!directory.mkdirs())throw new IOException("Cannot create the owned source directory");
        File source=new File(directory,"r8-owned-"+UUID.randomUUID()+"."+extension).getCanonicalFile();if(!source.getParentFile().equals(directory)||source.exists())throw new IOException("Owned source path collision");owned.add(source);return source;
    }
    private File remember(JSONObject result,String cache)throws Exception {
        File supplied=new File(result.getString("path")),file=supplied.getCanonicalFile(),directory=new File(root,cache).getCanonicalFile();
        yes(file.equals(supplied)&&file.getParentFile().equals(directory)&&directory.getParentFile().equals(root)&&!Files.isSymbolicLink(file.toPath())&&!Files.isSymbolicLink(directory.toPath()),"returned "+cache+" path is confined to the target cache");
        if(!priorCaches.get(cache).contains(file.getPath()))owned.add(file);return file;
    }
    private static Set<String> snapshot(File directory)throws IOException {Set<String> paths=new HashSet<>();File[] files=directory.listFiles();if(files!=null)for(File file:files)paths.add(file.getCanonicalPath());return paths;}
    private static void copy(InputStream input,File target,byte[] trailer)throws IOException {
        try(InputStream in=input;FileOutputStream out=new FileOutputStream(target)){byte[] block=new byte[65536];int count;while((count=in.read(block))!=-1)out.write(block,0,count);if(trailer!=null)out.write(trailer);out.getFD().sync();}
    }
    private static String hash(File file)throws Exception {
        MessageDigest digest=MessageDigest.getInstance("SHA-256");try(InputStream in=new FileInputStream(file)){byte[] block=new byte[65536];int count;while((count=in.read(block))!=-1)digest.update(block,0,count);}StringBuilder out=new StringBuilder();for(byte value:digest.digest())out.append(String.format(Locale.ROOT,"%02x",value&255));return out.toString();
    }
    private int pixelDifferences(File first,File second)throws IOException {
        Bitmap before=BitmapFactory.decodeFile(first.getPath()),after=BitmapFactory.decodeFile(second.getPath());
        try{if(before==null||after==null)throw new IOException("Cannot decode release portrait comparison");yes(before.getWidth()==after.getWidth()&&before.getHeight()==after.getHeight(),"portrait comparison uses identical pixel geometry");int changed=0;for(int y=0;y<before.getHeight();y+=Math.max(1,before.getHeight()/48))for(int x=0;x<before.getWidth();x+=Math.max(1,before.getWidth()/48)){int a=before.getPixel(x,y),b=after.getPixel(x,y);if(Math.abs(((a>>16)&255)-((b>>16)&255))+Math.abs(((a>>8)&255)-((b>>8)&255))+Math.abs((a&255)-(b&255))>3)changed++;}return changed;}
        finally{if(before!=null)before.recycle();if(after!=null)after.recycle();}
    }
    private void cleanup()throws IOException {
        List<File> files=new ArrayList<>(owned);Collections.reverse(files);IOException failure=null;
        for(File file:files){try{File canonical=file.getCanonicalFile();if(root==null||!canonical.equals(file)||!canonical.toPath().startsWith(root.toPath())||Files.isSymbolicLink(file.toPath()))throw new IOException("Refusing to clean a non-owned canonical path: "+file);Files.deleteIfExists(file.toPath());}catch(IOException value){if(failure==null)failure=value;else failure.addSuppressed(value);}}
        if(failure!=null)throw failure;
    }
}
