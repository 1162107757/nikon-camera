package cc.huevia.updateqa;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.Instrumentation;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.res.Configuration;
import android.graphics.Bitmap;
import android.graphics.Rect;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.ProgressBar;
import android.widget.ScrollView;
import android.widget.TextView;
import cc.huevia.ui.UiPalette;
import cc.huevia.ui.UpdatePanel;
import cc.huevia.updates.AppUpdateManager;
import java.io.File;
import java.io.FileOutputStream;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.AbstractExecutorService;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import org.json.JSONArray;
import org.json.JSONObject;

/** Component test. It never starts the app's MainActivity implementation or queues network/install work. */
public final class UpdatePromptProbe extends Instrumentation {
    private static final String ID = "daddec00-0000-0000-0000-000000000001";
    private static final String OTHER_ID = "daddec00-0000-0000-0000-000000000002";
    private static final String HASH = "a".repeat(64);
    private static float fontScale = 1f;
    private final JSONArray checks = new JSONArray();
    private final JSONArray screenshots = new JSONArray();
    private final JSONArray observations = new JSONArray();
    private Bundle arguments;
    private ProbeActivity activity;
    private File output;
    private Map<String, ?> managerBefore, promptBefore;
    private SharedPreferences managerPrefs, promptPrefs;
    private Throwable failure;
    private GuardExecutor guard;
    private int redirectedActivities;

    @Override public void onCreate(Bundle arguments) {
        this.arguments = arguments;
        fontScale = Float.parseFloat(arguments.getString("fontScale", "1.0"));
        start();
    }

    @Override public Activity newActivity(ClassLoader loader, String className, Intent intent)
            throws InstantiationException, IllegalAccessException, ClassNotFoundException {
        if (className.equals("cc.huevia.MainActivity")) {
            redirectedActivities++;
            return new ProbeActivity();
        }
        return super.newActivity(loader, className, intent);
    }

