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
    private Constructor<?> cancelConstructor,progressConstructor,taskFlagConstructor;
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
            detailChecks();
            rawChecks();
        }catch(Throwable value){failure=unwrap(value);}
        finally {
            try {cleanup();}catch(Throwable value){if(failure==null)failure=value;else failure.addSuppressed(value);}
            if(activity!=null){try{runOnMainSync(()->activity.finish());}catch(Throwable value){if(failure==null)failure=value;else failure.addSuppressed(value);}}
        }
        result.putInt("checks",checks);result.putString("evidence",evidence.toString());
        if(failure==null){
            String summary="PASS "+checks+" R8 release runtime checks; real mesh, semantic skin, renderer, read-only full details, patch, cancellation and RAW JNI callbacks\n";
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
        String taskClass=arguments.getString("taskClass","");
        if(!taskClass.isEmpty()){
            Class<?> type=Class.forName(taskClass,true,activity.getClassLoader());
            if(!AtomicBoolean.class.isAssignableFrom(type))throw new ReflectiveOperationException("Mapped production cancellation flag is not AtomicBoolean: "+type);
            taskFlagConstructor=type.getDeclaredConstructor();taskFlagConstructor.setAccessible(true);
            evidence.put("taskFlagClass",type.getName()).put("taskFlagConstructor",taskFlagConstructor.toGenericString());
        }else if(!cancelType.isInterface())throw new ReflectiveOperationException("The exact mapped production taskClass is required for the release cancellation capture.");
        for(Method method:cancelType.getDeclaredMethods())if(method.getReturnType()==boolean.class&&method.getParameterTypes().length==0&&!Modifier.isStatic(method.getModifiers())){
            if(cancelReader!=null)throw new NoSuchMethodException("Ambiguous release cancellation readers in "+cancelType.getName());
            cancelReader=method;cancelReader.setAccessible(true);
        }
        if(cancelReader==null)for(Method method:cancelType.getMethods())if(method.getReturnType()==boolean.class&&method.getParameterTypes().length==0&&!Modifier.isStatic(method.getModifiers())){cancelReader=method;break;}
        if(cancelReader==null)throw new NoSuchMethodException("No boolean() cancellation reader in "+cancelType.getName());
        if(cancelType.isInterface())evidence.put("cancelAdapter","runtime-interface-proxy");
        else {
            JSONArray attempts=new JSONArray();Constructor<?> constructor=cancelType.getDeclaredConstructor(int.class,Object.class);constructor.setAccessible(true);
            // R8 may specialize the backend for the production flag subtype
            // even when a synthetic constructor erases its capture to Object.
            // Verify the actual mapped subtype, never a plain AtomicBoolean.
            for(int classId=0;classId<8;classId++){
                AtomicBoolean probe=taskFlag(false);
                try {
                    Object instance=constructor.newInstance(classId,probe);
                    boolean initial=(Boolean)cancelReader.invoke(instance);probe.set(true);boolean signaled=(Boolean)cancelReader.invoke(instance);probe.set(false);boolean reset=(Boolean)cancelReader.invoke(instance);
                    if(!initial&&signaled&&!reset){cancelConstructor=constructor;cancelClassId=classId;break;}
                    attempts.put(new JSONObject().put("classId",classId).put("initial",initial).put("signaled",signaled).put("reset",reset));
                }catch(ReflectiveOperationException|RuntimeException failure){attempts.put(new JSONObject().put("classId",classId).put("error",unwrap(failure).toString()));}
                finally{probe.set(false);}
            }
            if(cancelConstructor==null)throw new ReflectiveOperationException("No bounded synthetic cancellation variant captured AtomicBoolean correctly: "+attempts);
            evidence.put("cancelAdapter","verified-production-task-flag-capture").put("cancelClassId",cancelClassId).put("cancelConstructor",cancelConstructor.toGenericString());
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
        return await(worker.submit(()->invoke(operation,frozen,taskFlag(false),value->{if(!Double.isFinite(value)||value<0||value>1)throw new AssertionError("Invalid native progress "+value);})));
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
    private AtomicBoolean taskFlag(boolean value)throws ReflectiveOperationException {
        AtomicBoolean flag=taskFlagConstructor==null?new AtomicBoolean():(AtomicBoolean)taskFlagConstructor.newInstance();
        flag.set(value);return flag;
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
        JSONObject bodySkin=call("media.retouchAnalyze",payload(source,changed.getString("localData")).put("mode","faceBody").put("tonePerFace",true));
        yes(bodySkin.getJSONObject("portrait").getJSONArray("faces").getJSONObject(0).getBoolean("hasBodySkinMask"),"release original body-skin model assigns a person-owned matte");
        JSONObject protectedOnly=call("media.retouchAnalyze",payload(source,bodySkin.getString("localData")).put("mode","body").put("locate",false).put("protection",100));
        JSONObject protectedPortrait=protectedOnly.getJSONObject("portrait"),priorPortrait=bodySkin.getJSONObject("portrait");
        yes(protectedOnly.getInt("selectedPerson")==-1&&protectedPortrait.getBoolean("hasBodyMask")&&protectedPortrait.getInt("protection")==100,"release background protection prepares its mask independently of person selection");
        yes(protectedPortrait.getJSONArray("body").toString().equals(priorPortrait.getJSONArray("body").toString()),"release background-only analysis preserves every existing shape area");
        yes(protectedPortrait.getJSONArray("faces").toString().equals(priorPortrait.getJSONArray("faces").toString())&&protectedPortrait.getInt("skinPixels")==priorPortrait.getInt("skinPixels"),"release background protection preserves face and global skin state");
        JSONObject custom=call("media.retouchChange",payload(source,bodySkin.getString("localData")).put("action","face").put("index",0).put("value",new JSONObject().put("toneRgb",0xbba080).put("toneAmount",.63).put("toneBody",true)));
        JSONObject tone=custom.getJSONObject("portrait").getJSONArray("faces").getJSONObject(0);
        yes(tone.getInt("toneId")==10&&tone.getInt("toneRgb")==0xbba080&&tone.getBoolean("toneBody"),"release custom tone retains RGB, strength and person body scope");
        JSONObject brush=call("media.retouchChange",payload(source,custom.getString("localData")).put("action","faceStroke").put("index",0).put("value",new JSONObject().put("points",new JSONArray().put(tone.getDouble("cx")).put(tone.getDouble("cy"))).put("radius",.01).put("erase",false)));
        yes(brush.getJSONObject("portrait").getJSONArray("faces").getJSONObject(0).getInt("strokeCount")==1,"release face selection stores an original immutable brush stroke");
        JSONObject selection=call("media.retouchAnalyze",payload(source,brush.getString("localData")).put("mode","overlay").put("index",0));
        JSONObject overlay=selection.getJSONObject("selectionOverlay");
        yes(Base64.getDecoder().decode(overlay.getString("rgba")).length==overlay.getInt("width")*overlay.getInt("height")*4&&overlay.getBoolean("premultiplied"),"release original selection overlay retains bounded premultiplied RGBA pixels");
        yes(selection.getString("localData").equals(brush.getString("localData")),"release overlay never changes tentative edits");
        JSONObject hit=call("media.retouchAnalyze",payload(source,brush.getString("localData")).put("mode","hitFace").put("x",tone.getDouble("cx")).put("y",tone.getDouble("cy")));
        yes(hit.getInt("hitFace")>=-1&&hit.getInt("hitFace")<found.length()&&hit.getString("localData").equals(brush.getString("localData")),"release tap selection uses original native face containment without changing edits");
        preview(source,brush.getString("localData"));
        JSONObject candidates=call("media.retouchAnalyze",payload(source,skin.getString("localData")).put("mode","autoBlemish"));
        yes(candidates.getJSONArray("healCandidates").length()<=24&&candidates.getString("localData").equals(skin.getString("localData")),"release automatic blemish candidates remain tentative and bounded");
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
        AtomicBoolean cancel=taskFlag(false),running=new AtomicBoolean();AtomicLong signaledAt=new AtomicLong();
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
    private Map<String,String> editState()throws Exception {
        Map<String,String> result=new TreeMap<>();
        for(String name:new String[]{"photo-edit-drafts","photo-versions","raw-development"})collectState(new File(root,name),result,0,root);
        File rawDevelopment=new File(root.getParentFile(),"raw-development").getCanonicalFile();
        collectState(rawDevelopment,result,0,rawDevelopment);
        return result;
    }
    private void collectState(File supplied,Map<String,String> result,int depth,File allowedRoot)throws Exception {
        if(depth>16)throw new IOException("Unexpectedly deep edit state");
        File file=supplied.getCanonicalFile();
        if(!file.equals(supplied)||!file.toPath().startsWith(allowedRoot.toPath())||Files.isSymbolicLink(file.toPath()))throw new IOException("Unconfined edit state path");
        if(!file.exists())return;
        if(file.isFile()){result.put(file.getPath(),hash(file));return;}
        File[] children=file.listFiles();if(children==null)throw new IOException("Cannot inspect edit state");
        for(File child:children)collectState(child,result,depth+1,allowedRoot);
    }
    private void detailChecks()throws Exception {
        File source=createSource("jpg");
        Bitmap bitmap=Bitmap.createBitmap(1600,1200,Bitmap.Config.ARGB_8888);
        try {
            int[] row=new int[1600];
            for(int y=0;y<1200;y++){
                for(int x=0;x<1600;x++)row[x]=0xff000000|((24+x%120)<<16)|((32+y%110)<<8)|(40+(x+y)%100);
                bitmap.setPixels(row,0,1600,0,y,1600,1);
            }
            try(FileOutputStream out=new FileOutputStream(source)){yes(bitmap.compress(Bitmap.CompressFormat.JPEG,95,out),"owned full-detail fixture encoded");out.getFD().sync();}
        }finally{bitmap.recycle();}
        String original=hash(source);
        JSONObject bounded=preview(source,"");
        yes(Math.max(bounded.getInt("width"),bounded.getInt("height"))<=640,"ordinary preview remains bounded before full-detail request");
        Map<String,String> state=editState();Set<String> previews=snapshot(new File(root,"previews"));
        JSONArray values=new JSONArray();for(int i=0;i<17;i++)values.put(i==1?10:0);
        JSONObject recipe=new JSONObject().put("schema",1).put("values",values);
        JSONObject payload=new JSONObject().put("owner",owner).put("path",source.getPath()).put("recipe",recipe).put("expectedSourceSha",original);
        JSONObject detail=call("media.detailRender",payload);File result=remember(detail,"previews");
        yes(detail.getBoolean("temporary")&&detail.getBoolean("fullResolution"),"full detail explicitly identifies a read-only temporary frame");
        yes(original.equals(detail.getString("sourceSha")),"full detail identifies the exact source SHA");
        yes(detail.getInt("width")==1600&&detail.getInt("height")==1200,"full detail preserves source-sized pixels beyond the preview cap");
        BitmapFactory.Options size=new BitmapFactory.Options();size.inJustDecodeBounds=true;BitmapFactory.decodeFile(result.getPath(),size);
        yes(size.outWidth==1600&&size.outHeight==1200,"encoded full-detail bitmap independently retains full dimensions");
        yes(!previews.contains(result.getPath()),"full detail owns a fresh temporary frame rather than a bounded cache entry");
        yes(pixelDifferences(source,result)>0,"full detail applies the requested exposure rather than copying the source");
        yes(state.equals(editState()),"full detail creates no draft, version or RAW development side effect");
        yes(original.equals(hash(source)),"full detail leaves source bytes unchanged");
        JSONObject mismatch=new JSONObject(payload.toString()).put("expectedSourceSha",String.join("",Collections.nCopies(64,"0")));
        Throwable wrongSha=null;try{call("media.detailRender",mismatch);}catch(Throwable failure){wrongSha=unwrap(failure);}
        yes(wrongSha instanceof IOException,"full detail rejects a changed-source SHA");
        JSONObject missing=new JSONObject(payload.toString());missing.remove("expectedSourceSha");
        Throwable noSha=null;try{call("media.detailRender",missing);}catch(Throwable failure){noSha=unwrap(failure);}
        yes(noSha instanceof IOException,"full detail requires an expected source SHA");
        Set<String> expectedPreviews=new HashSet<>(previews);expectedPreviews.add(result.getPath());
        yes(expectedPreviews.equals(snapshot(new File(root,"previews"))),"rejected full-detail identities leave no temporary frame");
        Set<String> beforeCancel=snapshot(new File(root,"previews"));
        Throwable failure=null;try{await(worker.submit(()->invoke("media.detailRender",payload.toString(),taskFlag(true),value->{})));}catch(Throwable value){failure=unwrap(value);}
        boolean canceled=false;for(Throwable value=failure;value!=null;value=value.getCause())if(value instanceof InterruptedIOException||String.valueOf(value.getMessage()).contains("取消")||String.valueOf(value.getMessage()).contains("停止"))canceled=true;
        yes(canceled,"full detail rejects an already-canceled native request");
        yes(beforeCancel.equals(snapshot(new File(root,"previews"))),"canceled full detail leaves no temporary frame");
        yes(state.equals(editState())&&original.equals(hash(source)),"rejected full-detail requests preserve source and persistent edit state");
        JSONObject tilePayload=new JSONObject().put("owner",owner).put("path",result.getPath()).put("detailToken",detail.getString("detailToken")).put("expectedSourceSha",original).put("maxEdge",512).put("region",new JSONObject().put("left",.25).put("top",.25).put("right",.5).put("bottom",.5));
        JSONObject tile=call("media.detailTile",tilePayload);File tileFile=remember(tile,"previews");
        yes(tile.getBoolean("temporary")&&tile.getString("detailToken").equals(detail.getString("detailToken"))&&tile.getString("sourceSha").equals(original),"tile owns a read-only frame bound to the issued full-detail source");
        yes(tile.getInt("width")==400&&tile.getInt("height")==300&&tile.getInt("sourceWidth")==1600&&tile.getInt("sourceHeight")==1200&&tile.getJSONObject("region").getDouble("left")==.25,"tile reports the exact upright pixel-rounded output ROI");
        double roiError=roiError(result,tileFile,400,300);
        yes(roiError<8,"real release tile pixels match the edited full-resolution ROI");
        yes(tile.getInt("decodedWidth")==400&&tile.getInt("decodedHeight")==300&&tile.getLong("decodedBytes")<=4L*1024*1024*4,"native ROI decoder allocates only the bounded 400x300 pixel tile");
        JSONObject overviewPayload=new JSONObject(tilePayload.toString()).put("maxEdge",128).put("region",new JSONObject().put("left",0).put("top",0).put("right",1).put("bottom",1));
        JSONObject overview=call("media.detailTile",overviewPayload);remember(overview,"previews");
        yes(overview.getInt("width")<=128&&overview.getInt("height")<=128&&overview.getInt("decodedWidth")<=128&&overview.getInt("decodedHeight")<=128,"zoomed-out ROI uses sampled region decoding rather than a full-size bitmap");
        for(JSONObject invalid:new JSONObject[]{new JSONObject(tilePayload.toString()).put("detailToken","unissued-capability"),new JSONObject(tilePayload.toString()).put("owner",owner+"different"),new JSONObject(tilePayload.toString()).put("path",source.getPath()),new JSONObject(tilePayload.toString()).put("expectedSourceSha",String.join("",Collections.nCopies(64,"0"))),new JSONObject(tilePayload.toString()).put("maxEdge",4096)}){
            Throwable rejected=null;try{call("media.detailTile",invalid);}catch(Throwable value){rejected=unwrap(value);}yes(rejected instanceof IOException,"tile rejects an unissued, cross-owner, rebound, changed-SHA or over-budget capability");
        }
        Set<String> tileBeforeCancel=snapshot(new File(root,"previews"));Throwable tileCancelled=null;
        try{await(worker.submit(()->invoke("media.detailTile",tilePayload.toString(),taskFlag(true),value->{})));}catch(Throwable value){tileCancelled=unwrap(value);}
        yes(tileCancelled instanceof IOException,"native tile honors an already-cancelled request");
        yes(tileBeforeCancel.equals(snapshot(new File(root,"previews"))),"cancelled or rejected tiles leave no temporary artifacts");
        byte[] originalFull=Files.readAllBytes(result.toPath());try{byte[] changed=originalFull.clone();changed[changed.length-1]^=1;Files.write(result.toPath(),changed);Throwable rejected=null;try{call("media.detailTile",tilePayload);}catch(Throwable value){rejected=unwrap(value);}yes(rejected instanceof IOException,"tile rejects changed full-plane bytes even at the issued private path");}finally{Files.write(result.toPath(),originalFull);}
        byte[] originalSource=Files.readAllBytes(source.toPath());try{byte[] changed=originalSource.clone();changed[changed.length-1]^=1;Files.write(source.toPath(),changed);Throwable rejected=null;try{call("media.detailTile",tilePayload);}catch(Throwable value){rejected=unwrap(value);}yes(rejected instanceof IOException,"tile rejects source bytes changed after full rendering");}finally{Files.write(source.toPath(),originalSource);}
        yes(state.equals(editState())&&original.equals(hash(source)),"all tile reads preserve original bytes and persistent editing transactions");
        JSONObject localRecipe=new JSONObject(recipe.toString()).put("geometry",new JSONObject().put("turns",1)).put("border",new JSONObject().put("template",3));
        JSONObject localDetail=call("media.detailRender",new JSONObject(payload.toString()).put("recipe",localRecipe).put("viewMode","local"));File localFile=remember(localDetail,"previews");
        yes(localDetail.getInt("width")==1600&&localDetail.getInt("height")==1200,"selection full detail uses the same geometry/border-neutral source plane as localPreview");
        yes(roiError(result,localFile,0,0)<8,"selection full detail retains the current adjustment profile on the exact source pixels");
        JSONObject rotated=call("media.detailRender",new JSONObject(payload.toString()).put("recipe",new JSONObject(recipe.toString()).put("geometry",new JSONObject().put("turns",1))));remember(rotated,"previews");
        yes(rotated.getInt("width")==1200&&rotated.getInt("height")==1600,"default full detail keeps the review composition rather than silently choosing local mode");
        Throwable badMode=null;try{call("media.detailRender",new JSONObject(payload.toString()).put("viewMode","unknown"));}catch(Throwable value){badMode=unwrap(value);}yes(badMode instanceof IOException,"unknown full-detail view modes are rejected");
        yes(state.equals(editState())&&original.equals(hash(source)),"local and review full-detail modes preserve all source and persistent edit transactions");
        evidence.put("detailTileWidth",tile.getInt("width")).put("detailTileHeight",tile.getInt("height")).put("detailTileDecodedBytes",tile.getLong("decodedBytes")).put("detailTileMeanChannelError",roiError).put("detailTileReadOnly",true);
        evidence.put("detailSourceSha256",original).put("detailWidth",size.outWidth).put("detailHeight",size.outHeight).put("detailPersistentStateUnchanged",true);
    }
    private void rawChecks()throws Exception {
        File source=createSource("dng");
        // TIFF readers follow referenced IFD/strip offsets. This unreferenced
        // trailer changes only this owned fixture's SHA and guarantees a cache miss.
        byte[] marker=("\nHuevia-R8-owned-fixture:"+UUID.randomUUID()+"\n").getBytes(StandardCharsets.UTF_8);
        copy(getContext().getAssets().open("raw-stack.dng"),source,marker);String original=hash(source);long bytes=source.length();
        JSONObject info=call("media.info",new JSONObject().put("path",source.getPath()));yes(info.getBoolean("raw"),"uniquely marked owned DNG remains a real RAW");
        Map<String,String> beforeDetail=editState();Set<String> detailPreviews=snapshot(new File(root,"previews"));
        Throwable rawDetail=null;try{call("media.detailRender",new JSONObject().put("path",source.getPath()).put("owner",owner).put("expectedSourceSha",original).put("recipe",new JSONObject().put("schema",1)));}catch(Throwable failure){rawDetail=unwrap(failure);}
        yes(rawDetail instanceof IOException&&String.valueOf(rawDetail.getMessage()).contains("显影"),"undeveloped RAW full detail requires explicit development");
        yes(beforeDetail.equals(editState())&&detailPreviews.equals(snapshot(new File(root,"previews"))),"rejected RAW detail creates no development, draft, version or preview");
        JSONObject thumbnail=call("media.rawThumbnail",new JSONObject().put("path",source.getPath()).put("owner",owner));
        File output=remember(thumbnail,"raw-thumbnails");
        yes(thumbnail.has("width")&&thumbnail.has("height"),"release RAW executed the fresh native/JNI branch rather than an old display cache");
        yes(original.equals(thumbnail.getString("sourceSha")),"RAW thumbnail identifies the exact uniquely owned source");
        BitmapFactory.Options bounds=new BitmapFactory.Options();bounds.inJustDecodeBounds=true;BitmapFactory.decodeFile(output.getPath(),bounds);
        yes(bounds.outWidth>0&&bounds.outHeight>0&&Math.max(bounds.outWidth,bounds.outHeight)<=512,"release RAW JNI produced a bounded <=512px encoded preview");
        Bitmap decoded=BitmapFactory.decodeFile(output.getPath());yes(decoded!=null,"release RAW JNI output is a decodable JPEG");if(decoded!=null)decoded.recycle();
        yes(source.length()==bytes&&original.equals(hash(source)),"RAW source length and SHA remain unchanged after actual JNI callbacks");
        Map<String,String> transactionBefore=editTransactions();
        JSONObject developPayload=new JSONObject().put("path",source.getPath()).put("owner",owner).put("expectedSourceSha",original).put("settings",new JSONObject().put("colorMode","NEUTRAL").put("exposure",0));
        JSONObject developed=call("media.rawDetail",developPayload);remember(developed,"previews");
        yes(developed.getBoolean("temporary")&&developed.getBoolean("fullResolution")&&developed.getInt("width")==info.getInt("width")&&developed.getInt("height")==info.getInt("height")&&developed.getJSONObject("settings").getInt("exposure")==0,"RAW detail returns the complete current staged developer pixels without rawPrepare");
        JSONObject rawTilePayload=new JSONObject().put("owner",owner).put("path",developed.getString("path")).put("detailToken",developed.getString("detailToken")).put("expectedSourceSha",original).put("maxEdge",512).put("region",new JSONObject().put("left",0).put("top",0).put("right",1).put("bottom",1));
        JSONObject neutralTile=call("media.detailTile",rawTilePayload);File neutralFile=remember(neutralTile,"previews");
        yes(neutralTile.getInt("decodedWidth")<=512&&neutralTile.getInt("decodedHeight")<=512&&neutralTile.getLong("decodedBytes")<=4L*1024*1024*4,"RAW full detail can be viewed through bounded native tiles");
        JSONObject darker=call("media.rawDetail",new JSONObject(developPayload.toString()).put("settings",new JSONObject().put("colorMode","NEUTRAL").put("exposure",-10)));remember(darker,"previews");
        JSONObject darkTile=call("media.detailTile",new JSONObject(rawTilePayload.toString()).put("path",darker.getString("path")).put("detailToken",darker.getString("detailToken")));File darkFile=remember(darkTile,"previews");
        yes(meanRed(darkFile)<meanRed(neutralFile)-8,"RAW detail tiles honor newly staged -1 EV rather than reusing stale cached pixels");
        yes(transactionBefore.equals(editTransactions()),"RAW detail writes only disposable previews and the reusable developer cache, with no draft/version/raw-editor/export transaction");
        yes(original.equals(hash(source)),"RAW detail leaves the owned original SHA unchanged");
        JSONArray editValues=new JSONArray();for(int i=0;i<17;i++)editValues.put(i==1?10:0);
        JSONObject editRecipe=new JSONObject().put("schema",1).put("values",editValues),edited=call("media.rawDetail",new JSONObject(developPayload.toString()).put("recipe",editRecipe).put("viewMode","review"));File editedFile=remember(edited,"previews");
        yes(meanRed(editedFile)>meanRed(neutralFile)+8,"direct RAW editor full detail applies the frozen +1 EV editing recipe after current development");
        yes(edited.getBoolean("temporary")&&edited.getBoolean("fullResolution")&&edited.getString("sourceSha").equals(original),"edited RAW detail retains the original NEF/DNG source identity and read-only ownership");
        JSONObject localRecipe=new JSONObject(editRecipe.toString()).put("geometry",new JSONObject().put("turns",1)).put("border",new JSONObject().put("template",3));
        JSONObject local=call("media.rawDetail",new JSONObject(developPayload.toString()).put("recipe",localRecipe).put("viewMode","local"));File localFile=remember(local,"previews");
        yes(local.getInt("width")==info.getInt("width")&&local.getInt("height")==info.getInt("height"),"direct RAW selection full detail strips composition exactly like localPreview");
        yes(roiError(editedFile,localFile,0,0)<8,"direct RAW local detail retains the same edited pixels while neutralizing geometry and border");
        JSONObject rotated=call("media.rawDetail",new JSONObject(developPayload.toString()).put("recipe",new JSONObject(editRecipe.toString()).put("geometry",new JSONObject().put("turns",1))));remember(rotated,"previews");
        yes(rotated.getInt("width")==info.getInt("height")&&rotated.getInt("height")==info.getInt("width"),"direct RAW review detail preserves the frozen rotated composition at full dimensions");
        Throwable invalidMode=null;try{call("media.rawDetail",new JSONObject(developPayload.toString()).put("recipe",editRecipe).put("viewMode","unknown"));}catch(Throwable value){invalidMode=unwrap(value);}yes(invalidMode instanceof IOException,"direct RAW detail rejects unknown composition modes");
        JSONObject editedTile=call("media.detailTile",new JSONObject(rawTilePayload.toString()).put("path",edited.getString("path")).put("detailToken",edited.getString("detailToken")));File editedTileFile=remember(editedTile,"previews");
        yes(editedTile.getString("sourceSha").equals(original)&&meanRed(editedTileFile)>meanRed(neutralFile)+8,"edited RAW ROI tiles retain the original RAW binding and current editing effect");
        yes(transactionBefore.equals(editTransactions())&&original.equals(hash(source)),"all direct RAW editing detail profiles preserve original bytes and persistent draft/version/raw-editor/export transactions");
        evidence.put("rawRecipeDetailVerified",true).put("rawRecipeLocalProfileVerified",true).put("rawRecipeSourceSha256",original);
        evidence.put("rawDetailWidth",developed.getInt("width")).put("rawDetailHeight",developed.getInt("height")).put("rawDetailReadOnly",true).put("rawDetailStagedExposureVerified",true);
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
    private double roiError(File fullFile,File tileFile,int left,int top)throws IOException{
        Bitmap full=BitmapFactory.decodeFile(fullFile.getPath()),tile=BitmapFactory.decodeFile(tileFile.getPath());
        try{if(full==null||tile==null)throw new IOException("Cannot decode ROI comparison");double error=0;int count=0;for(int y=12;y<tile.getHeight()-12;y+=19)for(int x=12;x<tile.getWidth()-12;x+=19){int a=full.getPixel(left+x,top+y),b=tile.getPixel(x,y);error+=Math.abs(((a>>16)&255)-((b>>16)&255))+Math.abs(((a>>8)&255)-((b>>8)&255))+Math.abs((a&255)-(b&255));count+=3;}return error/Math.max(1,count);}finally{if(full!=null)full.recycle();if(tile!=null)tile.recycle();}
    }
    private double meanRed(File file)throws IOException{Bitmap bitmap=BitmapFactory.decodeFile(file.getPath());try{if(bitmap==null)throw new IOException("Cannot decode RAW tile");double sum=0;int count=0;for(int y=0;y<bitmap.getHeight();y+=5)for(int x=0;x<bitmap.getWidth();x+=5){sum+=(bitmap.getPixel(x,y)>>16)&255;count++;}return sum/Math.max(1,count);}finally{if(bitmap!=null)bitmap.recycle();}}
    private Map<String,String> editTransactions()throws Exception{Map<String,String> state=new TreeMap<>();for(String name:new String[]{"photo-edit-drafts","photo-preset-history","photo-versions","raw-editor","exports"})collectState(new File(root,name),state,0,root);return state;}
    private void cleanup()throws IOException {
        List<File> files=new ArrayList<>(owned);Collections.reverse(files);IOException failure=null;
        for(File file:files){try{File canonical=file.getCanonicalFile();if(root==null||!canonical.equals(file)||!canonical.toPath().startsWith(root.toPath())||Files.isSymbolicLink(file.toPath()))throw new IOException("Refusing to clean a non-owned canonical path: "+file);Files.deleteIfExists(file.toPath());}catch(IOException value){if(failure==null)failure=value;else failure.addSuppressed(value);}}
        if(failure!=null)throw failure;
    }
}
