package cc.huevia.np3inspectionqa;

import android.app.*;
import android.content.*;
import android.graphics.*;
import android.os.*;
import android.view.*;
import android.view.accessibility.AccessibilityNodeInfo;
import android.widget.*;
import java.io.*;
import java.lang.reflect.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.atomic.AtomicReference;
import org.json.*;

/** Tests the installed APK, its real library, parameter entry and dialog. Synthetic NP3 only. */
public final class Np3InspectionProbe extends Instrumentation {
    private Activity activity;
    private ClassLoader loader;
    private Bundle args;
    private File output;
    private final JSONArray checks = new JSONArray();
    private final List<Object> added = new ArrayList<>();
    private Object library;
    private String originalMode;

    @Override public void onCreate(Bundle values) { super.onCreate(values); args = values; start(); }
    @Override public void onStart() {
        JSONObject report = new JSONObject(); Bundle result = new Bundle();
        try {
            check(Build.HARDWARE.equals("ranchu") || Build.HARDWARE.equals("goldfish"), "owned-emulator-only");
            check(Build.VERSION.SDK_INT >= 29, "window-inspection-api-supported");
            String apkSha = digest(new File(getTargetContext().getApplicationInfo().sourceDir));
            check(apkSha.equals(args.getString("apkSha256")), "installed-apk-hash-bound");
            check(getTargetContext().getPackageManager().getPackageInfo("cc.huevia", 0).getLongVersionCode() == 160, "version-160");
            loader = getTargetContext().getClassLoader(); String mode = args.getString("mode", "phone");
            output = new File(getTargetContext().getExternalFilesDir(null), "np3-inspection160/" + args.getString("runId", "local") + "/" + mode); output.mkdirs();
            originalMode = (String) invoke(loader.loadClass("cc.huevia.ui.AppAppearance"), null, "mode", getTargetContext());
            invoke(loader.loadClass("cc.huevia.ui.AppAppearance"), null, "setMode", getTargetContext(), mode.equals("dark") ? "dark" : "light");
            activity = startActivitySync(new Intent(Intent.ACTION_MAIN).setComponent(new ComponentName("cc.huevia", "cc.huevia.MainActivity"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK));
            until(() -> Boolean.TRUE.equals(get(activity, "ready")), "main-ready"); library = get(activity, "library");
            byte[] recipe = fixture(); Object record = add("qa-np3-document", recipe);
            check("NP3".equals(get(record, "fileFormat")), "extensionless-np3-detected-in-product");
            check(Arrays.equals(recipe, (byte[]) call(library, "readPreset", get(record, "id"))), "source-bytes-preserved");
            Object details = invoke(loader.loadClass("cc.huevia.ncp.Np3PresetDetails"), null, "read", recipe);
            check(Boolean.TRUE.equals(get(details, "previewSupported")), "installed-strict-reader-accepts-fixture");
            check(((List<?>) get(details, "groups")).size() == 5, "installed-parser-has-five-parameter-groups");
            detail(record); revealEntry(); capture("01-preset-entry"); click("查看 NP3 参数");
            until(() -> activeHas("NP3 参数"), "parameter-dialog-opened-by-entry");
            check(activeHas("关闭 NP3 参数") && !activeHas("完成"), "compact-header-close-replaces-footer-button");
            check(activeHas("参数已解析"), "successful-parse-status-visible");
            check(activeHas("Flexible Color"), "base-name-visible");
            check(activeHas("锐化"), "detail-amounts-visible");
            inspectDialog(); capture("02-parameters");
            click("色调"); check(activeHas("对比度"), "tone-controls-reachable"); inspectDialog(); capture("03-tone");
            click("混色"); check(activeHas("洋红"), "all-eight-colors-reachable"); inspectDialog(); capture("04-mixer");
            click("分级"); check(activeHas("混合") && activeHas("平衡"), "grading-and-blend-reachable");
            inspectDialog(); capture("05-grading"); clickDescription("关闭 NP3 参数");
            until(() -> !activeHas("NP3 参数") || activeHas("查看 NP3 参数"), "parameter-dialog-dismissed");
            if (mode.equals("phone")) {
                click("查看 NP3 参数"); until(() -> activeHas("关闭 NP3 参数"), "reopened-before-back");
                sendKeyDownUpSync(KeyEvent.KEYCODE_BACK); settle();
                check(!activeHas("关闭 NP3 参数"), "back-dismisses-parameter-dialog");
                click("查看 NP3 参数"); until(() -> activeHas("关闭 NP3 参数"), "reopened-before-mask-tap");
                Rect dialogBounds = new Rect(); getUiAutomation().getRootInActiveWindow().getBoundsInScreen(dialogBounds);
                check(dialogBounds.top > 180, "mask-test-point-is-above-dialog-and-below-status-bar");
                // Stay away from Android's edge-back gesture regions.
                // Accessibility excludes the window's shadow/inset. Allow more than
                // that inset so the touch is outside the actual window as well.
                tap(dialogBounds.exactCenterX(), dialogBounds.top - 150);
                until(() -> !activeHas("关闭 NP3 参数"), "mask-tap-dismisses-parameter-dialog");
                check(!activeHas("关闭 NP3 参数"), "mask-tap-dismisses-parameter-dialog");
                byte[] unknown = fixture(); field(unknown, 3, 0, 8); field(unknown, 3, 1, 2);
                Object unsupported = add("qa-unknown.NP3", unknown); detail(unsupported); revealEntry(); click("查看 NP3 参数");
                until(() -> activeHas("手机预览暂不支持"), "unsupported-dialog");
                check(activeHas("0x0802"), "unknown-base-is-not-guessed");
                check(!activeHas("混色器"), "unsupported-numeric-values-not-published");
                check(Arrays.equals(unknown, (byte[]) call(library, "readPreset", get(unsupported, "id"))), "unsupported-source-still-intact");
                inspectDialog(); capture("06-unsupported"); clickDescription("关闭 NP3 参数");
            }
            report.put("pass", true).put("apkSha256", apkSha);
        } catch (Throwable failure) {
            try { report.put("pass", false).put("failure", failure.toString()); capture("failure"); } catch (Exception ignored) {}
        } finally {
            try {
                for (Object record : added) call(library, "remove", get(record, "id"));
                if (originalMode != null) invoke(loader.loadClass("cc.huevia.ui.AppAppearance"), null, "setMode", getTargetContext(), originalMode);
                if (activity != null) ui(() -> activity.finish());
                report.put("checks", checks).put("mode", args.getString("mode", "phone"))
                        .put("scope", "Installed APK on an owned offline emulator. Generated synthetic NP3 files; source storage, real detail-entry touch, compact parameter dialog, scroll and unsupported-state checks. No camera write or Nikon color-equivalence claim.");
                if (output != null) try (OutputStream out = new FileOutputStream(new File(output, "report.json"))) { out.write(report.toString(2).getBytes(StandardCharsets.UTF_8)); }
                result.putString("stream", (report.optBoolean("pass") ? "PASS " : "FAIL ") + checks.length() + " NP3 device checks; " + report.optString("failure"));
            } catch (Exception failure) { result.putString("stream", "FAIL cleanup/report: " + failure); }
            finish(report.optBoolean("pass") ? Activity.RESULT_OK : Activity.RESULT_CANCELED, result);
        }
    }

    private Object add(String name, byte[] bytes) throws Exception {
        Object outcome = call(library, "importFile", name, bytes); Object record = get(outcome, "record");
        if (Boolean.TRUE.equals(get(outcome, "added"))) added.add(record); return record;
    }
    private void detail(Object record) throws Exception {
        ui(() -> {
            set(activity, "busy", false); set(activity, "catalogLoaded", true); set(activity, "localTab", true);
            call(activity, "switchRoot", 0); set(activity, "detailId", get(record, "id")); set(activity, "detailOnline", null); call(activity, "render");
        });
        until(() -> findText(activity.getWindow().getDecorView(), "查看 NP3 参数") != null, "parameter-entry-exists");
    }
    private void revealEntry() throws Exception {
        ui(() -> {
            View entry = findText(activity.getWindow().getDecorView(), "查看 NP3 参数");
            entry.requestRectangleOnScreen(new Rect(0, 0, Math.max(1, entry.getWidth()), Math.max(1, entry.getHeight())), true);
        }); settle();
    }
    private void scrollDialogBottom() throws Exception {
        ui(() -> {
            for (View root : android.view.inspector.WindowInspector.getGlobalWindowViews())
                if (root.hasWindowFocus()) { ScrollView scroll = findScroll(root); if (scroll != null) scroll.fullScroll(View.FOCUS_DOWN); }
        }); settle();
    }
    private ScrollView findScroll(View view) {
        if (view instanceof ScrollView) return (ScrollView) view;
        if (view instanceof android.view.ViewGroup) for (int i = 0; i < ((android.view.ViewGroup) view).getChildCount(); i++) {
            ScrollView found = findScroll(((android.view.ViewGroup) view).getChildAt(i)); if (found != null) return found;
        }
        return null;
    }
    private void inspectDialog() throws Exception {
        ui(() -> {
            boolean found = false;
            for (View root : android.view.inspector.WindowInspector.getGlobalWindowViews()) if (root.hasWindowFocus() && findText(root, "NP3 参数") != null) {
                found = true; checkText(root); check(root.getWidth() <= getTargetContext().getResources().getDisplayMetrics().widthPixels, "dialog-within-screen");
            }
            check(found, "actual-dialog-window-inspected");
        });
    }
    private void checkText(View view) throws Exception {
        if (view instanceof TextView && view.getVisibility() == View.VISIBLE) {
            TextView text = (TextView) view;
            if (text.getLayout() != null && !text.getText().toString().isEmpty()) {
                check(text.getWidth() > 0, "nonempty-text-has-width");
                for (int i = 0; i < text.getLayout().getLineCount(); i++) {
                    check(text.getLayout().getEllipsisCount(i) == 0, "no-ellipsized-parameter-text");
                    check(text.getLayout().getLineWidth(i) <= text.getWidth() - text.getPaddingLeft() - text.getPaddingRight() + 2, "text-fits-cell");
                }
                if (!"×".contentEquals(text.getText())) check(text.getTextSize() / text.getResources().getDisplayMetrics().scaledDensity <= 16.1f, "compact-text-scale");
            }
        }
        if (view instanceof android.view.ViewGroup) for (int i = 0; i < ((android.view.ViewGroup) view).getChildCount(); i++) checkText(((android.view.ViewGroup) view).getChildAt(i));
    }
    private View findText(View view, String value) {
        if (view instanceof TextView && value.contentEquals(((TextView) view).getText())) return view;
        if (view instanceof android.view.ViewGroup) for (int i = 0; i < ((android.view.ViewGroup) view).getChildCount(); i++) {
            View found = findText(((android.view.ViewGroup) view).getChildAt(i), value); if (found != null) return found;
        }
        return null;
    }
    private boolean activeHas(String text) { AccessibilityNodeInfo root = getUiAutomation().getRootInActiveWindow(); return root != null && !root.findAccessibilityNodeInfosByText(text).isEmpty(); }
    private void click(String text) throws Exception {
        until(() -> activeHas(text), "touch-target " + text); AccessibilityNodeInfo root = getUiAutomation().getRootInActiveWindow();
        for (AccessibilityNodeInfo node : root.findAccessibilityNodeInfosByText(text)) if (node.getText() != null && text.contentEquals(node.getText()) && node.isVisibleToUser()) {
            Rect bounds = new Rect(); node.getBoundsInScreen(bounds); if (bounds.isEmpty()) continue;
            long now = SystemClock.uptimeMillis(); MotionEvent down = MotionEvent.obtain(now, now, MotionEvent.ACTION_DOWN, bounds.exactCenterX(), bounds.exactCenterY(), 0);
            MotionEvent up = MotionEvent.obtain(now, now + 60, MotionEvent.ACTION_UP, bounds.exactCenterX(), bounds.exactCenterY(), 0);
            try { sendPointerSync(down); sendPointerSync(up); } finally { down.recycle(); up.recycle(); } settle(); return;
        }
        throw new AssertionError("No visible touch target: " + text);
    }
    private void clickDescription(String description) throws Exception {
        until(() -> activeHas(description), "close action available"); AccessibilityNodeInfo root = getUiAutomation().getRootInActiveWindow();
        for (AccessibilityNodeInfo node : root.findAccessibilityNodeInfosByText(description)) {
            if (!description.contentEquals(node.getContentDescription()) || !node.isVisibleToUser()) continue;
            Rect bounds = new Rect(); node.getBoundsInScreen(bounds);
            check(bounds.width() >= 44 * getTargetContext().getResources().getDisplayMetrics().density - 1, "close-keeps-44dp-hit-area");
            long now = SystemClock.uptimeMillis(); MotionEvent down = MotionEvent.obtain(now, now, MotionEvent.ACTION_DOWN, bounds.exactCenterX(), bounds.exactCenterY(), 0);
            MotionEvent up = MotionEvent.obtain(now, now + 60, MotionEvent.ACTION_UP, bounds.exactCenterX(), bounds.exactCenterY(), 0);
            try { sendPointerSync(down); sendPointerSync(up); } finally { down.recycle(); up.recycle(); } settle(); return;
        }
        throw new AssertionError("Close action not visible");
    }
    private void tap(float x, float y) throws Exception {
        long now = SystemClock.uptimeMillis();
        MotionEvent down = MotionEvent.obtain(now, now, MotionEvent.ACTION_DOWN, x, y, 0);
        MotionEvent up = MotionEvent.obtain(now, now + 60, MotionEvent.ACTION_UP, x, y, 0);
        // The dimmed area is outside the dialog's target window; UiAutomation is the
        // supported device-level injection path for an actual outside touch.
        try {
            check(getUiAutomation().injectInputEvent(down, true), "mask-down-injected");
            check(getUiAutomation().injectInputEvent(up, true), "mask-up-injected");
        } finally { down.recycle(); up.recycle(); } settle();
    }
    private void capture(String name) throws Exception {
        settle(); Bitmap screenshot = getUiAutomation().takeScreenshot();
        try (OutputStream out = new FileOutputStream(new File(output, name + ".png"))) { screenshot.compress(Bitmap.CompressFormat.PNG, 100, out); }
        finally { screenshot.recycle(); }
    }
    private byte[] fixture() throws Exception {
        ByteArrayOutputStream out = new ByteArrayOutputStream(); out.write(new byte[] {'N', 'C', 'P', 0});
        for (int i = 1; i <= 32; i++) {
            int size = i == 1 ? 4 : i == 2 || i == 32 ? 20 : i == 31 ? 28 : 2; byte[] data = new byte[size];
            if (i == 1) data = "0310".getBytes(StandardCharsets.US_ASCII);
            else if (i == 2) System.arraycopy("QA NP3 160".getBytes(StandardCharsets.US_ASCII), 0, data, 0, 10);
            else if (i == 3) data[1] = 32;
            else if (i == 4) { }
            else if (i == 6 || i == 7 || i == 22) { data[0] = (byte) (i == 6 ? 142 : i == 7 ? 134 : 140); data[1] = 4; }
            else if (i == 8 || i == 9 || i == 10 || i == 11 || i == 14 || i == 23 || i == 24) { data[0] = (byte) 255; data[1] = 4; }
            else if (i == 12 || i == 13) data[0] = (byte) 255;
            else if (i == 20) { data[0] = (byte) 129; data[1] = 1; }
            else if (i == 21) { data[0] = (byte) 255; data[1] = 10; }
            else if (i >= 25 && i <= 30) { data[0] = (byte) (i == 25 ? 143 : i == 30 ? 108 : 128); data[1] = 1; }
            else if (i == 31) { Arrays.fill(data, 0, 24, (byte) 128); data[0] = (byte) 140; data[2] = (byte) 117; data[24] = data[25] = data[26] = 1; }
            else if (i == 32) { for (int j = 0; j < 3; j++) data[j * 4] = data[j * 4 + 2] = data[j * 4 + 3] = (byte) 128; data[12] = data[13] = data[14] = data[17] = data[19] = 1; data[16] = (byte) 178; data[18] = (byte) 128; }
            else { data[0] = (byte) 255; data[1] = 1; }
            u32(out, i * 256); u32(out, size); out.write(data);
        }
        u32(out, 0); return out.toByteArray();
    }
    private static void field(byte[] bytes, int index, int position, int value) { int offset = 4; for (int i = 1; i < index; i++) offset += 8 + (bytes[offset + 7] & 255); bytes[offset + 8 + position] = (byte) value; }
    private static void u32(ByteArrayOutputStream out, int n) { out.write(n >>> 24); out.write(n >>> 16); out.write(n >>> 8); out.write(n); }
    private String digest(File file) throws Exception { MessageDigest hash = MessageDigest.getInstance("SHA-256"); try (InputStream in = new FileInputStream(file)) { byte[] data = new byte[65536]; int n; while ((n = in.read(data)) != -1) hash.update(data, 0, n); } StringBuilder text = new StringBuilder(); for (byte b : hash.digest()) text.append(String.format(Locale.ROOT, "%02x", b & 255)); return text.toString(); }
    private Field field(Class<?> type, String name) throws Exception { for (Class<?> current = type; current != null; current = current.getSuperclass()) try { Field field = current.getDeclaredField(name); field.setAccessible(true); return field; } catch (NoSuchFieldException ignored) {} throw new NoSuchFieldException(name); }
    private Object get(Object owner, String name) throws Exception { return field(owner.getClass(), name).get(owner); }
    private void set(Object owner, String name, Object value) throws Exception { field(owner.getClass(), name).set(owner, value); }
    private Object call(Object owner, String name, Object... args) throws Exception { return invoke(owner.getClass(), owner, name, args); }
    private Object invoke(Class<?> type, Object owner, String name, Object... args) throws Exception {
        for (Class<?> current = type; current != null; current = current.getSuperclass()) for (Method method : current.getDeclaredMethods()) if (method.getName().equals(name) && method.getParameterCount() == args.length) {
            Class<?>[] types = method.getParameterTypes(); boolean match = true;
            for (int i = 0; i < args.length; i++) if (args[i] != null && !types[i].isPrimitive() && !types[i].isAssignableFrom(args[i].getClass())) match = false;
            if (match) { method.setAccessible(true); return method.invoke(owner, args); }
        }
        throw new NoSuchMethodException(name);
    }
    private void check(boolean condition, String label) { if (!condition) throw new AssertionError(label); checks.put(label); }
    private interface Condition { boolean test() throws Exception; }
    private interface Work { void run() throws Exception; }
    private void until(Condition condition, String label) throws Exception { long end = SystemClock.uptimeMillis() + 30000; while (SystemClock.uptimeMillis() < end) { if (condition.test()) return; SystemClock.sleep(60); } throw new AssertionError("Timeout " + label); }
    private void ui(Work work) throws Exception { AtomicReference<Throwable> failure = new AtomicReference<>(); runOnMainSync(() -> { try { work.run(); } catch (Throwable error) { failure.set(error); } }); if (failure.get() != null) throw new RuntimeException(failure.get()); }
    private void settle() { waitForIdleSync(); SystemClock.sleep(250); }
}