    @Override public void onStart() {
        try {
            require("owned-emulator-only", android.os.Build.HARDWARE.contains("ranchu") || android.os.Build.HARDWARE.contains("goldfish"));
            require("font-scale-supported", fontScale == 1f || fontScale == 1.3f);
            output = new File(getTargetContext().getExternalFilesDir(null), "update-prompt-qa/" + arguments.getString("runId"));
            require("output-created", output.mkdirs() || output.isDirectory());
            managerPrefs = getTargetContext().getSharedPreferences(AppUpdateManager.PREFS, Context.MODE_PRIVATE);
            promptPrefs = getTargetContext().getSharedPreferences("app-update-prompts", Context.MODE_PRIVATE);
            managerBefore = new HashMap<>(managerPrefs.getAll()); promptBefore = new HashMap<>(promptPrefs.getAll());
            require("manager-prefs-cleared", managerPrefs.edit().clear().commit());
            require("prompt-prefs-cleared", promptPrefs.edit().clear().commit());
            Intent launch = new Intent().setClassName("cc.huevia", "cc.huevia.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
            activity = (ProbeActivity) startActivitySync(launch);
            require("main-activity-replaced-before-onCreate", redirectedActivities == 1 && activity != null);
            ui(() -> {
                activity.initialise();
                guard = new GuardExecutor();
                ExecutorService original = (ExecutorService) field(activity.manager, "worker");
                original.shutdownNow(); setField(activity.manager, "worker", guard);
                suppressAutomaticMetadata();
            });
            ordinaryFlow();
            mandatoryFlow();
            require("no-worker-task-network-or-installer", guard.attempts == 0);
            require("no-host-install-or-feedback", activity.installRequests == 0 && activity.feedbacks == 0);
            require("activity-still-open", !activity.isFinishing());
        } catch (Throwable problem) { failure = problem; }
        finally {
            try {
                if (activity != null) ui(() -> { if (activity.panel != null) activity.panel.close(); activity.finish(); });
                if (managerPrefs != null && managerBefore != null) restore(managerPrefs, managerBefore);
                if (promptPrefs != null && promptBefore != null) restore(promptPrefs, promptBefore);
                require("preferences-restored", managerPrefs == null || same(managerBefore, managerPrefs.getAll()) && same(promptBefore, promptPrefs.getAll()));
            } catch (Throwable cleanup) { if (failure == null) failure = cleanup; else failure.addSuppressed(cleanup); }
            try { writeReport(); } catch (Throwable write) { if (failure == null) failure = write; }
            Bundle result = new Bundle(); result.putString("report", output == null ? "" : new File(output, "report.json").getAbsolutePath());
            result.putString("summary", failure == null ? "PASS " + checks.length() + " checks" : "FAIL " + failure);
            finish(failure == null ? Activity.RESULT_OK : Activity.RESULT_CANCELED, result);
        }
    }

    private void ordinaryFlow() throws Exception {
        ui(() -> {
            activity.idle = false; activity.ready = false;
            seed(false, ID, shortNotes(), 1);
            activity.panel.onResume(); listener().available();
            require("ordinary-pending-while-busy", prompt() == null);
        });
        ui(() -> { activity.idle = true; activity.ready = true; suppressAutomaticMetadata(); activity.panel.automaticCheck(); });
        waitForIdleSync();
        ui(() -> {
            AlertDialog dialog = showing("ordinary-new-version-dialog");
            require("ordinary-title", textIn(dialog.getWindow().getDecorView(), "发现新版本"));
            require("ordinary-later", "稍后".contentEquals(dialog.getButton(AlertDialog.BUTTON_NEGATIVE).getText()));
            require("ordinary-version-visible", tagText(dialog, "update-prompt-version").contains("99.0.1"));
            require("ordinary-notes-complete", shortNotes().equals(tagText(dialog, "update-prompt-notes")));
            require("ordinary-not-blocking", !activity.panel.isMandatoryBlocking());
            assertLayout(dialog, "ordinary");
        });
        screenshot("01-ordinary");
        ui(() -> prompt().getButton(AlertDialog.BUTTON_NEGATIVE).performClick());
        waitForIdleSync();
        ui(() -> {
            require("ordinary-later-dismissed", prompt() == null);
            listener().available(); listener().changed(); activity.panel.automaticCheck();
            require("ordinary-repeat-deduplicated", prompt() == null);
            activity.panel.onPause(); activity.panel.onResume();
            require("ordinary-resume-deduplicated", prompt() == null);
            // A different artifact is a new update, even inside the reminder interval.
            seed(false, OTHER_ID, shortNotes(), 2); listener().available();
            showing("ordinary-new-artifact-prompts");
            prompt().onBackPressed();
        });
        waitForIdleSync();
        ui(() -> require("ordinary-back-dismisses", prompt() == null));
        ui(() -> {
            promptPrefs.edit().clear().commit(); seed(false, ID, shortNotes(), 7);
            activity.manager.checking = true; listener().available();
            require("ordinary-checking-does-not-pop", prompt() == null);
            activity.manager.checking = false; activity.manager.downloading = true; listener().available();
            require("ordinary-downloading-does-not-pop", prompt() == null);
            activity.manager.downloading = false; activity.manager.verifying = true; listener().available();
            require("ordinary-verifying-does-not-pop", prompt() == null);
            activity.manager.verifying = false; listener().available();
            showing("ordinary-ready-after-worker-phase"); prompt().onBackPressed();
        });
        waitForIdleSync();
    }

    private void mandatoryFlow() throws Exception {
        ui(() -> {
            activity.idle = false; activity.ready = false;
            seed(true, ID, longNotes(), 3); listener().available();
            require("required-busy-gate-active", activity.panel.isMandatoryBlocking());
            require("required-busy-dialog-pending", prompt() == null);
            activity.panel.goBack();
            require("required-back-does-not-release-gate", activity.panel.isMandatoryBlocking());
            activity.ready = true; suppressAutomaticMetadata(); activity.panel.automaticCheck();
        });
        waitForIdleSync();
        ui(() -> {
            AlertDialog dialog = showing("required-dialog-on-safe-host");
            require("required-page-open", activity.panel.isOpen());
            require("required-title", textIn(dialog.getWindow().getDecorView(), "需要更新"));
            require("required-no-later", !textIn(dialog.getWindow().getDecorView(), "稍后"));
            require("required-exit-app", "退出应用".contentEquals(dialog.getButton(AlertDialog.BUTTON_NEGATIVE).getText()));
            require("required-recheck", "重新检查".contentEquals(dialog.getButton(AlertDialog.BUTTON_NEUTRAL).getText()));
            require("required-message", "更新后可继续使用".equals(tagText(dialog, "update-required-message")));
            require("required-long-notes-not-truncated", longNotes().equals(tagText(dialog, "update-prompt-notes")));
            dialog.onBackPressed();
            require("required-back-cannot-dismiss", dialog.isShowing());
            MotionEvent outside = MotionEvent.obtain(SystemClock.uptimeMillis(), SystemClock.uptimeMillis(), MotionEvent.ACTION_OUTSIDE, -100, -100, 0);
            try { dialog.onTouchEvent(outside); } finally { outside.recycle(); }
            require("required-outside-cannot-dismiss", dialog.isShowing());
            activity.panel.goBack();
            require("required-goBack-stays-open", activity.panel.isOpen() && activity.panel.isMandatoryBlocking() && dialog.isShowing());
            assertLayout(dialog, "required-long-notes");
            ScrollView scroll = ancestor((TextView) tagged(dialog, "update-prompt-notes"), ScrollView.class);
            require("required-notes-scrollable", scroll != null && scroll.getChildAt(0).getHeight() > scroll.getHeight());
        });
        screenshot("02-required");
        ui(() -> {
            ScrollView scroll = ancestor(tagged(prompt(), "update-prompt-notes"), ScrollView.class);
            scroll.setSmoothScrollingEnabled(false);
            scroll.fullScroll(View.FOCUS_DOWN);
        });
        waitForIdleSync();
        ui(() -> {
            ScrollView scroll = ancestor(tagged(prompt(), "update-prompt-notes"), ScrollView.class);
            observations.put(new JSONObject().put("phase", "required-notes-end").put("scrollY", scroll.getScrollY()).put("childBottom", scroll.getChildAt(0).getBottom()).put("viewportHeight", scroll.getHeight()));
            require("required-notes-tail-reachable", scroll.getScrollY() > 0 && scroll.getChildAt(0).getBottom() - scroll.getScrollY() <= scroll.getHeight() + 2);
            assertButtonsReachable(prompt(), "required-scrolled");
        });
        screenshot("03-required-notes-end");
        ui(() -> {
            activity.manager.downloading = true; activity.manager.progress = 37; activity.manager.status = "正在下载更新…"; listener().changed();
            require("download-progress-visible", tagged(prompt(), "update-prompt-progress").getVisibility() == View.VISIBLE);
            require("download-progress-37", ((ProgressBar) tagged(prompt(), "update-prompt-progress")).getProgress() == 37);
            require("download-positive-disabled", !prompt().getButton(AlertDialog.BUTTON_POSITIVE).isEnabled());
            require("download-positive-hidden", prompt().getButton(AlertDialog.BUTTON_POSITIVE).getVisibility() == View.GONE);
            require("download-status-in-progress-area", "正在下载 · 37%".equals(tagText(prompt(), "update-required-message")));
            require("download-no-redundant-action-status", !textIn(prompt().getWindow().getDecorView(), "正在下载"));
            require("download-required-gate-kept", activity.panel.isMandatoryBlocking());
            ancestor(tagged(prompt(), "update-prompt-notes"), ScrollView.class).fullScroll(View.FOCUS_UP);
        });
        waitForIdleSync(); screenshot("04-downloading");
        ui(() -> {
            activity.manager.downloading = false; activity.manager.verifying = true; listener().changed();
            require("verifying-indeterminate", ((ProgressBar) tagged(prompt(), "update-prompt-progress")).isIndeterminate());
            require("verifying-positive-disabled", !prompt().getButton(AlertDialog.BUTTON_POSITIVE).isEnabled());
            require("verifying-positive-hidden", prompt().getButton(AlertDialog.BUTTON_POSITIVE).getVisibility() == View.GONE);
            require("verifying-status-in-progress-area", "正在校验安装包…".equals(tagText(prompt(), "update-required-message")));
            require("verifying-exit-still-reachable", prompt().getButton(AlertDialog.BUTTON_NEGATIVE).getVisibility() == View.VISIBLE);
        });
        waitForIdleSync(); ui(() -> assertLayout(prompt(), "required-verifying")); screenshot("06-verifying");
        ui(() -> {
            activity.manager.verifying = false; activity.manager.error = "下载中断，请检查网络后重试。"; listener().changed();
            require("error-message-complete", "下载中断，请检查网络后重试。".equals(tagText(prompt(), "update-prompt-detail")));
            require("retry-download-enabled", prompt().getButton(AlertDialog.BUTTON_POSITIVE).isEnabled() && "重试下载".contentEquals(prompt().getButton(AlertDialog.BUTTON_POSITIVE).getText()));
            require("retry-download-visible-again", prompt().getButton(AlertDialog.BUTTON_POSITIVE).getVisibility() == View.VISIBLE);
            require("error-required-gate-kept", activity.panel.isMandatoryBlocking());
        });
        ui(() -> assertLayout(prompt(), "required-error"));
        screenshot("05-download-error");
        ui(() -> {
            // Deliberately do not click retry/install: the component probe must never enqueue an APK download.
            activity.manager.error = ""; activity.manager.verified = true; listener().changed();
            require("verified-install-action-visible", "安装更新".contentEquals(prompt().getButton(AlertDialog.BUTTON_POSITIVE).getText()));
            require("verified-install-visible-again", prompt().getButton(AlertDialog.BUTTON_POSITIVE).getVisibility() == View.VISIBLE && prompt().getButton(AlertDialog.BUTTON_POSITIVE).isEnabled());
        });
        waitForIdleSync(); ui(() -> assertLayout(prompt(), "required-ready-to-install")); screenshot("07-ready-to-install");
        ui(() -> {
            activity.manager.verified = false; activity.manager.checking = true; listener().changed();
            require("checking-positive-hidden", prompt().getButton(AlertDialog.BUTTON_POSITIVE).getVisibility() == View.GONE);
            require("checking-recheck-disabled", !prompt().getButton(AlertDialog.BUTTON_NEUTRAL).isEnabled());
            require("checking-exit-still-visible", prompt().getButton(AlertDialog.BUTTON_NEGATIVE).getVisibility() == View.VISIBLE);
            activity.manager.checking = false; listener().changed();
            require("checking-done-download-visible", prompt().getButton(AlertDialog.BUTTON_POSITIVE).getVisibility() == View.VISIBLE && prompt().getButton(AlertDialog.BUTTON_POSITIVE).isEnabled());
            activity.manager.verified = false;
            activity.panel.onPause();
            require("pause-hides-window", prompt() == null);
            require("pause-does-not-release-gate", activity.panel.isMandatoryBlocking());
            listener().available(); require("background-does-not-show-dialog", prompt() == null);
            activity.panel.onResume(); showing("required-resume-prompts");
            // Changing only policy, with the same artifact, must immediately release the gate.
            seed(false, ID, shortNotes(), 4); listener().changed();
            require("server-ordinary-releases-gate", !activity.panel.isMandatoryBlocking());
            require("server-ordinary-dismisses-required-dialog", prompt() == null);
            activity.panel.goBack(); require("ordinary-back-page-closes", !activity.panel.isOpen());
            activity.ready = true; activity.idle = true;
            seed(true, OTHER_ID, shortNotes(), 5); listener().changed(); showing("required-new-release-restored");
            Button staleDownload = prompt().getButton(AlertDialog.BUTTON_POSITIVE);
            activity.manager.release = null; listener().changed();
            require("withdraw-releases-gate", !activity.panel.isMandatoryBlocking());
            require("withdraw-dismisses-dialog", prompt() == null);
            staleDownload.performClick();
            require("withdraw-stale-download-click-rejected", guard.attempts == 0 && activity.manager.release == null && !activity.manager.downloading);
            activity.panel.goBack(); require("withdraw-back-page-closes", !activity.panel.isOpen());
        });
        // A first foreground whose Host is not safe must retain pending required UI until safe resume.
        ui(() -> {
            activity.panel.onPause(); activity.idle = false; activity.ready = false;
            seed(true, ID, shortNotes(), 6); listener().available();
            require("first-foreground-pending-no-window", prompt() == null);
            activity.panel.onResume(); require("resume-busy-still-pending", prompt() == null);
            activity.ready = true; suppressAutomaticMetadata(); activity.panel.automaticCheck(); showing("resume-safe-displays-pending-required");
            activity.manager.release = null; listener().changed();
        });
    }

    private void seed(boolean required, String id, String notes, long revision) throws Exception {
        JSONObject json = new JSONObject().put("id", id).put("versionName", "99.0.1-beta").put("notes", notes)
                .put("sha256", HASH).put("signerSha256", HASH).put("downloadUrl", AppUpdateManager.BASE + "/releases/" + id + "/file")
                .put("packageName", activity.getPackageName()).put("channel", activity.manager.channel()).put("versionCode", activity.manager.installedCode() + 100)
                .put("byteLength", 3_901_562).put("minSdk", 26).put("revision", revision).put("mandatory", required);
        Constructor<AppUpdateManager.Release> constructor = AppUpdateManager.Release.class.getDeclaredConstructor(JSONObject.class, Context.class);
        constructor.setAccessible(true); activity.manager.release = constructor.newInstance(json, activity);
        activity.manager.downloading = activity.manager.verifying = activity.manager.checking = activity.manager.verified = false;
        activity.manager.error = ""; activity.manager.progress = 0; setField(activity.manager, "metadataChecked", true);
        setField(activity.manager, "automaticStarted", true); suppressAutomaticMetadata();
    }
    private void suppressAutomaticMetadata() { managerPrefs.edit().putLong("lastAttempt", System.currentTimeMillis()).putLong("lastCheck", System.currentTimeMillis()).commit(); }
    private AppUpdateManager.Listener listener() throws Exception { return (AppUpdateManager.Listener) field(activity.manager, "listener"); }
    private AlertDialog prompt() throws Exception { return (AlertDialog) field(activity.panel, "prompt"); }
    private AlertDialog showing(String name) throws Exception { AlertDialog dialog = prompt(); require(name, dialog != null && dialog.isShowing()); return dialog; }
    private View tagged(AlertDialog dialog, String tag) { View result = dialog.getWindow().getDecorView().findViewWithTag(tag); if (result == null) throw new AssertionError("missing tag " + tag); return result; }
    private String tagText(AlertDialog dialog, String tag) { return ((TextView) tagged(dialog, tag)).getText().toString(); }

    private void assertLayout(AlertDialog dialog, String phase) throws Exception {
        View decor = dialog.getWindow().getDecorView();
        require(phase + "-dialog-in-screen", decor.getWidth() > 0 && decor.getHeight() > 0 && decor.getWidth() <= activity.getResources().getDisplayMetrics().widthPixels);
        assertButtonsReachable(dialog, phase);
        for (String tag : new String[]{"update-prompt-version", "update-required-message", "update-prompt-detail", "update-prompt-notes"}) {
            TextView text = (TextView) tagged(dialog, tag); if (text.getVisibility() != View.VISIBLE) continue;
            require(phase + "-" + tag + "-layout", text.getLayout() != null && text.getLayout().getLineCount() > 0);
            require(phase + "-" + tag + "-full-text-laid-out", text.getLayout().getLineEnd(text.getLayout().getLineCount() - 1) == text.length());
            for (int i = 0; i < text.getLayout().getLineCount(); i++) require(phase + "-" + tag + "-no-ellipsis-" + i, text.getLayout().getEllipsisCount(i) == 0);
            require(phase + "-" + tag + "-no-horizontal-overflow", text.getLayout().getWidth() <= text.getWidth() - text.getCompoundPaddingLeft() - text.getCompoundPaddingRight());
        }
        observations.put(new JSONObject().put("phase", phase).put("fontScale", fontScale).put("dialogWidth", decor.getWidth()).put("dialogHeight", decor.getHeight()));
    }
    private void assertButtonsReachable(AlertDialog dialog, String phase) throws Exception {
        Rect screen = new Rect(0, 0, activity.getResources().getDisplayMetrics().widthPixels, activity.getResources().getDisplayMetrics().heightPixels);
        for (int which : new int[]{AlertDialog.BUTTON_POSITIVE, AlertDialog.BUTTON_NEGATIVE, AlertDialog.BUTTON_NEUTRAL}) {
            Button button = dialog.getButton(which); if (button == null || button.getVisibility() != View.VISIBLE) continue;
            int[] xy = new int[2]; button.getLocationOnScreen(xy); Rect actual = new Rect(xy[0], xy[1], xy[0] + button.getWidth(), xy[1] + button.getHeight());
            require(phase + "-button-" + which + "-in-screen", actual.width() > 0 && actual.height() > 0 && screen.contains(actual));
            require(phase + "-button-" + which + "-no-ellipsis", button.getLayout() != null && button.getLayout().getEllipsisCount(0) == 0);
        }
    }
    private static boolean textIn(View view, String value) {
        if (view instanceof TextView && ((TextView) view).getText().toString().equals(value) && view.getVisibility() == View.VISIBLE) return true;
        if (view instanceof ViewGroup) for (int i = 0; i < ((ViewGroup) view).getChildCount(); i++) if (textIn(((ViewGroup) view).getChildAt(i), value)) return true;
        return false;
    }
    private static <T> T ancestor(View view, Class<T> kind) {
        while (view != null) { if (kind.isInstance(view)) return kind.cast(view); view = view.getParent() instanceof View ? (View) view.getParent() : null; }
        return null;
    }
    private void screenshot(String name) throws Exception {
        waitForIdleSync(); SystemClock.sleep(500);
        ui(() -> {
            View decor = prompt().getWindow().getDecorView();
            android.graphics.drawable.Drawable background = decor.getBackground();
            JSONObject observation = new JSONObject().put("phase", "capture-" + name).put("settleMs", 500)
                    .put("clipToOutline", decor.getClipToOutline()).put("viewAlpha", decor.getAlpha())
                    .put("windowAlpha", prompt().getWindow().getAttributes().alpha)
                    .put("backgroundClass", background == null ? "null" : background.getClass().getName())
                    .put("backgroundAlpha", background == null ? -1 : background.getAlpha());
            if (background instanceof android.graphics.drawable.GradientDrawable) {
                android.content.res.ColorStateList color = ((android.graphics.drawable.GradientDrawable) background).getColor();
                if (color != null) observation.put("backgroundColor", String.format(java.util.Locale.ROOT, "#%08X", color.getDefaultColor()))
                        .put("backgroundColorAlpha", android.graphics.Color.alpha(color.getDefaultColor()));
            }
            observations.put(observation);
        });
        Bitmap bitmap = getUiAutomation().takeScreenshot(); if (bitmap == null) throw new AssertionError("screenshot " + name);
        File file = new File(output, name + ".png");
        try (FileOutputStream stream = new FileOutputStream(file)) { if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)) throw new AssertionError("PNG " + name); }
        screenshots.put(new JSONObject().put("file", file.getName()).put("width", bitmap.getWidth()).put("height", bitmap.getHeight())); bitmap.recycle();
    }
    private interface Checked { void run() throws Exception; }
    private void ui(Checked action) throws Exception {
        AtomicReference<Throwable> error = new AtomicReference<>();
        runOnMainSync(() -> { try { action.run(); } catch (Throwable problem) { error.set(problem); } });
        if (error.get() != null) { if (error.get() instanceof Exception) throw (Exception) error.get(); throw new AssertionError(error.get()); }
        waitForIdleSync();
    }
    private void require(String name, boolean ok) throws Exception { checks.put(new JSONObject().put("name", name).put("pass", ok)); if (!ok) throw new AssertionError(name); }
    private static Field findField(Class<?> type, String name) throws NoSuchFieldException { while (type != null) { try { Field field = type.getDeclaredField(name); field.setAccessible(true); return field; } catch (NoSuchFieldException ignored) { type = type.getSuperclass(); } } throw new NoSuchFieldException(name); }
    private static Object field(Object object, String name) throws Exception { return findField(object.getClass(), name).get(object); }
    private static void setField(Object object, String name, Object value) throws Exception { findField(object.getClass(), name).set(object, value); }
    private static String shortNotes() { return "优化本机照片细节载入；新增版本提示与强制更新。"; }
    private static String longNotes() { StringBuilder notes = new StringBuilder(); for (int i = 1; i <= 28; i++) notes.append(i).append(". 改善照片处理和连接稳定性，保留原始照片，更新后继续使用。\n"); return notes.append("说明末尾：全部更新说明已完整显示。").toString(); }
    @SuppressWarnings("unchecked") private static void restore(SharedPreferences prefs, Map<String, ?> values) {
        SharedPreferences.Editor edit = prefs.edit().clear();
        for (Map.Entry<String, ?> entry : values.entrySet()) { String key = entry.getKey(); Object value = entry.getValue(); if (value instanceof String) edit.putString(key, (String) value); else if (value instanceof Boolean) edit.putBoolean(key, (Boolean) value); else if (value instanceof Integer) edit.putInt(key, (Integer) value); else if (value instanceof Long) edit.putLong(key, (Long) value); else if (value instanceof Float) edit.putFloat(key, (Float) value); else if (value instanceof Set) edit.putStringSet(key, (Set<String>) value); }
        if (!edit.commit()) throw new AssertionError("preferences restore failed");
    }
    private static boolean same(Map<String, ?> before, Map<String, ?> after) { return before != null && before.equals(after); }
    private void writeReport() throws Exception {
        if (output == null) return;
        JSONArray trace = new JSONArray(); if (failure != null) for (StackTraceElement line : failure.getStackTrace()) trace.put(line.toString());
        JSONArray causes = new JSONArray(); if (failure != null) { Throwable cause = failure.getCause(); while (cause != null) { causes.put(cause.toString()); cause = cause.getCause(); } }
        JSONObject report = new JSONObject().put("scope", "production UpdatePanel component UI; synthetic validated Release/status callbacks; no MainActivity implementation, metadata HTTP, DownloadManager or installer")
                .put("pass", failure == null).put("fontScale", fontScale).put("candidateSha256", arguments.getString("candidateSha256", ""))
                .put("versionCode", getTargetContext().getPackageManager().getPackageInfo(getTargetContext().getPackageName(), 0).getLongVersionCode())
                .put("workerTasks", guard == null ? -1 : guard.attempts).put("checks", checks).put("screenshots", screenshots).put("layoutObservations", observations)
                .put("failure", failure == null ? JSONObject.NULL : failure.toString()).put("causes", causes).put("stack", trace);
        try (FileOutputStream stream = new FileOutputStream(new File(output, "report.json"))) { stream.write(report.toString(2).getBytes(java.nio.charset.StandardCharsets.UTF_8)); }
    }

    public static final class ProbeActivity extends Activity implements UpdatePanel.Host {
        UpdatePanel panel; AppUpdateManager manager; FrameLayout frame;
        boolean idle = true, ready = true; int feedbacks, installRequests;
        @Override protected void attachBaseContext(Context base) { Configuration configuration = new Configuration(base.getResources().getConfiguration()); configuration.fontScale = fontScale; super.attachBaseContext(base.createConfigurationContext(configuration)); }
        @Override protected void onCreate(Bundle state) { super.onCreate(state); getWindow().setStatusBarColor(0xff171614); getWindow().setNavigationBarColor(0xff171614); frame = new FrameLayout(this); frame.setBackgroundColor(0xff171614); setContentView(frame); }
        void initialise() throws Exception { panel = new UpdatePanel(this, this); manager = (AppUpdateManager) field(panel, "updates"); render(); }
        void render() { if (panel == null || frame == null) return; frame.removeAllViews(); if (panel.isOpen()) frame.addView(panel.createView(new UiPalette(this))); else { TextView label = new TextView(this); label.setText("更新提示组件检查"); label.setTextColor(0xffe7e5e2); label.setTextSize(16); label.setGravity(android.view.Gravity.CENTER); frame.addView(label, new FrameLayout.LayoutParams(-1, -1)); } }
        @Override public void onChanged() { render(); }
        @Override public boolean idleForAutomaticCheck() { return idle; }
        @Override public boolean readyForMandatoryUpdate() { return ready; }
        @Override public void onFeedback(String title, String message) { feedbacks++; }
        @Override public void onAvailable(String version, Runnable show) { throw new AssertionError("Legacy toast available callback used"); }
        @Override public void beforeInstall(Runnable proceed) { installRequests++; throw new AssertionError("Installer forbidden in component probe"); }
        @Override public void onBackPressed() { if (panel != null) panel.goBack(); }
    }
    private static final class GuardExecutor extends AbstractExecutorService {
        int attempts; boolean closed;
        @Override public void execute(Runnable command) { attempts++; throw new AssertionError("Network/download/installer worker forbidden in UI component probe"); }
        @Override public void shutdown() { closed = true; }
        @Override public List<Runnable> shutdownNow() { closed = true; return new ArrayList<>(); }
        @Override public boolean isShutdown() { return closed; }
        @Override public boolean isTerminated() { return closed; }
        @Override public boolean awaitTermination(long timeout, TimeUnit unit) { return closed; }
    }
}
