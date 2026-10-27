package cc.huevia.onlineformatqa;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ActivityInfo;
import android.content.res.Configuration;
import android.graphics.Bitmap;
import android.graphics.Rect;
import android.os.Build;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.accessibility.AccessibilityNodeInfo;
import android.widget.GridView;
import android.widget.TextView;
import org.json.JSONArray;
import org.json.JSONObject;
import javax.net.ssl.HttpsURLConnection;
import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.net.URL;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.security.Principal;
import java.security.cert.Certificate;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.stream.Collectors;

/** Real MainActivity/HTTP parser/UI, with explicitly synthetic in-memory HTTPS responses. */
public final class OnlineFormatProbe extends Instrumentation {
    private static final String TARGET="cc.huevia", FILTER="online-preset-format-filter";
    private Bundle args;
    private Activity activity;
    private ClassLoader loader;
    private File output, fixtureRoot;
    private String stage="start", mode, priorAppearance;
    private boolean appearanceCaptured, menuCaptured;
    private int diagnosticKnownFailures;
    private final JSONArray checks=new JSONArray(), screenshots=new JSONArray();
    private final JSONObject report=new JSONObject();
    private final List<Map<String,Object>> rows=new ArrayList<>();
    private final Map<String,byte[]> recipes=new HashMap<>();
    private final List<String> requests=new CopyOnWriteArrayList<>();
    private volatile boolean failPages;
    private volatile Gate gate;
    private Object fixtureRepository;

