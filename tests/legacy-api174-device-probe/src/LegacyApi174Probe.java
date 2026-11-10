package cc.huevia.legacyapi174qa;

import android.app.*;
import android.content.*;
import android.graphics.Bitmap;
import android.os.*;
import android.view.*;
import android.widget.*;
import java.io.*;
import java.lang.reflect.*;
import java.net.URL;
import java.security.cert.Certificate;
import java.util.*;
import javax.net.ssl.HttpsURLConnection;
import org.json.*;

/** Actual platform boot classes and installed app, with a metadata-only HTTPS fixture. */
public final class LegacyApi174Probe extends Instrumentation {
    private Bundle args;private Activity activity;private File output,scratch;
    private final JSONObject report=new JSONObject();private final JSONArray checks=new JSONArray();private final List<String> urls=new ArrayList<>();
    @Override public void onCreate(Bundle b){args=b;start();}
    @Override public void onStart(){Throwable failure=null;try{
        check("ranchu".equals(Build.HARDWARE)||"goldfish".equals(Build.HARDWARE),"owned-emulator");
        String run=args.getString("runId");check(run!=null&&run.matches("[A-Za-z0-9.-]{8,100}"),"safe-run-id");
        output=new File(getTargetContext().getExternalFilesDir(null),"legacy-api174/"+run);check(output.mkdirs(),"new-evidence-directory");
        long version=getTargetContext().getPackageManager().getPackageInfo("cc.huevia",0).getLongVersionCode();check(version==172||version==174,"baseline-or-final-version");
        report.put("versionCode",version);report.put("sdk",Build.VERSION.SDK_INT);boolean missing=version==172&&Build.VERSION.SDK_INT<33;
        scratch=new File(getTargetContext().getFilesDir(),"legacy-api174-"+run);check(scratch.mkdirs(),"owned-scratch-directory");
        Object repository=repository();Object page=null;Throwable pageError=null;
        try{page=repository.getClass().getMethod("fetchPage",int.class,int.class,String.class,String.class).invoke(repository,1,20,"风景","");}catch(InvocationTargetException e){pageError=e.getCause();}
        report.put("pageError",pageError==null?JSONObject.NULL:android.util.Log.getStackTraceString(pageError));
        if(missing){check(pageError instanceof NoSuchMethodError,"baseline-real-platform-missing-encoder");check(urls.isEmpty(),"baseline-fails-before-network");}
        else{check(pageError==null,"page-request-supported-by-platform");check(((List<?>)page.getClass().getField("presets").get(page)).size()==1,"validated-page-result");check(urls.size()==1&&urls.get(0).contains("category=%E9%A3%8E%E6%99%AF"),"UTF8-category-query");}
        Class<?> community=Class.forName("cc.huevia.community.CommunityRepository");Throwable communityError=null;String encoded=null;
        try{encoded=(String)community.getMethod("encode",String.class).invoke(null,"蔚蓝天空 +&/😀");}catch(InvocationTargetException e){communityError=e.getCause();}
        report.put("communityError",communityError==null?JSONObject.NULL:android.util.Log.getStackTraceString(communityError));
        if(missing)check(communityError instanceof NoSuchMethodError,"baseline-community-missing-encoder");
        else{check(communityError==null,"community-encoder-supported-by-platform");check("%E8%94%9A%E8%93%9D%E5%A4%A9%E7%A9%BA+%2B%26%2F%F0%9F%98%80".equals(encoded),"Chinese-space-plus-ampersand-slash-emoji-encoding");check("".equals(community.getMethod("encode",String.class).invoke(null,new Object[]{null})),"null-community-name-remains-empty");}
        if(!missing){
            activity=startActivitySync(new Intent(Intent.ACTION_MAIN).setClassName("cc.huevia","cc.huevia.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TASK));
            until(()->Boolean.TRUE.equals(get(activity,"ready")),"main-ready");
            ui(()->{set(activity,"settingsTab",false);set(activity,"albumTab",false);set(activity,"localAlbumTab",false);set(activity,"localTab",true);set(activity,"online",repository);set(activity,"catalogEpoch",((Integer)get(activity,"catalogEpoch"))+1);set(activity,"loadingCatalog",false);set(activity,"catalogLoaded",false);set(activity,"homePresetQuery","");call(activity,"render");});
            for(int i=0;i<8;i++){final boolean local=i%2!=0;ui(()->call(activity,"selectPresetSource",local));SystemClock.sleep(70);check(Boolean.valueOf(local).equals(get(activity,"localTab")),"actual-top-source-switch-"+i);}
            ui(()->call(activity,"selectPresetSource",false));until(()->Boolean.TRUE.equals(get(activity,"catalogLoaded"))&&!Boolean.TRUE.equals(get(activity,"loadingCatalog")),"actual-online-page-loads");
            check(!activity.isFinishing(),"actual-online-page-remains-alive");capture("online-api-supported");
        }
        report.put("scope","Actual installed app encoding on actual Android boot runtime. Baseline172 belowAPI33 must raise NoSuchMethodError in page and community encoding. Fixed174 checks UTF8 wire query, parsed page, community names and actual MainActivity source switches. HTTPS transport is mocked; no writes or preview certification. An Android API31 emulator is not a physical HarmonyOS device.");
    }catch(Throwable t){failure=t;try{report.put("failure",android.util.Log.getStackTraceString(t));}catch(Exception ignored){}}
    finally{try{if(activity!=null)ui(()->activity.finish());removeOwned(scratch);}catch(Throwable t){try{report.put("cleanupError",t.toString());}catch(Exception ignored){}}
        try{report.put("pass",failure==null);report.put("checks",checks);report.put("candidateSha256",args.getString("candidateSha256"));if(output!=null)try(Writer w=new OutputStreamWriter(new FileOutputStream(new File(output,"report.json")),"UTF-8")){w.write(report.toString(2));}}catch(Exception ignored){}
        Bundle result=new Bundle();result.putString("result",report.toString());finish(failure==null?-1:0,result);}
    }
    private Object repository()throws Exception{
        JSONObject item=new JSONObject().put("id","b798456f-e181-4944-95c0-f91a6cd0763c").put("name","蔚蓝天空").put("fileUrl","https://example.invalid/qa174.ncp").put("sha256",String.join("",Collections.nCopies(64,"0"))).put("byteLength",52).put("fileFormat","NCP").put("category","风景");
        byte[] bytes=new JSONObject().put("items",new JSONArray().put(item)).put("page",1).put("pageSize",20).put("total",1).put("hasMore",false).put("fileFormat","").put("categories",new JSONArray().put("风景")).toString().getBytes("UTF-8");
        Class<?> connections=Class.forName("cc.huevia.library.SecureHttpClient$Connections");Object connector=Proxy.newProxyInstance(connections.getClassLoader(),new Class<?>[]{connections},(p,m,v)->{URL u=(URL)v[0];urls.add(u.toString());return new Connection(u,bytes);});
        Class<?> httpClass=Class.forName("cc.huevia.library.SecureHttpClient");Constructor<?> hc=httpClass.getDeclaredConstructor(connections);hc.setAccessible(true);Object http=hc.newInstance(connector);
        Class<?> library=Class.forName("cc.huevia.library.PresetLibrary");Object local=library.getConstructor(File.class).newInstance(scratch);
        Class<?> repo=Class.forName("cc.huevia.library.OnlinePresetRepository");Constructor<?> rc=repo.getDeclaredConstructor(File.class,library,httpClass);rc.setAccessible(true);Object result=rc.newInstance(scratch,local,http);
        repo.getMethod("useManagedEndpoint",String.class).invoke(result,repo.getField("MANAGED_CATALOG_URL").get(null));return result;
    }
    private static final class Connection extends HttpsURLConnection{
        final byte[] bytes;Connection(URL u,byte[] b){super(u);bytes=b;}public int getResponseCode(){return 200;}public long getContentLengthLong(){return bytes.length;}public InputStream getInputStream(){return new ByteArrayInputStream(bytes);}public void disconnect(){}public boolean usingProxy(){return false;}public void connect(){}public String getCipherSuite(){return "TEST";}public Certificate[] getLocalCertificates(){return new Certificate[0];}public Certificate[] getServerCertificates(){return new Certificate[0];}}
    private void removeOwned(File f)throws Exception{if(f==null||!f.exists())return;String expected=getTargetContext().getFilesDir().getCanonicalPath()+File.separator+"legacy-api174-";if(!f.getCanonicalPath().startsWith(expected))throw new IOException("Unexpected cleanup path");remove(f);}
    private void remove(File f)throws IOException{if(f.isDirectory()){File[] list=f.listFiles();if(list==null)throw new IOException("Cannot list fixture");for(File c:list)remove(c);}if(!f.delete())throw new IOException("Cannot remove fixture");}
    private void capture(String name)throws Exception{waitForIdleSync();Bitmap b=getUiAutomation().takeScreenshot();try(OutputStream out=new FileOutputStream(new File(output,name+".png"))){b.compress(Bitmap.CompressFormat.PNG,100,out);}b.recycle();}
    private void check(boolean b,String name)throws Exception{checks.put(new JSONObject().put("name",name).put("pass",b));if(!b)throw new AssertionError(name);}
    private interface Work{void run()throws Exception;}private interface Condition{boolean test()throws Exception;}
    private void ui(Work w)throws Exception{Throwable[] t={null};runOnMainSync(()->{try{w.run();}catch(Throwable e){t[0]=e;}});if(t[0]!=null)throw new RuntimeException(t[0]);}
    private void until(Condition c,String name)throws Exception{long end=SystemClock.uptimeMillis()+30000;while(SystemClock.uptimeMillis()<end){if(c.test())return;SystemClock.sleep(40);}throw new AssertionError("Timeout "+name);}
    private static Object get(Object o,String n)throws Exception{Field f=o.getClass().getDeclaredField(n);f.setAccessible(true);return f.get(o);}private static void set(Object o,String n,Object v)throws Exception{Field f=o.getClass().getDeclaredField(n);f.setAccessible(true);f.set(o,v);}private static Object call(Object o,String n,Object...v)throws Exception{for(Method m:o.getClass().getDeclaredMethods())if(m.getName().equals(n)&&m.getParameterCount()==v.length){m.setAccessible(true);return m.invoke(o,v);}throw new NoSuchMethodException(n);}
}
