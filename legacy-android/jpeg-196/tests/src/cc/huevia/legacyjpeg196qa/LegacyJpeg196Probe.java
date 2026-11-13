package cc.huevia.legacyjpeg196qa;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.Intent;
import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import org.json.JSONArray;
import org.json.JSONObject;

/** Exercises installed production classes. No app classes or simulated indexes are bundled. */
public final class LegacyJpeg196Probe extends Instrumentation {
    private Bundle arguments;
    private Activity activity;
    private Object runtime,controller,panel,createdClient;
    private final JSONArray assertions=new JSONArray(),states=new JSONArray();
    private final List<String> completed=new ArrayList<>();
    private int timeoutSeconds;

    @Override public void onCreate(Bundle value){super.onCreate(value);arguments=value==null?new Bundle():value;start();}
    @Override public void onStart(){
        Bundle result=new Bundle();JSONObject report=new JSONObject();boolean passed=false;
        try{
            check("ranchu".equals(Build.HARDWARE)||"goldfish".equals(Build.HARDWARE),"owned-emulator-only");
            String expected=arguments.getString("apkSha256","");
            check(expected.matches("[0-9a-f]{64}")&&expected.equals(sha(new File(getTargetContext().getApplicationInfo().sourceDir))),"installed-apk-matches-explicit-hash");
            check("cc.huevia".equals(getTargetContext().getPackageName()),"target-is-original-app-not-export-entry");
            timeoutSeconds=Integer.parseInt(arguments.getString("timeoutSeconds","25"));
            check(timeoutSeconds>=5&&timeoutSeconds<=60,"bounded-case-timeout");
            activity=startActivitySync(new Intent().setClassName("cc.huevia","cc.huevia.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            await(()->onMain(()->Boolean.TRUE.equals(get(activity,"ready"))),30,"production-activity-ready");
            onMain(()->{runtime=get(activity,"connections");controller=get(runtime,"album");panel=get(activity,"album");return null;});
            ensureControlledInventory();
            // Drain completion notifications before deliberately losing this panel's listener.
            waitForIdleSync();Thread.sleep(150);waitForIdleSync();
            String selected=arguments.getString("case","all");
            if(selected.equals("all")||selected.equals("resume"))exerciseStaleEntry("resume");
            if(selected.equals("all")||selected.equals("entry"))exerciseStaleEntry("entry");
            if(selected.equals("all")||selected.equals("retry"))exerciseStaleEntry("retry");
            if(selected.equals("all")||selected.equals("guards"))exerciseGuards();
            if(selected.equals("all")||selected.equals("disconnect"))exerciseMissedDisconnect();
            check(!completed.isEmpty(),"at-least-one-requested-case-ran");
            report.put("completedCases",new JSONArray(completed));passed=true;
        }catch(Throwable failure){
            try{StringWriter value=new StringWriter();failure.printStackTrace(new PrintWriter(value));report.put("error",value.toString());}catch(Exception ignored){}
        }finally{
            try{
                if(controller!=null&&panel!=null)report.put("finalState",onMain(this::snapshot));
                if(activity!=null)report.put("activityClass",activity.getClass().getName());
                if(controller!=null)report.put("trace",callStatic(type("cc.huevia.album.ConnectionTrace"),"snapshot"));
                report.put("status",passed?"PASS":"FAIL").put("assertions",assertions).put("states",states)
                    .put("apkSha256",arguments.getString("apkSha256",""))
                    .put("scope","Installed original MainActivity/AlbumPanel/Controller on owned emulator; real read-only TCP peer15752, no physical camera or Wi-Fi-radio acceptance");
                File directory=new File(getTargetContext().getExternalFilesDir(null),"legacy-jpeg196-qa");
                if(!directory.isDirectory()&&!directory.mkdirs())throw new IllegalStateException("Cannot create owned QA output directory");
                File output=new File(directory,"result-"+System.currentTimeMillis()+".json");
                try(FileOutputStream stream=new FileOutputStream(output)){stream.write((report.toString(2)+"\n").getBytes(StandardCharsets.UTF_8));stream.getFD().sync();}
                result.putString("reportPath",output.getPath());result.putString("report",report.toString());result.putString("qaPass",Boolean.toString(passed));
            }catch(Throwable failure){passed=false;result.putString("qaPass","false");result.putString("reportError",failure.toString());}
            if(!"true".equals(arguments.getString("keepActivity","false"))){
                try{if(createdClient!=null&&controller!=null&&get(controller,"active")==createdClient)onMain(()->{call(controller,"disconnect");return null;});else if(createdClient!=null)call(createdClient,"close");}catch(Throwable ignored){}
                try{if(activity!=null)onMain(()->{activity.finish();return null;});}catch(Throwable ignored){}
            }
            finish(passed?Activity.RESULT_OK:Activity.RESULT_CANCELED,result);
        }
    }

    private void ensureControlledInventory()throws Exception{
        boolean live=(Boolean)call(controller,"hasLiveSession");
        if(live){
            Object active=get(controller,"active");
            check(((Number)call(active,"connectedPort")).intValue()==15752&&"10.0.2.2".equals(call(active,"connectedHost")),"existing-session-belongs-to-owned-peer15752");
        }else{
            Class<?> connector=type("cc.huevia.album.PtpIpClient$SocketConnector");
            Object transport=Proxy.newProxyInstance(connector.getClassLoader(),new Class<?>[]{connector},(proxy,method,args)->{
                if(method.getName().equals("connect")){
                    check("10.0.2.2".equals(args[0])&&((Integer)args[1])==15752,"only-controlled-peer-endpoint");
                    Socket socket=new Socket();socket.connect(new InetSocketAddress("10.0.2.2",15752),Math.min((Integer)args[2],15000));return socket;
                }
                return proxyDefault(proxy,method,args);
            });
            createdClient=type("cc.huevia.album.PtpIpClient").getConstructor(connector).newInstance(transport);
            call(createdClient,"connect",new Class<?>[]{String.class,int.class,byte[].class,String.class},"10.0.2.2",15752,new byte[16],"Legacy JPEG UI regression");
            onMain(()->{
                check(!(Boolean)call(controller,"hasLiveSession"),"no-replacement-of-another-camera-owner");
                Constructor<?> constructor=type("cc.huevia.album.ConnectionInfo").getDeclaredConstructor(String.class,String.class,int.class,int.class);constructor.setAccessible(true);
                set(controller,"active",createdClient);
                set(controller,"sessionConnectionInfo",constructor.newInstance("Z 6_2","10.0.2.2",15752,0));
                set(controller,"cachedConnectionInfo",null);
                return null;
            });
        }
        if(!(Boolean)call(controller,"isConnected")){
            Class<?> callback=type("cc.huevia.album.AlbumController$Callback");CountDownLatch finished=new CountDownLatch(1);AtomicReference<String> error=new AtomicReference<>();
            Object completion=Proxy.newProxyInstance(callback.getClassLoader(),new Class<?>[]{callback},(proxy,method,args)->{
                if(method.getName().equals("onSuccess")){finished.countDown();return null;}
                if(method.getName().equals("onError")){error.set(String.valueOf(args[0]));finished.countDown();return null;}
                return proxyDefault(proxy,method,args);
            });
            onMain(()->{call(controller,"retryBrowse",new Class<?>[]{callback},completion);return null;});
            check(finished.await(35,TimeUnit.SECONDS),"production-inventory-completes-before-timeout");
            check(error.get()==null,"production-inventory-read-succeeded");
        }
        check((Boolean)call(controller,"isConnected"),"shared-controller-index-ready");
        Object info=call(controller,"connectionInfo");int total=((Number)call(info,"totalHandles")).intValue();
        int expected=Integer.parseInt(arguments.getString("expectedHandles","303"));check(total==expected,"actual-inventory-count-"+expected);
    }

    private void exerciseStaleEntry(String entry)throws Exception{
        onMain(()->{
            // Another real panel takes the sole callback and closes, as a second Activity does.
            Object other=newPanel(false);Object itsListener=get(other,"connectionListener");
            check(get(controller,"connectionListener")==itsListener,"second-panel-takes-sole-listener-"+entry);
            call(other,"close");check(get(controller,"connectionListener")==null,"closed-second-panel-leaves-no-listener-"+entry);
            call(controller,"setPhotoLiveListener",new Class<?>[]{Runnable.class},get(panel,"photoLiveListener"));
            stale(panel);syncRootFlags();
            check((Boolean)call(controller,"isConnected")&&get(panel,"connection")==null&&!(Boolean)call(get(panel,"paging"),"hasMore"),"exact-stale-local-snapshot-with-ready-controller-"+entry);
            states.put(snapshot().put("phase","before-"+entry));
            if(entry.equals("resume")){callActivityOnPause(activity);callActivityOnResume(activity);}
            else if(entry.equals("entry")){
                set(activity,"albumTab",false);
                call(activity,"switchRoot",new Class<?>[]{int.class},1);
            }else{
                // Render the current panel directly to expose its real empty-state retry action.
                if(get(panel,"root")!=null)call(panel,"render");
                View button=findText((View)get(panel,"root"),"重试读取照片");
                if(button!=null&&button.isClickable())check(button.performClick(),"visible-production-retry-button-clicked");
                else{
                    Runnable retry=(Runnable)get(panel,"retrySharedCamera");
                    check(retry!=null,"production-retry-callback-present");retry.run();
                }
            }
            return null;
        });
        await(()->onMain(()->(Boolean)call(panel,"isConnected")&&get(panel,"connection")==call(controller,"connectionInfo")),timeoutSeconds,"STALE_PANEL_NOT_RECONCILED_"+entry);
        await(()->onMain(()->{
            Set<Long> handles=photoHandles();return handles.contains(302L)&&handles.contains(303L)&&!(Boolean)call(get(panel,"paging"),"isLoading");
        }),timeoutSeconds,"production-loadPage-reads-standard-and-generic-JPEG-"+entry);
        onMain(()->{
            List<?> photos=(List<?>)get(panel,"photos");check(photos.size()==2,"only-two-independent-JPEG-rows-"+entry);
            check(((Number)call(get(panel,"paging"),"cursor")).intValue()>0,"real-paging-cursor-advanced-"+entry);
            states.put(snapshot().put("phase","loaded-"+entry));return null;
        });
        assertRepeatedPresentationPreservesRows(entry);completed.add(entry);
    }
    private void assertRepeatedPresentationPreservesRows(String entry)throws Exception{
        List<?> before=onMain(()->new ArrayList<>((List<?>)get(panel,"photos")));Object snapshot=call(controller,"connectionInfo");
        int cursor=onMain(()->((Number)call(get(panel,"paging"),"cursor")).intValue());
        for(int i=0;i<3;i++){
            onMain(()->{call(activity,"render");callActivityOnPause(activity);callActivityOnResume(activity);return null;});
            waitForIdleSync();
        }
        Thread.sleep(400);waitForIdleSync();
        onMain(()->{
            List<?> after=(List<?>)get(panel,"photos");
            check(get(panel,"connection")==snapshot&&call(controller,"connectionInfo")==snapshot,"immutable-core-and-panel-snapshot-retained-"+entry);
            check(after.size()==before.size(),"repeat-presentation-does-not-append-duplicate-first-page-"+entry);
            for(int i=0;i<before.size();i++)check(after.get(i)==before.get(i),"repeat-presentation-does-not-clear-and-recreate-existing-row-"+entry+"-"+i);
            check(((Number)call(get(panel,"paging"),"cursor")).intValue()==cursor,"repeat-presentation-does-not-rewind-cursor-"+entry);
            return null;
        });
    }
    private void exerciseGuards()throws Exception{
        onMain(()->{
            Object current=get(panel,"connection");
            for(String flag:new String[]{"downloading","exporting","recoveringDownloads"}){
                Object previous=get(panel,flag);set(panel,"connection",null);set(panel,flag,true);
                try{check(Boolean.FALSE.equals(call(panel,"resumeCameraConnection")),"busy-resume-declines-"+flag);check(get(panel,"connection")==null,"busy-resume-does-not-replace-work-snapshot-"+flag);}
                finally{set(panel,flag,previous);set(panel,"connection",current);}
            }
            Object oldConnecting=get(panel,"connecting"),oldOwns=get(panel,"ownsConnectionRequest"),oldPending=get(panel,"pendingConnectionStart"),oldAddress=get(panel,"cameraAddress");
            Runnable pending=()->{throw new AssertionError("Owned connecting guard must not execute a replacement start");};
            set(panel,"connection",null);set(panel,"connecting",true);set(panel,"ownsConnectionRequest",true);
            set(panel,"pendingConnectionStart",pending);set(panel,"cameraAddress","192.0.2.196");
            try{
                check(Boolean.FALSE.equals(call(panel,"resumeCameraConnection")),"owned-connecting-resume-declines-old-ready-controller");
                check(get(panel,"connection")==null,"owned-connecting-does-not-adopt-old-snapshot");
                check(Boolean.TRUE.equals(get(panel,"connecting"))&&Boolean.TRUE.equals(get(panel,"ownsConnectionRequest"))&&get(panel,"pendingConnectionStart")==pending,"owned-connecting-intent-and-callback-remain-owned");
                check("192.0.2.196".equals(get(panel,"cameraAddress")),"owned-connecting-does-not-overwrite-new-address-with-old-camera");
            }finally{
                set(panel,"connection",current);set(panel,"connecting",oldConnecting);set(panel,"ownsConnectionRequest",oldOwns);
                set(panel,"pendingConnectionStart",oldPending);set(panel,"cameraAddress",oldAddress);
            }
            Object local=newPanel(true);Object listener=get(controller,"connectionListener");
            try{check(Boolean.FALSE.equals(call(local,"resumeCameraConnection")),"local-workspace-does-not-adopt-camera");check(get(local,"connection")==null&&get(controller,"connectionListener")==listener,"local-workspace-does-not-steal-sync-listener");}
            finally{call(local,"close");}
            Object closed=newPanel(false);call(closed,"close");Object afterClose=get(controller,"connectionListener");
            check(Boolean.FALSE.equals(call(closed,"resumeCameraConnection")),"closed-panel-cannot-resume");check(get(controller,"connectionListener")==afterClose,"closed-panel-does-not-rebind-listener");
            call(panel,"resumeCameraConnection");call(controller,"setPhotoLiveListener",new Class<?>[]{Runnable.class},get(panel,"photoLiveListener"));
            check(get(controller,"connectionListener")==get(panel,"connectionListener"),"foreground-panel-listener-restored-after-guard-fixtures");
            states.put(snapshot().put("phase","guards-complete"));return null;
        });
        completed.add("closed-local-workspace-busy-guards");
    }
    private void exerciseMissedDisconnect()throws Exception{
        onMain(()->{syncRootFlags();call(activity,"render");return null;});
        await(()->onMain(()->Boolean.TRUE.equals(call(controller,"isConnected"))&&photoHandles().contains(302L)&&photoHandles().contains(303L)),timeoutSeconds,"ready-photos-before-missed-disconnect");
        onMain(()->{
            check(!(Boolean)call(panel,"isTransferBusy"),"disconnect-fixture-has-no-foreign-photo-work");
            Object previousSnapshot=get(panel,"connection");check(previousSnapshot!=null,"disconnect-fixture-starts-with-a-real-local-snapshot");
            Object other=newPanel(false);call(other,"close");
            check(get(controller,"connectionListener")==null,"disconnect-notification-will-miss-foreground-panel");
            // These are controlled UI flags only: no original transfer or recovery job is started.
            set(panel,"downloading",true);set(panel,"recoveringDownloads",true);
            call(controller,"disconnect");
            check(!(Boolean)call(controller,"isConnected")&&!(Boolean)call(controller,"hasLiveSession"),"real-production-controller-session-was-closed");
            check(get(panel,"connection")==previousSnapshot&&((List<?>)get(panel,"photos")).size()==2,"old-ui-retains-stale-snapshot-until-host-resume");
            states.put(snapshot().put("phase","before-missed-disconnect-resume"));
            callActivityOnPause(activity);callActivityOnResume(activity);return null;
        });
        await(()->onMain(()->get(panel,"connection")==null&&!Boolean.TRUE.equals(get(panel,"downloading"))&&!Boolean.TRUE.equals(get(panel,"recoveringDownloads"))&&((List<?>)get(panel,"photos")).isEmpty()),timeoutSeconds,"host-resume-clears-missed-disconnect-snapshot-busy-flags-and-photos");
        onMain(()->{
            check(!(Boolean)call(panel,"isConnected"),"disconnected-panel-is-not-advertised-ready");
            check(!Boolean.TRUE.equals(call(get(panel,"paging"),"hasMore"))&&((Number)call(get(panel,"paging"),"cursor")).intValue()==0,"disconnected-camera-paging-is-retired");
            check(((List<?>)get(panel,"photos")).isEmpty(),"disconnected-camera-does-not-display-invalid-remote-rows");
            states.put(snapshot().put("phase","missed-disconnect-cleared"));return null;
        });
        completed.add("missed-disconnect-cleanup");
    }
    private Object newPanel(boolean local)throws Exception{
        Class<?> host=type("cc.huevia.ui.AlbumPanel$Host");Object inert=Proxy.newProxyInstance(host.getClassLoader(),new Class<?>[]{host},LegacyJpeg196Probe::proxyDefault);
        if(!local)return type("cc.huevia.ui.AlbumPanel").getConstructor(Activity.class,host,type("cc.huevia.album.AlbumController")).newInstance(activity,inert,controller);
        return type("cc.huevia.ui.AlbumPanel").getConstructor(Activity.class,host,type("cc.huevia.album.AlbumController"),type("cc.huevia.album.PhotoPresetBatch"),type("cc.huevia.album.PhotoProjectPresets"),boolean.class).newInstance(activity,inert,controller,null,null,true);
    }
    private void stale(Object target)throws Exception{
        check(!(Boolean)call(target,"isTransferBusy"),"stale-fixture-never-overwrites-real-photo-work");
        set(target,"connection",null);set(target,"connecting",false);set(target,"ownsConnectionRequest",false);
        set(target,"downloadedTab",false);set(target,"liveTab",false);set(target,"selectionMode",false);
        Class<?> screen=type("cc.huevia.ui.AlbumPanel$Screen");Object overview=null;for(Object value:screen.getEnumConstants())if(((Enum<?>)value).name().equals("OVERVIEW"))overview=value;
        set(target,"screen",overview);((List<?>)get(target,"photos")).clear();call(get(target,"paging"),"reset",new Class<?>[]{boolean.class},false);
    }
    private void syncRootFlags()throws Exception{
        check(!Boolean.TRUE.equals(get(activity,"busy")),"root-has-no-foreign-operation");
        set(activity,"albumTab",true);set(activity,"settingsTab",false);set(activity,"localAlbumTab",false);set(activity,"wirelessGuide",false);
        set(activity,"confirmation",null);set(activity,"importOutcome",null);set(activity,"detailId","");set(activity,"detailOnline",null);
    }
    private Set<Long> photoHandles()throws Exception{Set<Long> handles=new HashSet<>();for(Object photo:(List<?>)get(panel,"photos"))handles.add(((Number)call(photo,"handle")).longValue());return handles;}
    private JSONObject snapshot()throws Exception{
        Object paging=get(panel,"paging"),info=call(controller,"connectionInfo");
        return new JSONObject().put("coreReady",call(controller,"isConnected")).put("coreHandles",info==null?-1:call(info,"totalHandles"))
            .put("panelReady",call(panel,"isConnected")).put("panelSnapshotPresent",get(panel,"connection")!=null)
            .put("panelConnecting",get(panel,"connecting")).put("listenerAttached",get(controller,"connectionListener")==get(panel,"connectionListener"))
            .put("photoCount",((List<?>)get(panel,"photos")).size()).put("pagingCursor",call(paging,"cursor"))
            .put("pagingHasMore",call(paging,"hasMore")).put("pagingLoading",call(paging,"isLoading"));
    }
    private void await(Work<Boolean> condition,int seconds,String name)throws Exception{
        long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(seconds);
        while(System.nanoTime()<deadline){if(Boolean.TRUE.equals(condition.get())){check(true,name);return;}Thread.sleep(40);}
        check(false,name);
    }
    private synchronized void check(boolean value,String name){if(!value)throw new AssertionError(name);assertions.put(name);}
    private interface Work<T>{T get()throws Exception;}
    private <T>T onMain(Work<T> work)throws Exception{
        AtomicReference<T> result=new AtomicReference<>();AtomicReference<Throwable> failure=new AtomicReference<>();
        runOnMainSync(()->{try{result.set(work.get());}catch(Throwable error){failure.set(error);}});
        if(failure.get()!=null)throw new Exception(failure.get());return result.get();
    }
    private Class<?> type(String name)throws Exception{return getTargetContext().getClassLoader().loadClass(name);}
    private static Object get(Object target,String name)throws Exception{Field field=findField(target.getClass(),name);return field.get(target);}
    private static void set(Object target,String name,Object value)throws Exception{findField(target.getClass(),name).set(target,value);}
    private static Field findField(Class<?> type,String name)throws Exception{for(Class<?> current=type;current!=null;current=current.getSuperclass())try{Field field=current.getDeclaredField(name);field.setAccessible(true);return field;}catch(NoSuchFieldException ignored){}throw new NoSuchFieldException(name);}
    private static Object call(Object target,String name)throws Exception{return call(target,name,new Class<?>[0]);}
    private static Object call(Object target,String name,Class<?>[] types,Object... values)throws Exception{Method method=target.getClass().getDeclaredMethod(name,types);method.setAccessible(true);return method.invoke(target,values);}
    private static Object callStatic(Class<?> target,String name)throws Exception{Method method=target.getDeclaredMethod(name);method.setAccessible(true);return method.invoke(null);}
    private static Object proxyDefault(Object proxy,Method method,Object[] values){
        if(method.getName().equals("toString"))return "Owned legacy UI regression callback";
        if(method.getName().equals("hashCode"))return System.identityHashCode(proxy);
        if(method.getName().equals("equals"))return values!=null&&values.length==1&&proxy==values[0];
        Class<?> type=method.getReturnType();if(type==boolean.class)return false;if(type==int.class)return 0;if(type==long.class)return 0L;if(type==float.class)return 0f;if(type==double.class)return 0d;return null;
    }
    private static View findText(View root,String text){if(root==null)return null;if(root instanceof TextView&&text.contentEquals(((TextView)root).getText()))return root;if(root instanceof ViewGroup){ViewGroup group=(ViewGroup)root;for(int i=0;i<group.getChildCount();i++){View result=findText(group.getChildAt(i),text);if(result!=null)return result;}}return null;}
    private static String sha(File file)throws Exception{MessageDigest digest=MessageDigest.getInstance("SHA-256");try(InputStream stream=new FileInputStream(file)){byte[] data=new byte[65536];int count;while((count=stream.read(data))!=-1)digest.update(data,0,count);}StringBuilder value=new StringBuilder();for(byte b:digest.digest())value.append(String.format(java.util.Locale.ROOT,"%02x",b&255));return value.toString();}
}