    @Override public void onCreate(Bundle values){super.onCreate(values);args=values==null?new Bundle():values;start();}
    @Override public void onStart(){
        Bundle result=new Bundle();
        try {
            check(Build.HARDWARE.equals("ranchu")||Build.HARDWARE.equals("goldfish"),"emulator-only");
            var installed=getTargetContext().getPackageManager().getPackageInfo(TARGET,0);
            check(installed.getLongVersionCode()==Integer.parseInt(args.getString("version","102")),"installed-version-code");
            check(installed.versionName.equals(args.getString("versionName","0.21.3-beta")),"installed-version-name");
            check(sha(new File(getTargetContext().getApplicationInfo().sourceDir)).equals(args.getString("candidateSha256")),"installed-frozen-apk-sha256");
            mode=args.getString("mode","phone");loader=getTargetContext().getClassLoader();
            output=new File(getTargetContext().getExternalFilesDir(null),"online-format-qa/"+args.getString("runId"));
            if(!output.mkdirs())throw new IOException("Fresh evidence directory required");
            fixtureRoot=new File(getTargetContext().getCacheDir(),"online-format-qa/"+args.getString("runId"));
            if(!fixtureRoot.mkdirs())throw new IOException("Fresh fixture directory required");
            SharedPreferences prefs=getTargetContext().getSharedPreferences("app-appearance",Context.MODE_PRIVATE);
            priorAppearance=prefs.getString("mode",null);appearanceCaptured=true;
            prefs.edit().putString("mode",mode.equals("dark")?"dark":"light").commit();
            createRows();
            activity=startActivitySync(new Intent(Intent.ACTION_MAIN).setComponent(new ComponentName(TARGET,TARGET+".MainActivity")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TASK));
            until(()->Boolean.TRUE.equals(get(activity,"ready"))&&!Boolean.TRUE.equals(get(activity,"loadingCatalog")),"initial-offline-startup-settled",25000);
            int requestedOrientation=mode.equals("landscape")?Configuration.ORIENTATION_LANDSCAPE:Configuration.ORIENTATION_PORTRAIT;
            ui(()->activity.setRequestedOrientation(mode.equals("landscape")?ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE:ActivityInfo.SCREEN_ORIENTATION_PORTRAIT));
            until(()->activity.getResources().getConfiguration().orientation==requestedOrientation,"native-initial-orientation-matches-mode",10000);
            check(Boolean.TRUE.equals(get(get(activity,"colors"),"dark"))==mode.equals("dark"),"native-app-theme-matches-mode");
            Configuration configuration=activity.getResources().getConfiguration();
            check(Math.abs(configuration.fontScale-(mode.equals("large-font")?1.3f:1f))<.03f,"native-font-scale-matches-mode");
            report.put("initialScreenWidthDp",configuration.screenWidthDp).put("initialScreenHeightDp",configuration.screenHeightDp).put("fontScale",configuration.fontScale);
            stage="inject-in-memory-http";injectRepository();
            ui(()->{
                set(activity,"catalogEpoch",((Number)get(activity,"catalogEpoch")).intValue()+1);
                set(activity,"online",fixtureRepository);set(activity,"localTab",false);
                set(activity,"albumTab",false);set(activity,"localAlbumTab",false);set(activity,"settingsTab",false);
                set(activity,"detailId","");set(activity,"detailOnline",null);set(activity,"message","");
                set(activity,"onlineFormatFilter","");set(activity,"onlineCategoryFilter","全部");
                set(activity,"catalogLoaded",false);set(activity,"loadingCatalog",false);
                set(activity,"catalog",new ArrayList<>());set(activity,"catalogPage",0);set(activity,"catalogHasMore",false);
                invoke(activity,"loadCatalogPage",new Class<?>[]{boolean.class},false);
            });
            awaitCatalog("","全部",20,1,72);
            geometry("all");capture("all-formats");
            stage="format-and-pagination";chooseFormat("NP3");awaitCatalog("NP3","全部",20,1,24);
            assertVisibleFormat("NP3");geometry("np3");
            ui(()->((GridView)get(activity,"list")).smoothScrollToPosition(19));
            until(()->!Boolean.TRUE.equals(get(activity,"loadingCatalog"))&&((Number)get(activity,"catalogPage")).intValue()==2,"native-scroll-fetches-second-format-page",15000);
            check(((List<?>)get(activity,"catalog")).size()==24,"two-format-pages-have-24-items");
            Set<String> ids=new HashSet<>();for(Object row:(List<?>)get(activity,"catalog"))check(ids.add(String.valueOf(get(row,"id"))),"paged-unique-id-"+get(row,"id"));
            assertVisibleFormat("NP3");check(!Boolean.TRUE.equals(get(activity,"catalogHasMore")),"last-format-page-stops-pagination");
            chooseCategory("人像");awaitCatalog("NP3","人像",12,1,12);assertVisibleFormat("NP3");capture("np3-portrait");
            chooseFormat("NCP");awaitCatalog("NCP","人像",20,1,20);assertVisibleFormat("NCP");
            check(requests.stream().anyMatch(x->x.contains("fileFormat=NCP")&&x.contains("category=%E4%BA%BA%E5%83%8F"))||requests.stream().anyMatch(x->x.contains("format=NCP")&&x.contains("category=%E4%BA%BA%E5%83%8F")),"request-combines-category-and-format");
            chooseCategory("黑白");awaitCatalog("NCP","黑白",8,1,8);
            stage="no-match-empty-state";chooseFormat("NP3");awaitCatalog("NP3","黑白",0,1,0);
            until(()->findText(root(),"没有符合条件的预设")!=null,"filter-empty-copy-visible",5000);
            check(findText(root(),"清除筛选")!=null,"filter-empty-reset-action-visible");geometry("empty");capture("np3-no-match");
            tap(textView("清除筛选"));awaitCatalog("","全部",20,1,72);
            check(findTag(root(),FILTER)!=null,"clear-restores-online-format-control");
            staleResponse();
            categoryRace();
            stateAndConfiguration();
            cachedCombination();
            report.put("pass",diagnosticKnownFailures==0);
            if(diagnosticKnownFailures>0)report.put("failure","Known format touch-height defect retained as FAIL; other diagnostic stages completed").put("diagnosticKnownFailures",diagnosticKnownFailures);
        } catch(Throwable failure) {
            while(failure instanceof InvocationTargetException&&failure.getCause()!=null)failure=failure.getCause();
            StringWriter trace=new StringWriter();failure.printStackTrace(new PrintWriter(trace));
            try{report.put("pass",false).put("failure",trace.toString());if(activity!=null)report.put("catalogState",new JSONObject(map("format",get(activity,"onlineFormatFilter"),"category",get(activity,"onlineCategoryFilter"),"loading",get(activity,"loadingCatalog"),"loaded",get(activity,"catalogLoaded"),"page",get(activity,"catalogPage"),"total",get(activity,"catalogTotal"),"count",((List<?>)get(activity,"catalog")).size(),"message",get(activity,"catalogMessage"))));if(output!=null&&activity!=null)capture("failure");}catch(Exception ignored){}
        } finally {
            if(gate!=null)gate.release.countDown();
            try{if(activity!=null)ui(()->activity.finish());}catch(Exception ignored){}
            if(appearanceCaptured){var edit=getTargetContext().getSharedPreferences("app-appearance",Context.MODE_PRIVATE).edit();if(priorAppearance==null)edit.remove("mode");else edit.putString("mode",priorAppearance);edit.commit();}
            try{if(fixtureRoot!=null&&fixtureRoot.exists()){
                String allowed=new File(getTargetContext().getCacheDir(),"online-format-qa").getCanonicalPath()+File.separator;
                check(fixtureRoot.getCanonicalPath().startsWith(allowed),"fixture-cleanup-scope");
                try(var paths=Files.walk(fixtureRoot.toPath())){for(var path:paths.sorted(Comparator.reverseOrder()).collect(Collectors.toList()))Files.delete(path);}
            }}catch(Exception failure){try{report.put("cleanupFailure",failure.toString()).put("pass",false);}catch(Exception ignored){}}
            try{report.put("stage",stage).put("mode",mode).put("checks",checks).put("screenshots",screenshots).put("requests",new JSONArray(requests));
                report.put("scope","Real installed MainActivity, native taps/Views/configuration and incumbent repository/HTTPS JSON parser. Explicit in-memory public-recipe and synthetic catalogue fixtures; no live server request, account mutation, physical camera, update-policy change or physical performance claim.");
                if(output!=null)Files.writeString(new File(output,"report.json").toPath(),report.toString(2));
            }catch(Exception failure){result.putString("reportFailure",failure.toString());}
            result.putString("stream",report.toString());finish(report.optBoolean("pass")?Activity.RESULT_OK:Activity.RESULT_CANCELED,result);
        }
    }

