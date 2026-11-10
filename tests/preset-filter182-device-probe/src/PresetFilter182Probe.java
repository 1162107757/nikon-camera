package cc.huevia.presetfilter182qa;

import android.app.*;
import android.content.*;
import android.graphics.*;
import android.os.*;
import android.view.*;
import android.widget.*;
import cc.huevia.library.*;
import java.io.*;
import java.lang.reflect.*;
import java.math.BigDecimal;
import java.nio.ByteBuffer;
import java.util.*;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.LongSupplier;
import org.json.*;

/** Actual installed Activity and Dialog, isolated library and synthetic complete390 metadata. */
public final class PresetFilter182Probe extends Instrumentation {
    private Bundle args; private Activity activity; private File output, temporary;
    private Object originalLibrary, originalPersonal; private String appearance;
    private Map<String,?> preferences;
    private final JSONArray checks = new JSONArray(); private final JSONObject report = new JSONObject();
    private final AtomicInteger fetches = new AtomicInteger(); private final CountDownLatch gate = new CountDownLatch(1);
    private volatile boolean network = true, disk; private List<OnlinePreset> rows;
    @Override public void onCreate(Bundle b) { args = b; start(); }
    @Override public void onStart() {
        Throwable failure = null;
        try {
            check("ranchu".equals(Build.HARDWARE) || "goldfish".equals(Build.HARDWARE), "owned-emulator");
            String run = args.getString("runId"); check(run != null && run.matches("[A-Za-z0-9.-]{8,100}"), "safe-run-id");
            output = new File(getTargetContext().getExternalFilesDir(null), "preset-filter182/" + run); check(output.mkdirs(), "new-evidence-directory");
            report.put("versionCode", getTargetContext().getPackageManager().getPackageInfo("cc.huevia", 0).getLongVersionCode());
            check(report.getLong("versionCode") == 182, "exact-installed-version182");
            appearance = cc.huevia.ui.AppAppearance.mode(getTargetContext());
            preferences = new HashMap<>(getTargetContext().getSharedPreferences("preset-home-filter-v1", 0).getAll());
            getTargetContext().getSharedPreferences("preset-home-filter-v1", 0).edit().clear().commit();
            cc.huevia.ui.AppAppearance.setMode(getTargetContext(), args.getString("appearance", "light"));
            activity = startActivitySync(new Intent(Intent.ACTION_MAIN).setClassName("cc.huevia", "cc.huevia.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK));
            until(() -> Boolean.TRUE.equals(get(activity, "ready")), "main-ready");
            originalLibrary = get(activity, "library"); originalPersonal = get(activity, "personal");
            temporary = new File(getTargetContext().getCacheDir(), "preset-filter182-" + run);
            PresetLibrary library = new PresetLibrary(temporary);
            PresetRecord saved = library.importFile("NCP misleading.np3", np3()).record;
            library.setCategory(saved.id, "风景"); rows = fixtures(saved);
            Object engine = engine();
            ui(() -> {
                set(activity, "library", library); set(activity, "personal", null);
                set(activity, "settingsTab", false); set(activity, "albumTab", false); set(activity, "localAlbumTab", false); set(activity, "localTab", false);
                set(activity, "catalogEpoch", ((Integer)get(activity, "catalogEpoch")) + 1); set(activity, "loadingCatalog", false);
                set(activity, "catalog", new ArrayList<>(rows.subList(0, 20))); set(activity, "catalogLoaded", true);
                set(activity, "catalogPage", 1); set(activity, "catalogTotal", 390L); set(activity, "catalogHasMore", false);
                set(activity, "homePresetQuery", ""); set(activity, "onlineSearch", engine);
                set(activity, "onlineCategoryFilter", PresetCategories.ALL); set(activity, "onlineFormatFilter", "");
                call(activity, "render");
            });
            check(text().contains("390 份"), "unfiltered-server-total-retained");
            check(visible().size() == 20, "first-page-browse-fixture20");
            ui(() -> call(activity, "showPresetFilters")); Dialog sheet = sheet();
            check(sheet.isShowing(), "custom-sheet-opens");
            touchTargets(sheet.getWindow().getDecorView()); geometry(sheet); capture("01-sheet-online");
            click(sheet, "preset-filter:预设类型:NP3"); click(sheet, "preset-filter:下载状态:saved");
            check("".equals(get(activity, "onlineFormatFilter")), "draft-type-not-committed");
            click(sheet, "preset-filter-close"); check("".equals(get(activity, "onlineFormatFilter")), "close-discards-draft");
            ui(() -> call(activity, "showPresetFilters")); sheet = sheet();
            click(sheet, "preset-filter:风格:风景"); click(sheet, "preset-filter:预设类型:NP3");
            click(sheet, "preset-filter:下载状态:saved"); capture("02-draft-combination");
            click(sheet, "preset-filter-apply"); until(() -> fetches.get() == 1, "complete-index-request");
            check(text().contains("加载中"), "pending-filter-not-zero"); gate.countDown();
            until(() -> !Boolean.TRUE.equals(get(activity, "loadingOnlineSearch")), "complete-index-ready");
            until(() -> visible().size() == 1, "deep-saved-NP3-after-first-page-found");
            check(((OnlinePreset)visible().get(0)).id.equals("qa182-389"), "real-type-despite-misleading-NCP-name-and-url");
            check(text().contains("1 份匹配"), "combined-full-library-count"); capture("03-combined-deep-result");
            ui(() -> call(activity, "showPresetFilters")); sheet = sheet();
            check(find(sheet.getWindow().getDecorView(), "preset-filter:风格:风景").isSelected(), "sheet-reopens-committed-style");
            click(sheet, "preset-filter-reset"); check("NP3".equals(get(activity, "onlineFormatFilter")), "reset-only-changes-draft");
            final Dialog backSheet = sheet; ui(() -> backSheet.onBackPressed());
            check("NP3".equals(get(activity, "onlineFormatFilter")), "system-back-discards-reset");
            ui(() -> call(activity, "showPresetFilters")); sheet = sheet();
            click(sheet, "preset-filter:风格:" + PresetCategories.ALL); click(sheet, "preset-filter:下载状态:missing");
            click(sheet, "preset-filter-apply"); until(() -> ((Integer)get(activity, "homePresetMatchCount")) == 194, "type-plus-missing-count194");
            int firstPage = visible().size();
            check(firstPage >= 20 && firstPage < 194 && firstPage % 20 == 0, "full-filter-result-page20-increments-with-large-viewport-prefetch");
            ui(() -> call(activity, "loadMoreHomeIndex")); until(() -> visible().size() >= firstPage + 20, "filtered-local-pagination-adds-next20");
            check(text().contains("194 份匹配"), "pagination-does-not-change-full-count");
            check(fetches.get() == 1, "paging-and-conditions-reuse-full-index"); capture("04-filter-pagination");
            ui(() -> call(activity, "selectPresetCategory", "风景"));
            check("风景".equals(get(activity, "onlineCategoryFilter")), "shortcut-track-shares-style");
            ui(() -> call(activity, "searchHomePresets")); query("天空");
            until(() -> visible().isEmpty(), "search-intersects-missing-download");
            ui(() -> call(activity, "showPresetFilters")); sheet = sheet(); click(sheet, "preset-filter:下载状态:saved"); click(sheet, "preset-filter-apply");
            until(() -> visible().size() == 1, "search-style-type-download-all-combine");
            check(fetches.get() == 1, "typing-reuses-index");
            ui(() -> call(activity, "closeHomePresetSearch")); check(visible().size() == 1, "closing-search-keeps-applied-filter");
            Bundle state = new Bundle(); ui(() -> call(activity, "onSaveInstanceState", state));
            check(state.getInt("presetHomeFilterVersion") == 1 && state.getString("presetHomeOnlineType").equals("NP3"), "versioned-saved-state");
            ui(() -> { set(activity, "onlineFormatFilter", "NCP"); call(activity, "restorePresetHomeFilters", state); });
            check("NP3".equals(get(activity, "onlineFormatFilter")), "applied-state-restores");
            ui(() -> { set(activity, "onlineFormatFilter", ""); call(activity, "restorePresetHomeFilters", (Object)null); });
            check("NP3".equals(get(activity, "onlineFormatFilter")), "persistent-applied-filter-restores-without-bundle");
            getTargetContext().getSharedPreferences("preset-home-filter-v1", 0).edit().clear().commit();
            Bundle old = new Bundle(); old.putString("onlinePresetFormat", "NCP");
            ui(() -> call(activity, "restorePresetHomeFilters", old));
            check("".equals(get(activity, "onlineFormatFilter")), "legacy-format-key-cannot-hide-presets");
            ui(() -> { call(activity, "restorePresetHomeFilters", state); call(activity, "selectPresetSource", true); }); SystemClock.sleep(200);
            ui(() -> call(activity, "showPresetFilters")); sheet = sheet();
            check(find(sheet.getWindow().getDecorView(), "preset-filter:下载状态:saved") == null, "local-download-group-hidden");
            touchTargets(sheet.getWindow().getDecorView()); geometry(sheet); capture("05-sheet-local");
            click(sheet, "preset-filter:预设类型:NCP"); click(sheet, "preset-filter-apply");
            check(visible().isEmpty(), "local-type-filter-uses-real-file-format");
            check(text().contains("没有符合条件的预设"), "local-filter-empty-has-recovery");
            ui(() -> call(activity, "showPresetFilters")); sheet = sheet(); click(sheet, "preset-filter-reset"); click(sheet, "preset-filter-apply");
            check(visible().size() == 1, "local-reset-restores-file");
            ui(() -> call(activity, "selectPresetSource", false)); SystemClock.sleep(200);
            check("NP3".equals(get(activity, "onlineFormatFilter")), "sources-keep-independent-types");
            network = false; disk = true; ui(() -> call(activity, "retryOnlinePresetSearch"));
            until(() -> !Boolean.TRUE.equals(get(activity, "loadingOnlineSearch")), "cache-fallback-ready");
            check(text().contains("缓存 · 1 份匹配"), "cached-combined-result-labeled"); capture("06-cache-result");
            disk = false; Object unavailable = engine();
            ui(() -> { set(activity, "onlineSearch", unavailable); set(activity, "onlineSearchSnapshot", null); set(activity, "onlineSearchAttempted", false); call(activity, "render"); });
            until(() -> !Boolean.TRUE.equals(get(activity, "loadingOnlineSearch")), "unavailable-completes");
            check(text().contains("暂时无法筛选"), "unavailable-full-catalog-distinct-from-empty");
            check(!text().contains("0 份匹配"), "partial-page-never-counted-as-full-library-zero");
            network = true; ui(() -> call(activity, "retryOnlinePresetSearch"));
            until(() -> !Boolean.TRUE.equals(get(activity, "loadingOnlineSearch")) && visible().size() == 1, "retry-preserves-applied-filter");
            library.remove(saved.id); ui(() -> call(activity, "applyRefreshedPresetLibrary"));
            check(visible().isEmpty(), "deletion-updates-online-downloaded-filter");
            check(text().contains("0 份匹配"), "download-count-reflects-real-library-removal");
            capture("07-empty-after-local-delete");
            report.put("scope", "Installed182 actual MainActivity/custom Dialog; isolated validated NP3 library plus synthetic390 complete catalog, first20 browsing. Covers three-group combination, full counts/local paging/search, draft close/back/reset, shared category, versioned restoration, local semantics, cache/error/retry and committed deletion. No live server or camera writes.");
        } catch (Throwable t) { failure = t; try { report.put("failure", android.util.Log.getStackTraceString(t)); } catch (Exception ignored) { } }
        finally {
            gate.countDown();
            try { if (activity != null) ui(() -> { Dialog d = (Dialog)get(activity, "presetFilterSheet"); if (d != null) d.dismiss(); if (originalLibrary != null) set(activity,"library",originalLibrary); if(originalPersonal != null)set(activity,"personal",originalPersonal); activity.finish(); }); } catch (Throwable ignored) { }
            try {
                if (appearance != null) cc.huevia.ui.AppAppearance.setMode(getTargetContext(), appearance);
                if (preferences != null) { SharedPreferences.Editor e=getTargetContext().getSharedPreferences("preset-home-filter-v1",0).edit().clear(); for(Map.Entry<String,?> p:preferences.entrySet()) {Object v=p.getValue();if(v instanceof String)e.putString(p.getKey(),(String)v);else if(v instanceof Integer)e.putInt(p.getKey(),(Integer)v);}e.commit(); }
                if (temporary != null && temporary.getCanonicalPath().startsWith(getTargetContext().getCacheDir().getCanonicalPath() + File.separator + "preset-filter182-")) erase(temporary);
            } catch (Throwable ignored) { }
            try { report.put("pass", failure == null); report.put("checks", checks); report.put("candidateSha256", args.getString("candidateSha256")); if (output != null) try (Writer w = new OutputStreamWriter(new FileOutputStream(new File(output, "report.json")), "UTF-8")) { w.write(report.toString(2)); } } catch (Exception ignored) { }
            Bundle result = new Bundle(); result.putString("result", report.toString()); finish(failure == null ? -1 : 0, result);
        }
    }
    private List<OnlinePreset> fixtures(PresetRecord saved) throws Exception {
        List<OnlinePreset> result = new ArrayList<>();
        for(int i=0;i<390;i++){
            Map<String,Object> m=new LinkedHashMap<>();m.put("id","qa182-"+i);m.put("name",i==389?"NCP 名称·天空":"NP3 名称·色彩 "+i);
            m.put("fileUrl","https://example.invalid/misleading.ncp");m.put("fileFormat",i%2==0?"NCP":"NP3");
            m.put("sha256",i==389?saved.sha256:String.format("%064x",i+1));m.put("byteLength",BigDecimal.valueOf(i==389?saved.byteLength:52));
            m.put("category",i==389?"风景":Arrays.asList("人像","风景","胶片","黑白","日常","夜景","").get(i%7));result.add(OnlinePreset.fromMap(m));
        }return result;
    }
    private byte[] np3() throws Exception {
        ByteArrayOutputStream bytes=new ByteArrayOutputStream();DataOutputStream out=new DataOutputStream(bytes);out.write(new byte[]{'N','C','P',0});
        for(int i=1;i<=32;i++){int len=i==1?4:i==2||i==32?20:i==31?28:2;out.writeInt(i*0x100);out.writeInt(len);byte[] value=new byte[len];if(i==1)System.arraycopy("0310".getBytes("US-ASCII"),0,value,0,4);out.write(value);}out.writeInt(0);return bytes.toByteArray();
    }
    private Object engine() throws Exception {
        Class<?> source=Class.forName("cc.huevia.library.OnlinePresetSearch$Source");
        Object provider=Proxy.newProxyInstance(source.getClassLoader(),new Class<?>[]{source},(proxy,method,values)->{
            if(method.getName().equals("fetch")){fetches.incrementAndGet();if(!gate.await(25,TimeUnit.SECONDS))throw new AssertionError("gate timed out");return result(network?"ok":"error",network);}
            if(method.getName().equals("cached"))return result(disk?"cached":"no_cache",disk);throw new AssertionError(method.getName());});
        Constructor<?> c=OnlinePresetSearch.class.getDeclaredConstructor(source,LongSupplier.class);c.setAccessible(true);return c.newInstance(provider,(LongSupplier)System::currentTimeMillis);
    }
    private Object result(String status,boolean present)throws Exception{Constructor<?> c=OnlinePresetRepository.CatalogResult.class.getDeclaredConstructor(String.class,String.class,List.class,boolean.class);c.setAccessible(true);return c.newInstance(status,"",present?rows:Collections.emptyList(),status.equals("cached"));}
    private Dialog sheet() throws Exception { waitForIdleSync(); return (Dialog)get(activity,"presetFilterSheet"); }
    private void click(Dialog dialog,String tag)throws Exception{ui(()->{View view=find(dialog.getWindow().getDecorView(),tag);if(view==null)throw new AssertionError("Missing "+tag);view.requestRectangleOnScreen(new Rect(0,0,view.getWidth(),view.getHeight()),true);view.performClick();});waitForIdleSync();}
    private void erase(File file) { File[] children=file.listFiles();if(children!=null)for(File child:children)erase(child);file.delete(); }
    private View find(View v,String tag){if(tag.equals(v.getTag()))return v;if(v instanceof ViewGroup)for(int i=0;i<((ViewGroup)v).getChildCount();i++){View f=find(((ViewGroup)v).getChildAt(i),tag);if(f!=null)return f;}return null;}
    private void touchTargets(View root)throws Exception{float density=activity.getResources().getDisplayMetrics().density;List<View> list=new ArrayList<>();collect(root,list);for(View v:list)if(v.getTag() instanceof String&&((String)v.getTag()).startsWith("preset-filter")&&v.isClickable())check(v.getWidth()+1>=48*density&&v.getHeight()+1>=48*density,"48dp-"+v.getTag());}
    private void collect(View v,List<View> list){list.add(v);if(v instanceof ViewGroup)for(int i=0;i<((ViewGroup)v).getChildCount();i++)collect(((ViewGroup)v).getChildAt(i),list);}
    private void geometry(Dialog dialog)throws Exception{Rect apply=new Rect(),close=new Rect();View a=find(dialog.getWindow().getDecorView(),"preset-filter-apply"),c=find(dialog.getWindow().getDecorView(),"preset-filter-close");check(a.getGlobalVisibleRect(apply)&&apply.height()==a.getHeight(),"fixed-apply-fully-visible");check(c.getGlobalVisibleRect(close)&&close.height()==c.getHeight(),"fixed-close-fully-visible");check(close.bottom<apply.top,"header-footer-do-not-overlap");Object mode=find(dialog.getWindow().getDecorView(),"preset-filter-sheet").getTag(cc.huevia.R.id.preset_filter_material);check("blur".equals(mode)||"translucent-fallback".equals(mode),"glass-or-explicit-fallback");report.put("material",mode);View nav=activity.getWindow().getDecorView().findViewWithTag("root-floating-navigation");check(nav==null||nav.getVisibility()!=View.VISIBLE,"navigation-hidden-under-sheet");}
    private void query(String value)throws Exception{ui(()->((EditText)get(activity,"homePresetSearchInput")).setText(value));SystemClock.sleep(210);}
    private List<?> visible()throws Exception{return(List<?>)get(activity,"visiblePresets");}
    private String text(){StringBuilder b=new StringBuilder();runOnMainSync(()->visibleText(activity.getWindow().getDecorView(),b));return b.toString();}
    private void visibleText(View v,StringBuilder b){if(v.getVisibility()!=View.VISIBLE)return;if(v instanceof TextView)b.append(((TextView)v).getText()).append(' ');if(v instanceof ViewGroup)for(int i=0;i<((ViewGroup)v).getChildCount();i++)visibleText(((ViewGroup)v).getChildAt(i),b);}
    private void capture(String name)throws Exception{
        waitForIdleSync();
        CountDownLatch frame=new CountDownLatch(1);
        ui(()->{View decor=activity.getWindow().getDecorView();decor.postOnAnimation(()->decor.postOnAnimation(frame::countDown));decor.invalidate();});
        check(frame.await(3,TimeUnit.SECONDS),"settled-frame-"+name);SystemClock.sleep(200);
        report.put(name+"Text",text());Bitmap b=getUiAutomation().takeScreenshot();
        try(OutputStream s=new FileOutputStream(new File(output,name+".png"))){b.compress(Bitmap.CompressFormat.PNG,100,s);}b.recycle();
    }
    private void check(boolean value,String name)throws Exception{checks.put(new JSONObject().put("name",name).put("pass",value));if(!value)throw new AssertionError(name);}
    private interface Work{void run()throws Exception;}private interface Condition{boolean test()throws Exception;}
    private void ui(Work work)throws Exception{Throwable[] t={null};runOnMainSync(()->{try{work.run();}catch(Throwable e){t[0]=e;}});if(t[0]!=null)throw new RuntimeException(t[0]);}
    private void until(Condition c,String name)throws Exception{long end=SystemClock.uptimeMillis()+30000;while(SystemClock.uptimeMillis()<end){if(c.test())return;SystemClock.sleep(40);}throw new AssertionError("Timeout "+name);}
    private static Object get(Object target,String name)throws Exception{Field f=target.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(target);}
    private static void set(Object target,String name,Object value)throws Exception{Field f=target.getClass().getDeclaredField(name);f.setAccessible(true);f.set(target,value);}
    private static Object call(Object target,String name,Object...args)throws Exception{for(Method m:target.getClass().getDeclaredMethods())if(m.getName().equals(name)&&m.getParameterCount()==args.length){m.setAccessible(true);return m.invoke(target,args);}throw new NoSuchMethodException(name);}
}
