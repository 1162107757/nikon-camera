package cc.huevia.showcaseqa;

import android.app.*;
import android.content.*;
import android.graphics.*;
import android.graphics.drawable.BitmapDrawable;
import android.net.Uri;
import android.os.*;
import android.view.*;
import android.widget.*;
import java.io.*;
import java.lang.reflect.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.atomic.AtomicReference;
import org.json.*;

/** Loads production classes from the installed APK; generated NCPs and custom-template fixtures only. */
public final class ShowcaseProbe extends Instrumentation {
    private Activity activity;
    private ClassLoader loader;
    private Bundle args;
    private File output;
    private final JSONArray checks = new JSONArray();
    private final List<Object> records = new ArrayList<>();
    private final Map<String, byte[]> recipes = new LinkedHashMap<>();
    @Override public void onCreate(Bundle values) { super.onCreate(values); args = values == null ? new Bundle() : values; start(); }
    @Override public void onStart() {
        JSONObject report = new JSONObject(); Bundle result = new Bundle();
        try {
            check(Build.HARDWARE.equals("ranchu") || Build.HARDWARE.equals("goldfish"), "owned-emulator-only");
            loader = getTargetContext().getClassLoader(); String mode = args.getString("mode", "phone");
            output = new File(getTargetContext().getExternalFilesDir(null), "preset-showcase155/" + mode); output.mkdirs();
            stat("ui.AppAppearance", "setMode", getTargetContext(), mode.equals("dark") ? "dark" : "light");
            activity = startActivitySync(new Intent(Intent.ACTION_MAIN).setComponent(new ComponentName("cc.huevia", "cc.huevia.MainActivity"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK));
            until(() -> (Boolean) get(activity, "ready"), "main ready");
            Object gallery = get(activity, "presetShowcases"), template = get(activity, "presetPreviews");
            if (mode.equals("live")) { liveCatalog(gallery); report.put("pass", true); return; }
            JSONObject manifest;
            try (InputStream in = getTargetContext().getAssets().open("preset-showcase/manifest.json")) {
                manifest = new JSONObject(new String(in.readAllBytes(), java.nio.charset.StandardCharsets.UTF_8));
            }
            JSONArray photos = manifest.getJSONArray("items"); check(photos.length() == 10, "ten-bundled-licensed-photos");
            seed(gallery);
            if (mode.equals("phone")) validateSources(gallery, template, photos);
            settingsSources(gallery);
            ui(() -> { set(activity, "busy", false); set(activity, "catalogLoaded", true); set(activity, "localTab", true); call(activity, "switchRoot", 0); call(activity, "render"); });
            until(() -> visiblePreviewCount() >= 2, "visible gallery effects"); settle(); capture("01-gallery");
            check(((List<?>) get(activity, "visiblePresets")).size() == 10, "ten-source-fixtures-in-real-gallery");
            check(visiblePreviewCount() >= 2, "gallery-renders-photographic-previews");
            Object selected = records.get(0);
            Object expectedSource = call(gallery, "source", get(selected, "sha256"), get(selected, "category"));
            String firstKey = (String) get(expectedSource, "cacheKey");
            ui(() -> { set(activity, "detailId", get(selected, "id")); set(activity, "detailOnline", null); call(activity, "render"); });
            until(() -> get(activity, "activeComparison") != null && ((View) call(get(activity, "activeComparison"), "getButtonView")).isEnabled(), "detail effect and original");
            Object comparison = get(activity, "activeComparison");
            Bitmap original = (Bitmap) get(comparison, "original"), effect = (Bitmap) get(comparison, "effect");
            Bitmap expected = (Bitmap) call(gallery, "original", expectedSource);
            check(pixelHash(original).equals(pixelHash(expected)), "detail-original-is-matching-frozen-scene"); expected.recycle();
            check(original.getWidth() == effect.getWidth() && original.getHeight() == effect.getHeight(), "comparison-dimensions-match");
            settle(); capture("02-detail-effect");
            View button = (View) call(comparison, "getButtonView");
            ui(() -> button.performClick()); check((Boolean) get(comparison, "showingOriginal"), "comparison-shows-original"); capture("03-detail-original");
            ui(() -> button.performClick()); check(!(Boolean) get(comparison, "showingOriginal"), "comparison-restores-effect");
            ui(() -> { set(activity, "detailId", ""); call(activity, "render"); });
            check(firstKey.equals(get(call(gallery, "source", get(selected, "sha256"), get(selected, "category")), "cacheKey")), "returning-keeps-same-scene-and-key");
            report.put("pass", true);
        } catch (Throwable error) { try { report.put("pass", false).put("failure", error.toString()); } catch (Exception ignored) {} }
        finally {
            try {
                report.put("mode", args.getString("mode", "phone")).put("checks", checks)
                        .put("scope", "Installed production gallery only; generated valid NCP recipes and an owned custom-template PNG. No physical phone or camera-output claim.");
                if (output != null) try (OutputStream out = new FileOutputStream(new File(output, "report.json"))) { out.write(report.toString(2).getBytes(java.nio.charset.StandardCharsets.UTF_8)); }
                result.putString("stream", (report.optBoolean("pass") ? "PASS " : "FAIL ") + checks.length());
            } catch (Exception ignored) {}
            finish(report.optBoolean("pass") ? Activity.RESULT_OK : Activity.RESULT_CANCELED, result);
        }
    }

    private void settingsSources(Object gallery) throws Exception {
        check(((Object[]) call(gallery, "sources")).length == 10, "settings-gallery-source-set-matches-ten-photos");
        ui(() -> call(activity, "choosePreviewTemplate")); until(() -> activeHas("恢复内置摄影样片"), "settings action dialog");
        check(activeHas("恢复内置摄影样片"), "settings-restore-names-photography-set");
        clickActive("查看内置摄影样片"); settle(); capture("04-settings-sources");
        check(activeHas("山湖倒影"), "settings-lists-current-gallery-sources");
        clickActive("山湖倒影");
        until(() -> activeHas("山湖倒影 · 原图"), "settings actual photograph");
        check(activeHas("James Wheeler / Pexels"), "settings-photo-credit-matches-selected-source");
        capture("05-settings-original"); clickActive("关闭"); settle();
    }

    private void liveCatalog(Object gallery) throws Exception {
        ui(() -> { set(activity, "localTab", false); call(activity, "render"); call(activity, "loadCatalog", false); });
        until(() -> ((List<?>) get(activity, "catalog")).size() >= 2, "live online catalog read");
        until(() -> visiblePreviewCount() >= 2, "live online photographic effects");
        check(((List<?>) get(activity, "catalog")).size() >= 2, "real-online-catalog-populated");
        check(visiblePreviewCount() >= 2, "real-online-recipes-render-photographic-gallery");
        capture("01-live-online-gallery");
        Object remote = ((List<?>) get(activity, "catalog")).get(0);
        Object source = call(gallery, "source", get(remote, "sha256"), get(remote, "category"));
        ui(() -> { set(activity, "detailId", ""); set(activity, "detailOnline", remote); call(activity, "render"); });
        until(() -> get(activity, "activeComparison") != null && ((View) call(get(activity, "activeComparison"), "getButtonView")).isEnabled(), "live remote detail comparison");
        Bitmap expected = (Bitmap) call(gallery, "original", source);
        check(pixelHash(expected).equals(pixelHash((Bitmap) get(get(activity, "activeComparison"), "original"))), "live-remote-detail-holds-matching-source"); expected.recycle();
        capture("02-live-online-detail");
    }

    private void seed(Object gallery) throws Exception {
        Object library = get(activity, "library");
        for (int n = 0; recipes.size() < 10 && n < 500; n++) {
            byte[] bytes = cc.huevia.ncp.NcpCompatibilityFixtures.ncp();
            Arrays.fill(bytes, 16, 36, (byte) 0); byte[] name = ("SHOWCASE " + n).getBytes(java.nio.charset.StandardCharsets.US_ASCII);
            System.arraycopy(name, 0, bytes, 16, name.length);
            String sha = sha(bytes); Object source = call(gallery, "source", sha, ""); String id = (String) get(source, "id");
            if (recipes.containsKey(id)) continue;
            recipes.put(id, bytes);
            Object record = get(call(library, "importFile", "样片演示-" + get(source, "label") + ".NCP", bytes), "record"); records.add(record);
        }
        check(recipes.size() == 10, "all-ten-scenes-reachable-from-real-recipe-hashes");
    }

    private void validateSources(Object gallery, Object template, JSONArray photos) throws Exception {
        Set<String> originals = new HashSet<>();
        for (int i = 0; i < photos.length(); i++) {
            JSONObject item = photos.getJSONObject(i); byte[] raw;
            try (InputStream in = getTargetContext().getAssets().open("preset-showcase/" + item.getString("file"))) { raw = in.readAllBytes(); }
            check(sha(raw).equals(item.getString("sha256")) && raw.length == item.getInt("byteLength"), "bundled-photo-sha-" + i);
            byte[] bytes = recipes.get(item.getString("id")); Object source = call(gallery, "source", sha(bytes), "");
            check(item.getString("id").equals(get(source, "id")), "source-identity-" + i);
            Bitmap before = (Bitmap) call(gallery, "original", source, 320), coloured = (Bitmap) call(gallery, "render", bytes, source, 320);
            String beforeHash = pixelHash(before); originals.add(beforeHash);
            check(Math.max(before.getWidth(), before.getHeight()) <= 320, "bounded-decode-" + i);
            Object profile = stat("ncp.PresetPreviewProfiles", "fromPreset", bytes);
            int[] expected = (int[]) call(profile, "render", pixels(before), before.getWidth(), before.getHeight());
            check(Arrays.equals(expected, pixels(coloured)), "uses-existing-preset-colour-model-" + i);
            check(!beforeHash.equals(pixelHash(coloured)), "effect-is-not-raw-stock-photo-" + i);
            Bitmap after = (Bitmap) call(gallery, "original", source, 320);
            check(beforeHash.equals(pixelHash(after)), "original-pixels-remain-unchanged-" + i);
            save(coloured, "effect-" + item.getString("id") + ".png"); before.recycle(); coloured.recycle(); after.recycle();
        }
        check(originals.size() == 10, "ten-distinct-photographic-inputs");
        check(((Map<?, ?>) get(gallery, "pixels")).size() <= 3, "source-pixel-cache-bounded-to-three");
        Object old = call(gallery, "source", sha(recipes.values().iterator().next()), "");
        Bitmap fixture = Bitmap.createBitmap(192, 128, Bitmap.Config.ARGB_8888); new Canvas(fixture).drawColor(Color.rgb(90, 140, 185));
        File custom = new File(getTargetContext().getCacheDir(), "showcase-template-fixture.png");
        try (OutputStream out = new FileOutputStream(custom)) { fixture.compress(Bitmap.CompressFormat.PNG, 100, out); } fixture.recycle();
        call(template, "setTemplate", Uri.fromFile(custom));
        byte[] bytes = recipes.values().iterator().next(); Object source = call(gallery, "source", sha(bytes), "人像");
        check((Boolean) get(source, "custom") && !(Boolean) call(gallery, "isCurrent", old), "custom-template-invalidates-old-source");
        check(((Object[]) call(gallery, "sources")).length == 1, "settings-current-source-set-respects-custom-template");
        Bitmap shown = (Bitmap) call(gallery, "original", source), reference = (Bitmap) call(template, "originalTemplate");
        check(pixelHash(shown).equals(pixelHash(reference)), "gallery-respects-user-custom-template"); shown.recycle(); reference.recycle();
        shown = (Bitmap) call(gallery, "render", bytes, source, 320); reference = (Bitmap) call(template, "render", bytes, 320);
        check(pixelHash(shown).equals(pixelHash(reference)), "custom-template-effects-preserved"); shown.recycle(); reference.recycle();
        boolean rejected = false; try { call(gallery, "original", old); } catch (Exception stale) { rejected = true; }
        check(rejected, "stale-source-never-pairs-with-new-original");
        call(template, "resetTemplate"); check(!(Boolean) call(gallery, "isCurrent", source), "reset-invalidates-custom-source");
        Bitmap builtin = (Bitmap) call(template, "originalTemplate");
        check(builtin.getWidth() > 0, "legacy-template-renderer-still-available-for-editor-selection"); builtin.recycle();
    }

    private int visiblePreviewCount() throws Exception { AtomicReference<Integer> count = new AtomicReference<>(0); ui(() -> count.set(countPreviews(activity.getWindow().getDecorView()))); return count.get(); }
    private boolean activeHas(String text) { android.view.accessibility.AccessibilityNodeInfo root = getUiAutomation().getRootInActiveWindow(); return root != null && !root.findAccessibilityNodeInfosByText(text).isEmpty(); }
    private void clickActive(String text) throws Exception { until(() -> activeHas(text), "native action " + text); android.view.accessibility.AccessibilityNodeInfo root = getUiAutomation().getRootInActiveWindow(); for (android.view.accessibility.AccessibilityNodeInfo node : root.findAccessibilityNodeInfosByText(text)) if (node.getText() != null && text.contentEquals(node.getText())) { Rect bounds = new Rect(); node.getBoundsInScreen(bounds); if (!bounds.isEmpty()) { long now = SystemClock.uptimeMillis(); MotionEvent down = MotionEvent.obtain(now, now, MotionEvent.ACTION_DOWN, bounds.exactCenterX(), bounds.exactCenterY(), 0), up = MotionEvent.obtain(now, now + 60, MotionEvent.ACTION_UP, bounds.exactCenterX(), bounds.exactCenterY(), 0); try { sendPointerSync(down); sendPointerSync(up); } finally { down.recycle(); up.recycle(); } return; } } throw new AssertionError("Missing native action: " + text); }
    private int countPreviews(View view) { int n = view instanceof ImageView && view.getTag() instanceof String && ((String) view.getTag()).startsWith("sim:") && ((ImageView) view).getDrawable() instanceof BitmapDrawable ? 1 : 0; if (view instanceof ViewGroup) for (int i = 0; i < ((ViewGroup) view).getChildCount(); i++) n += countPreviews(((ViewGroup) view).getChildAt(i)); return n; }
    private int[] pixels(Bitmap bitmap) { int[] p = new int[bitmap.getWidth() * bitmap.getHeight()]; bitmap.getPixels(p, 0, bitmap.getWidth(), 0, 0, bitmap.getWidth(), bitmap.getHeight()); return p; }
    private String pixelHash(Bitmap bitmap) throws Exception { java.nio.ByteBuffer data = java.nio.ByteBuffer.allocate(bitmap.getWidth() * bitmap.getHeight() * 4); for (int p : pixels(bitmap)) data.putInt(p); return sha(data.array()); }
    private String sha(byte[] data) throws Exception { StringBuilder out = new StringBuilder(); for (byte value : MessageDigest.getInstance("SHA-256").digest(data)) out.append(String.format(Locale.ROOT, "%02x", value & 255)); return out.toString(); }
    private void capture(String name) throws Exception { settle(); Bitmap screenshot = getUiAutomation().takeScreenshot(); save(screenshot, name + ".png"); screenshot.recycle(); }
    private void save(Bitmap bitmap, String name) throws Exception { try (OutputStream out = new FileOutputStream(new File(output, name))) { bitmap.compress(Bitmap.CompressFormat.PNG, 100, out); } }
    private interface Work { void run() throws Exception; } private interface Condition { boolean test() throws Exception; }
    private void until(Condition condition, String label) throws Exception { long end = SystemClock.uptimeMillis() + 35000; while (SystemClock.uptimeMillis() < end) { if (condition.test()) return; SystemClock.sleep(50); } throw new AssertionError("Timeout " + label); }
    private void settle() throws Exception { waitForIdleSync(); SystemClock.sleep(220); }
    private void check(boolean pass, String label) throws Exception { checks.put(new JSONObject().put("name", label).put("pass", pass)); if (!pass) throw new AssertionError(label); }
    private void ui(Work work) throws Exception { AtomicReference<Throwable> failure = new AtomicReference<>(); runOnMainSync(() -> { try { work.run(); } catch (Throwable error) { failure.set(error); } }); if (failure.get() != null) throw new RuntimeException(failure.get()); }
    private Class<?> cls(String name) throws Exception { return loader.loadClass("cc.huevia." + name); }
    private Field field(Class<?> type, String name) throws Exception { for (Class<?> c = type; c != null; c = c.getSuperclass()) try { Field f = c.getDeclaredField(name); f.setAccessible(true); return f; } catch (NoSuchFieldException ignored) {} throw new NoSuchFieldException(name); }
    private Object get(Object target, String name) throws Exception { return field(target.getClass(), name).get(target); }
    private void set(Object target, String name, Object value) throws Exception { field(target.getClass(), name).set(target, value); }
    private Object call(Object target, String name, Object... values) throws Exception { return invoke(target.getClass(), target, name, values); }
    private Object stat(String type, String name, Object... values) throws Exception { return invoke(cls(type), null, name, values); }
    private Object invoke(Class<?> type, Object target, String name, Object[] values) throws Exception { for (Class<?> c = type; c != null; c = c.getSuperclass()) for (Method m : c.getDeclaredMethods()) if (m.getName().equals(name) && m.getParameterCount() == values.length) { m.setAccessible(true); try { return m.invoke(target, values); } catch (IllegalArgumentException mismatch) {} catch (InvocationTargetException error) { throw new RuntimeException(error.getCause()); } } throw new NoSuchMethodException(name); }
}