    private void staleResponse()throws Exception{
        stage="stale-format-response";gate=new Gate("NCP","",1);
        chooseFormat("NCP");check(gate.entered.await(8,TimeUnit.SECONDS),"old-format-request-held");
        int requestStart=requests.size();chooseFormat("NP3");
        until(()->!Boolean.TRUE.equals(get(activity,"loadingCatalog"))&&"NP3".equals(get(activity,"onlineFormatFilter"))&&((Number)get(activity,"catalogTotal")).longValue()==24&&((List<?>)get(activity,"catalog")).size()>=20,"new-format-result-arrives-before-old-response",10000);
        check(requests.subList(requestStart,requests.size()).stream().filter(x->x.contains("/community/feed")&&x.contains("fileFormat=NP3")).findFirst().orElse("").contains("page=1&"),"new-format-request-starts-page-one-before-scroll-restoration");
        gate.release.countDown();Thread.sleep(700);waitForIdleSync();
        check("NP3".equals(get(activity,"onlineFormatFilter")),"late-ncp-response-keeps-np3-selection");
        check(((Number)get(activity,"catalogTotal")).longValue()==24,"late-ncp-response-keeps-new-total");
        assertVisibleFormat("NP3");gate=null;
    }
    private void categoryRace()throws Exception{
        stage="stale-category-response";gate=new Gate("NP3","人像",1);
        chooseCategory("人像");check(gate.entered.await(8,TimeUnit.SECONDS),"old-category-request-held");
        chooseCategory("风景");awaitCatalog("NP3","风景",12,1,12);
        gate.release.countDown();Thread.sleep(700);waitForIdleSync();
        check("风景".equals(get(activity,"onlineCategoryFilter")),"late-portrait-response-keeps-landscape-selection");
        for(Object row:(List<?>)get(activity,"visiblePresets"))check("风景".equals(get(row,"category")),"late-category-response-cannot-leak-portrait");
        gate=null;
    }
    private void stateAndConfiguration()throws Exception{
        stage="local-online-return";tap(textView("我的预设"));
        until(()->Boolean.TRUE.equals(get(activity,"localTab")),"native-switch-to-local",5000);
        check(findTag(root(),FILTER)==null,"online-format-control-hidden-in-local-library");
        tap(textView("在线预设"));awaitCatalog("NP3","风景",12,1,12);geometry("online-return");
        Bundle saved=new Bundle();ui(()->invoke(activity,"onSaveInstanceState",new Class<?>[]{Bundle.class},saved));
        check("NP3".equals(saved.getString("onlinePresetFormat")),"saved-instance-state-retains-format");
        check("风景".equals(saved.getString("onlinePresetCategory")),"saved-instance-state-retains-category");
        stage="native-configuration-change";
        int before=activity.getResources().getConfiguration().orientation;
        ui(()->activity.setRequestedOrientation(before==Configuration.ORIENTATION_PORTRAIT?ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE:ActivityInfo.SCREEN_ORIENTATION_PORTRAIT));
        until(()->activity.getResources().getConfiguration().orientation!=before,"native-orientation-change-observed",10000);
        awaitCatalog("NP3","风景",12,1,12);geometry("rotated");capture("rotated-selection");
        ui(()->activity.setRequestedOrientation(before==Configuration.ORIENTATION_PORTRAIT?ActivityInfo.SCREEN_ORIENTATION_PORTRAIT:ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE));
        until(()->activity.getResources().getConfiguration().orientation==before,"native-orientation-restored",10000);
        awaitCatalog("NP3","风景",12,1,12);geometry("rotation-return");
    }
    private void cachedCombination()throws Exception{
        stage="cached-format-category-combination";
        Map<String,Object> cache=map("schemaVersion",1,"endpoint",managedEndpoint(),"fetchedAt",System.currentTimeMillis(),"manifest",map("version",1,"presets",rows));
        File cacheFile=new File(fixtureRoot,"online-presets/catalog.json");Files.writeString(cacheFile.toPath(),new JSONObject(cache).toString());
        failPages=true;
        ui(()->invoke(activity,"loadCatalog",new Class<?>[]{boolean.class},true));
        until(()->!Boolean.TRUE.equals(get(activity,"loadingCatalog"))&&Boolean.TRUE.equals(get(activity,"catalogFromCache")),"explicit-cache-read-marked",10000);
        check(((List<?>)get(activity,"visiblePresets")).size()==12,"cache-count-uses-both-active-filters");
        assertVisibleFormat("NP3");for(Object row:(List<?>)get(activity,"visiblePresets"))check("风景".equals(get(row,"category")),"cached-rows-keep-category");
        check(findText(root(),"缓存 · 12 份")!=null,"cache-heading-count-disclosed");
        failPages=false;
    }

