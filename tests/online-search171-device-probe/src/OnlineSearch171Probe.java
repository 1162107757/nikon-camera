package cc.huevia.onlinesearch171qa;

import android.app.*;
import android.content.*;
import android.graphics.Bitmap;
import android.os.*;
import android.view.*;
import android.widget.*;
import cc.huevia.library.*;
import java.io.*;
import java.lang.reflect.*;
import java.math.BigDecimal;
import java.util.*;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.LongSupplier;
import org.json.*;

/** Synthetic metadata index in actual installed MainActivity. No accounts, camera or preset writes. */
public final class OnlineSearch171Probe extends Instrumentation {
    private Bundle args; private Activity activity; private File output;
    private final JSONArray checks = new JSONArray(); private final JSONObject report = new JSONObject();
    private final AtomicInteger fetches = new AtomicInteger(); private final CountDownLatch gate = new CountDownLatch(1);
    private volatile boolean online = true, disk; private List<OnlinePreset> rows; private String appearance;
    @Override public void onCreate(Bundle b) { args = b; start(); }
    @Override public void onStart() {
        Throwable failure = null;
        try {
            check("ranchu".equals(Build.HARDWARE) || "goldfish".equals(Build.HARDWARE), "owned-emulator");
            String run = args.getString("runId"); check(run != null && run.matches("[A-Za-z0-9.-]{8,100}"), "safe-run-id");
            output = new File(getTargetContext().getExternalFilesDir(null), "online-search171/" + run); check(output.mkdirs(), "new-evidence-directory");
            long version = getTargetContext().getPackageManager().getPackageInfo("cc.huevia", 0).getLongVersionCode();
            report.put("versionCode", version); report.put("sdk", Build.VERSION.SDK_INT); check(version == 171, "exact-version171");
            appearance = cc.huevia.ui.AppAppearance.mode(getTargetContext());
            cc.huevia.ui.AppAppearance.setMode(getTargetContext(), args.getString("appearance", "light"));
            activity = startActivitySync(new Intent(Intent.ACTION_MAIN).setClassName("cc.huevia", "cc.huevia.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK));
            until(() -> Boolean.TRUE.equals(get(activity, "ready")), "main-ready");
            rows = fixtures(); Object engine = engine();
            ui(() -> {
                set(activity, "settingsTab", false); set(activity, "albumTab", false); set(activity, "localAlbumTab", false); set(activity, "localTab", false);
                set(activity, "catalogEpoch", ((Integer)get(activity, "catalogEpoch")) + 1); set(activity, "loadingCatalog", false);
                set(activity, "catalog", new ArrayList<>(rows.subList(0, 20))); set(activity, "catalogLoaded", true);
                set(activity, "catalogPage", 1); set(activity, "catalogTotal", 390L); set(activity, "catalogHasMore", false);
                set(activity, "homePresetQuery", ""); set(activity, "onlineSearch", engine); call(activity, "render"); call(activity, "searchHomePresets");
            });
            query("蔚蓝天空"); until(() -> fetches.get() == 1, "full-index-request-starts");
            check(text().contains("搜索中"), "pending-search-is-not-zero-results");
            check(!text().contains("没有匹配的预设"), "pending-search-does-not-claim-empty"); capture("01-search-loading");
            gate.countDown(); until(() -> !Boolean.TRUE.equals(get(activity, "loadingOnlineSearch")), "full-index-completes");
            until(() -> visible().size() == 1, "deep-preset-found");
            check(((OnlinePreset)visible().get(0)).name.equals("蔚蓝天空"), "actual-name-after-page-one");
            check(text().contains("1 份匹配"), "complete-index-count");
            check(((List<?>)get(activity, "catalog")).size() == 20, "search-does-not-replace-browse-page");
            capture("02-blue-sky-found");
            for (String value : new String[]{"蔚", "蔚蓝", "蔚蓝天", "天空"}) { query(value); SystemClock.sleep(210); check(visible().size() == 1, "partial-name-" + value); }
            check(fetches.get() == 1, "typing-does-not-repeat-HTTP");
            ui(() -> call(activity, "selectPresetCategory", "胶片")); until(() -> visible().isEmpty(), "category-filter-applies");
            check(text().contains("没有匹配的预设"), "valid-empty-state"); capture("03-category-no-match");
            ui(() -> call(activity, "selectPresetCategory", "风景")); until(() -> visible().size() == 1, "category-restores-deep-match");
            check(fetches.get() == 1, "category-change-reuses-full-index");
            online = false; disk = true; ui(() -> call(activity, "retryOnlinePresetSearch"));
            until(() -> !Boolean.TRUE.equals(get(activity, "loadingOnlineSearch")), "offline-cache-load");
            check(text().contains("缓存 · 1 份匹配"), "cached-search-labeled"); capture("04-cached-search");
            disk = false; Object failedEngine = engine();
            ui(() -> { set(activity, "onlineSearch", failedEngine); set(activity, "onlineSearchSnapshot", null); set(activity, "onlineSearchAttempted", false); call(activity, "render"); });
            until(() -> !Boolean.TRUE.equals(get(activity, "loadingOnlineSearch")), "unavailable-search-completes");
            check(text().contains("暂时无法搜索"), "network-error-distinct-from-no-match");
            check(!text().contains("0 份匹配"), "unavailable-search-not-counted-as-zero"); capture("05-search-unavailable");
            online = true; ui(() -> call(activity, "retryOnlinePresetSearch"));
            until(() -> !Boolean.TRUE.equals(get(activity, "loadingOnlineSearch")) && visible().size() == 1, "retry-keeps-query-and-recovers");
            query(""); SystemClock.sleep(230); check(visible().size() == 0, "clearing-query-retains-selected-landscape-category");
            query("天空"); until(() -> visible().size() == 1, "restore-query-before-changing-category");
            ui(() -> call(activity, "selectPresetCategory", PresetCategories.ALL));
            query(""); SystemClock.sleep(230);
            check(visible().size() == 20, "clear-search-restores-browse-items");
            ui(() -> call(activity, "closeHomePresetSearch")); check(!Boolean.TRUE.equals(get(activity, "homePresetSearchExpanded")), "cancel-closes-search");
            for (int i = 0; i < 8; i++) {
                final boolean local = i % 2 == 0; ui(() -> call(activity, "selectPresetSource", local)); SystemClock.sleep(55);
                check(Boolean.valueOf(local).equals(get(activity, "localTab")), "source-switch-" + i);
            }
            SystemClock.sleep(350); check(!activity.isFinishing(), "rapid-source-switch-keeps-activity-alive"); capture("06-source-switch-return");
            report.put("scope", "Actual MainActivity with synthetic complete390 metadata, target at index389, first20 browse fixture. Covers loading, match, category, cache, unavailable/retry, clear/cancel, repeated source transitions. Emulator does not certify HarmonyOS hardware.");
        } catch (Throwable t) { failure = t; try { report.put("failure", android.util.Log.getStackTraceString(t)); } catch (Exception ignored) { } }
        finally {
            gate.countDown();
            try { if (activity != null) ui(() -> activity.finish()); if (appearance != null) cc.huevia.ui.AppAppearance.setMode(getTargetContext(), appearance); } catch (Throwable ignored) { }
            try { report.put("pass", failure == null); report.put("checks", checks); report.put("candidateSha256", args.getString("candidateSha256")); if (output != null) try (Writer w = new OutputStreamWriter(new FileOutputStream(new File(output, "report.json")), "UTF-8")) { w.write(report.toString(2)); } } catch (Exception ignored) { }
            Bundle result = new Bundle(); result.putString("result", report.toString()); finish(failure == null ? -1 : 0, result);
        }
    }
    private Object engine() throws Exception {
        Class<?> source = Class.forName("cc.huevia.library.OnlinePresetSearch$Source");
        Object provider = Proxy.newProxyInstance(source.getClassLoader(), new Class<?>[]{source}, (proxy, method, values) -> {
            if (method.getName().equals("fetch")) { fetches.incrementAndGet(); if (!gate.await(20, TimeUnit.SECONDS)) throw new AssertionError("gate timed out"); return result(online ? "ok" : "error", online); }
            if (method.getName().equals("cached")) return result(disk ? "cached" : "no_cache", disk);
            throw new AssertionError(method.getName());
        });
        Constructor<?> c = OnlinePresetSearch.class.getDeclaredConstructor(source, LongSupplier.class); c.setAccessible(true);
        return c.newInstance(provider, (LongSupplier)System::currentTimeMillis);
    }
    private Object result(String status, boolean present) throws Exception {
        Constructor<?> c = OnlinePresetRepository.CatalogResult.class.getDeclaredConstructor(String.class, String.class, List.class, boolean.class); c.setAccessible(true);
        return c.newInstance(status, "", present ? rows : Collections.emptyList(), status.equals("cached"));
    }
    private List<OnlinePreset> fixtures() throws Exception {
        List<OnlinePreset> result = new ArrayList<>();
        for (int i = 0; i < 390; i++) {
            Map<String,Object> m = new LinkedHashMap<>(); m.put("id", "qa171-" + i); m.put("name", i == 389 ? "蔚蓝天空" : "胶片 " + i);
            m.put("fileUrl", "https://example.invalid/qa171.ncp"); m.put("sha256", String.join("", Collections.nCopies(64, "0"))); m.put("byteLength", BigDecimal.valueOf(52));
            m.put("category", i == 389 ? "风景" : "胶片"); result.add(OnlinePreset.fromMap(m));
        } return result;
    }
    private void query(String value) throws Exception { ui(() -> ((EditText)get(activity, "homePresetSearchInput")).setText(value)); SystemClock.sleep(180); }
    private List<?> visible() throws Exception { return (List<?>)get(activity, "visiblePresets"); }
    private String text() { StringBuilder b = new StringBuilder(); runOnMainSync(() -> visibleText(activity.getWindow().getDecorView(), b)); return b.toString(); }
    private void visibleText(View v, StringBuilder b) { if (v.getVisibility() != View.VISIBLE) return; if (v instanceof TextView) b.append(((TextView)v).getText()).append(' '); if (v instanceof ViewGroup) for (int i = 0; i < ((ViewGroup)v).getChildCount(); i++) visibleText(((ViewGroup)v).getChildAt(i), b); }
    private String accessibilityText(android.view.accessibility.AccessibilityNodeInfo n) { if (n == null) return ""; StringBuilder b = new StringBuilder(); if (n.getText() != null) b.append(n.getText()).append(' '); for (int i = 0; i < n.getChildCount(); i++) b.append(accessibilityText(n.getChild(i))); return b.toString(); }
    private void capture(String name) throws Exception { waitForIdleSync(); report.put(name + "Text", text()); Bitmap b = getUiAutomation().takeScreenshot(); try (OutputStream s = new FileOutputStream(new File(output, name + ".png"))) { b.compress(Bitmap.CompressFormat.PNG, 100, s); } b.recycle(); check(!accessibilityText(getUiAutomation().getRootInActiveWindow()).contains("未响应"), "no-ANR-" + name); }
    private void check(boolean value, String name) throws Exception { checks.put(new JSONObject().put("name", name).put("pass", value)); if (!value) throw new AssertionError(name); }
    private interface Work { void run() throws Exception; } private interface Condition { boolean test() throws Exception; }
    private void ui(Work work) throws Exception { Throwable[] t = {null}; runOnMainSync(() -> { try { work.run(); } catch (Throwable e) { t[0] = e; } }); if (t[0] != null) throw new RuntimeException(t[0]); }
    private void until(Condition c, String name) throws Exception { long until = SystemClock.uptimeMillis() + 30000; while (SystemClock.uptimeMillis() < until) { if (c.test()) return; SystemClock.sleep(40); } throw new AssertionError("Timeout " + name); }
    private static Object get(Object target, String name) throws Exception { Field f = target.getClass().getDeclaredField(name); f.setAccessible(true); return f.get(target); }
    private static void set(Object target, String name, Object value) throws Exception { Field f = target.getClass().getDeclaredField(name); f.setAccessible(true); f.set(target, value); }
    private static Object call(Object target, String name, Object... args) throws Exception { for (Method m : target.getClass().getDeclaredMethods()) if (m.getName().equals(name) && m.getParameterCount() == args.length) { m.setAccessible(true); return m.invoke(target, args); } throw new NoSuchMethodException(name); }
}