    private void injectRepository()throws Exception{
        Class<?> http=type("library.SecureHttpClient"), connections=type("library.SecureHttpClient$Connections");
        Object seam=Proxy.newProxyInstance(loader,new Class<?>[]{connections},(proxy,method,values)->{
            if(method.getName().equals("open"))return connection((URL)values[0]);
            if(method.getName().equals("toString"))return "Online format isolated HTTPS fixture";
            if(method.getName().equals("hashCode"))return System.identityHashCode(proxy);
            if(method.getName().equals("equals"))return proxy==values[0];
            throw new UnsupportedOperationException(method.getName());
        });
        Constructor<?> hc=http.getDeclaredConstructor(connections);hc.setAccessible(true);Object client=hc.newInstance(seam);
        Constructor<?> rc=type("library.OnlinePresetRepository").getDeclaredConstructor(File.class,type("library.PresetLibrary"),http);rc.setAccessible(true);
        fixtureRepository=rc.newInstance(fixtureRoot,get(activity,"library"),client);
        invoke(fixtureRepository,"useManagedEndpoint",new Class<?>[]{String.class},managedEndpoint());
    }
    private String managedEndpoint()throws Exception{return String.valueOf(type("library.OnlinePresetRepository").getField("MANAGED_CATALOG_URL").get(null));}
    private HttpsURLConnection connection(URL url)throws Exception{
        requests.add(url.toString());
        if(url.getHost().equals("format-fixture.invalid")){
            byte[] recipe=recipes.get(url.getPath());if(recipe==null)throw new IOException("Unrecognized fixture recipe");return new MemoryConnection(url,recipe,null);
        }
        if(!url.getPath().endsWith("/community/feed"))throw new IOException("Blocked non-fixture HTTPS operation");
        Map<String,String> query=new HashMap<>();for(String part:url.getQuery().split("&")){String[] pair=part.split("=",2);query.put(URLDecoder.decode(pair[0],StandardCharsets.UTF_8),pair.length==1?"":URLDecoder.decode(pair[1],StandardCharsets.UTF_8));}
        String format=query.getOrDefault("fileFormat",query.getOrDefault("format","")),category=query.getOrDefault("category","");
        int page=Integer.parseInt(query.getOrDefault("page","1")),size=Integer.parseInt(query.getOrDefault("pageSize","20"));
        if(failPages)throw new IOException("Explicit offline page fixture");
        List<Map<String,Object>> selected=new ArrayList<>();for(Map<String,Object> row:rows)if((format.isEmpty()||format.equals(row.get("fileFormat")))&&(category.isEmpty()||category.equals(row.get("category"))))selected.add(row);
        int start=Math.min(selected.size(),(page-1)*size),end=Math.min(selected.size(),start+size);
        Gate current=gate;Gate held=current!=null&&current.format.equals(format)&&current.category.equals(category)&&current.page==page?current:null;
        byte[] body=new JSONObject(map("items",new ArrayList<>(selected.subList(start,end)),"total",selected.size(),"page",page,"pageSize",size,"hasMore",end<selected.size(),"fileFormat",format,"categories",List.of("人像","风景","黑白"))).toString().getBytes(StandardCharsets.UTF_8);
        return new MemoryConnection(url,body,held);
    }
    private void createRows()throws Exception{
        byte[] np3;try(InputStream input=getContext().getAssets().open("supported.np3")){np3=input.readAllBytes();}
        for(int i=0;i<72;i++){
            String format=i<48?"NCP":"NP3",category=i<20?"人像":i<40?"风景":i<48?"黑白":i<60?"人像":"风景";
            String id=String.format(java.util.Locale.ROOT,"format-qa-%03d",i),name=String.format(java.util.Locale.ROOT,"%s · %s %02d",category,format,i+1);
            byte[] recipe=format.equals("NP3")?np3:ncp("QA FILM "+i);String path="/"+id+"."+format.toLowerCase(java.util.Locale.ROOT);recipes.put(path,recipe);
            rows.add(map("id",id,"name",name,"description","Explicit isolated native filter fixture","fileUrl","https://format-fixture.invalid"+path,"sha256",sha(recipe),"byteLength",recipe.length,"previewUrl","","category",category,"compatibleModels",List.of(),"fileFormat",format,"source","community","authorName","QA"));
        }
        report.put("fixtureItems",rows.size()).put("np3FixtureSha256",sha(np3));
    }
    private static byte[] ncp(String name){byte[] value=new byte[52];value[0]='N';value[1]='C';value[2]='P';value[7]=1;value[11]=36;value[12]='0';value[13]='1';value[14]='0';value[15]='0';byte[] label=name.getBytes(StandardCharsets.US_ASCII);System.arraycopy(label,0,value,16,Math.min(19,label.length));return value;}

    private void chooseFormat(String label)throws Exception{
        until(()->findTag(root(),FILTER)!=null,"format-menu-visible-before-"+label,5000);
        tap(findTag(root(),FILTER));until(()->get(activity,"onlineFormatMenu")!=null&&activeText("NCP")!=null&&activeText("NP3")!=null,"format-popup-opened",5000);
        ui(()->{var menu=((android.widget.PopupMenu)get(activity,"onlineFormatMenu")).getMenu();check(menu.size()==3,"format-menu-has-only-three-options");String selected=String.valueOf(get(activity,"onlineFormatFilter"));int active=selected.isEmpty()?0:selected.equals("NCP")?1:2;for(int i=0;i<3;i++)check(menu.getItem(i).isCheckable()&&menu.getItem(i).isChecked()==(active==i),"format-menu-single-selection-"+i);});
        if(!menuCaptured){capture("format-menu");menuCaptured=true;}
        clickActive(label.isEmpty()?"全部格式":label);
        until(()->get(activity,"onlineFormatMenu")==null,"format-popup-closes-after-selection",5000);
    }
    private void chooseCategory(String label)throws Exception{
        String description="预设分类："+label;until(()->findDescription(root(),description)!=null,"category-control-present-"+label,5000);
        View chip=findDescription(root(),description);ui(()->chip.requestRectangleOnScreen(new Rect(0,0,chip.getWidth(),chip.getHeight()),false));waitForIdleSync();tap(chip);
    }
    private void awaitCatalog(String format,String category,int count,int page,long total)throws Exception{
        until(()->!Boolean.TRUE.equals(get(activity,"loadingCatalog"))&&Boolean.TRUE.equals(get(activity,"catalogLoaded"))&&format.equals(get(activity,"onlineFormatFilter"))&&category.equals(get(activity,"onlineCategoryFilter"))&&((List<?>)get(activity,"catalog")).size()==count&&((Number)get(activity,"catalogPage")).intValue()==page&&((Number)get(activity,"catalogTotal")).longValue()==total,"catalog-"+format+"-"+category+"-page"+page+"-count"+count,15000);
        waitForIdleSync();
        check(findText(root(),total+" 份")!=null,"heading-shows-server-total-"+total);
    }
    private void assertVisibleFormat(String format)throws Exception{
        List<?> visible=(List<?>)get(activity,"visiblePresets");check(!visible.isEmpty(),"visible-results-present-"+format);
        for(Object row:visible)check(format.equals(get(row,"fileFormat")),"visible-format-"+get(row,"id")+"-"+format);
        check(String.valueOf(get(activity,"presetGridKey")).contains(format),"grid-position-key-includes-format-"+format);
    }
    private void geometry(String id)throws Exception{
        waitForIdleSync();ui(()->{
            View control=findTag(root(),FILTER);check(control!=null,"format-control-present-"+id);
            String label=String.valueOf(get(activity,"onlineFormatFilter"));if(label.isEmpty())label="全部格式";
            View labelView=findText(control,label);check(labelView instanceof TextView,"format-control-label-present-"+id);
            TextView text=(TextView)labelView;float density=activity.getResources().getDisplayMetrics().density;
            Rect visible=new Rect();check(control.getGlobalVisibleRect(visible)&&visible.width()==control.getWidth()&&visible.height()==control.getHeight(),"format-control-unclipped-"+id);
            check(control.getHeight()>=Math.round(48*density),"format-touch-height48dp-"+id);
            check(text.getLineCount()==1,"format-label-single-line-"+id);
            check(text.getLayout()!=null&&text.getLayout().getEllipsisCount(0)==0,"format-label-not-ellipsized-"+id);
            check(text.getTextSize()/activity.getResources().getDisplayMetrics().scaledDensity<=13.1f,"format-font-stays-compact-"+id);
            check(control.isSelected()==!String.valueOf(get(activity,"onlineFormatFilter")).isEmpty(),"format-control-selected-state-"+id);
            check(control.getParent() instanceof ViewGroup&&((ViewGroup)control.getParent()).getChildCount()>=3,"format-sits-with-heading-and-count-"+id);
        });
    }
    private void capture(String name)throws Exception{
        waitForIdleSync();Thread.sleep(500);Bitmap image=getUiAutomation().takeScreenshot();if(image==null)throw new IOException("Native screenshot unavailable");
        File path=new File(output,name+".png");try(FileOutputStream stream=new FileOutputStream(path)){if(!image.compress(Bitmap.CompressFormat.PNG,100,stream))throw new IOException("Screenshot write failed");}finally{image.recycle();}
        screenshots.put(new JSONObject().put("file",path.getName()).put("sha256",sha(path)));
    }
    private View root(){return activity.getWindow().getDecorView();}
    private View textView(String text)throws Exception{View view=findText(root(),text);if(view==null)throw new IOException("Missing text "+text);return view;}
    private static View findText(View root,String text){if(root instanceof TextView&&text.contentEquals(((TextView)root).getText()))return root;if(root instanceof ViewGroup)for(int i=0;i<((ViewGroup)root).getChildCount();i++){View found=findText(((ViewGroup)root).getChildAt(i),text);if(found!=null)return found;}return null;}
    private static View findContaining(View root,String text){if(root instanceof TextView&&((TextView)root).getText().toString().contains(text))return root;if(root instanceof ViewGroup)for(int i=0;i<((ViewGroup)root).getChildCount();i++){View found=findContaining(((ViewGroup)root).getChildAt(i),text);if(found!=null)return found;}return null;}
    private static View findTag(View root,String tag){if(tag.equals(root.getTag()))return root;if(root instanceof ViewGroup)for(int i=0;i<((ViewGroup)root).getChildCount();i++){View found=findTag(((ViewGroup)root).getChildAt(i),tag);if(found!=null)return found;}return null;}
    private static View findDescription(View root,String value){if(value.contentEquals(root.getContentDescription()==null?"":root.getContentDescription()))return root;if(root instanceof ViewGroup)for(int i=0;i<((ViewGroup)root).getChildCount();i++){View found=findDescription(((ViewGroup)root).getChildAt(i),value);if(found!=null)return found;}return null;}
    private AccessibilityNodeInfo activeText(String value){AccessibilityNodeInfo root=getUiAutomation().getRootInActiveWindow();if(root==null)return null;for(AccessibilityNodeInfo node:root.findAccessibilityNodeInfosByText(value))if(value.contentEquals(node.getText()==null?"":node.getText()))return node;return null;}
    private void clickActive(String text)throws Exception{AccessibilityNodeInfo node=activeText(text);if(node==null)throw new IOException("Missing active text "+text);Rect bounds=new Rect();node.getBoundsInScreen(bounds);check(!bounds.isEmpty()&&node.isVisibleToUser(),"native-popup-target-visible-"+text);long now=SystemClock.uptimeMillis();MotionEvent down=MotionEvent.obtain(now,now,MotionEvent.ACTION_DOWN,bounds.exactCenterX(),bounds.exactCenterY(),0);sendPointerSync(down);down.recycle();MotionEvent up=MotionEvent.obtain(now,now+65,MotionEvent.ACTION_UP,bounds.exactCenterX(),bounds.exactCenterY(),0);sendPointerSync(up);up.recycle();waitForIdleSync();}
    private void tap(View view)throws Exception{if(view==null)throw new IOException("Null native tap target");int[] point=new int[2],size=new int[2];ui(()->{view.getLocationOnScreen(point);size[0]=view.getWidth();size[1]=view.getHeight();});long now=SystemClock.uptimeMillis();MotionEvent down=MotionEvent.obtain(now,now,MotionEvent.ACTION_DOWN,point[0]+size[0]/2f,point[1]+size[1]/2f,0);sendPointerSync(down);down.recycle();MotionEvent up=MotionEvent.obtain(now,now+65,MotionEvent.ACTION_UP,point[0]+size[0]/2f,point[1]+size[1]/2f,0);sendPointerSync(up);up.recycle();waitForIdleSync();}
    private void check(boolean condition,String name){checks.put(new JSONObject(map("name",name,"pass",condition)));if(!condition){if(name.startsWith("format-touch-height48dp-")&&args.getString("diagnoseKnownTouchHeight","false").equals("true")){diagnosticKnownFailures++;return;}throw new AssertionError(name);}}
    private void until(Condition condition,String name,long timeout)throws Exception{long end=SystemClock.uptimeMillis()+timeout;Throwable last=null;while(SystemClock.uptimeMillis()<end){try{if(condition.get()){check(true,name);return;}}catch(Throwable error){last=error;}Thread.sleep(80);}AssertionError error=new AssertionError(name+" at "+stage);if(last!=null)error.initCause(last);throw error;}
    private void ui(Action action)throws Exception{Throwable[] failure={null};runOnMainSync(()->{try{action.run();}catch(Throwable error){failure[0]=error;}});if(failure[0]!=null){if(failure[0] instanceof Exception)throw (Exception)failure[0];if(failure[0] instanceof Error)throw (Error)failure[0];throw new RuntimeException(failure[0]);}}
    private Class<?> type(String suffix)throws Exception{return Class.forName(TARGET+"."+suffix,true,loader);}
    private static Field field(Object target,String name)throws Exception{for(Class<?> c=target.getClass();c!=null;c=c.getSuperclass())try{Field result=c.getDeclaredField(name);result.setAccessible(true);return result;}catch(NoSuchFieldException ignored){}throw new NoSuchFieldException(name);}
    private static Object get(Object target,String name)throws Exception{return field(target,name).get(target);}
    private static void set(Object target,String name,Object value)throws Exception{field(target,name).set(target,value);}
    private static Object invoke(Object target,String name)throws Exception{return invoke(target,name,new Class<?>[0]);}
    private static Object invoke(Object target,String name,Class<?>[] types,Object...values)throws Exception{for(Class<?> c=target.getClass();c!=null;c=c.getSuperclass())try{Method method=c.getDeclaredMethod(name,types);method.setAccessible(true);return method.invoke(target,values);}catch(NoSuchMethodException ignored){}throw new NoSuchMethodException(name);}
    private static String sha(File file)throws Exception{return sha(Files.readAllBytes(file.toPath()));}
    private static String sha(byte[] bytes)throws Exception{StringBuilder result=new StringBuilder();for(byte value:MessageDigest.getInstance("SHA-256").digest(bytes))result.append(String.format(java.util.Locale.ROOT,"%02x",value&255));return result.toString();}
    private static Map<String,Object> map(Object...values){Map<String,Object> result=new LinkedHashMap<>();for(int i=0;i<values.length;i+=2)result.put(String.valueOf(values[i]),values[i+1]);return result;}
    private interface Condition{boolean get()throws Exception;}
    private interface Action{void run()throws Exception;}
    private static final class Gate{final String format,category;final int page;final CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1);Gate(String format,String category,int page){this.format=format;this.category=category;this.page=page;}}
    private static final class MemoryConnection extends HttpsURLConnection{
        private final byte[] body;private final Gate gate;
        MemoryConnection(URL url,byte[] body,Gate gate){super(url);this.body=body;this.gate=gate;}
        @Override public int getResponseCode()throws IOException{if(gate!=null){gate.entered.countDown();try{if(!gate.release.await(12,TimeUnit.SECONDS))throw new IOException("Fixture gate timed out");}catch(InterruptedException interrupted){Thread.currentThread().interrupt();throw new IOException(interrupted);}}return 200;}
        @Override public InputStream getInputStream(){return new ByteArrayInputStream(body);}
        @Override public long getContentLengthLong(){return body.length;}
        @Override public String getHeaderField(String name){return null;}
        @Override public void disconnect(){}
        @Override public boolean usingProxy(){return false;}
        @Override public void connect(){}
        @Override public String getCipherSuite(){return "QA_MEMORY_ONLY";}
        @Override public Certificate[] getLocalCertificates(){return null;}
        @Override public Certificate[] getServerCertificates(){return new Certificate[0];}
        @Override public Principal getPeerPrincipal(){return null;}
        @Override public Principal getLocalPrincipal(){return null;}
    }
}
