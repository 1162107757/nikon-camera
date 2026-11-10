package cc.huevia.rawdevelopmentqa;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.view.View;
import android.widget.TextView;
import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.List;
import org.json.JSONArray;
import org.json.JSONObject;

/** Exercises the installed Activity's real buttons when the system document provider fails. */
final class RawDocumentPickerChecks {
    static void emptyEntry(Instrumentation probe, Activity host, String owner, JSONArray checks) throws Exception {
        List<String> actions = new ArrayList<>();
        Instrumentation.ActivityMonitor unavailable = new Instrumentation.ActivityMonitor() {
            @Override public Instrumentation.ActivityResult onStartActivity(Intent intent) {
                if (Intent.ACTION_OPEN_DOCUMENT.equals(intent.getAction()) || Intent.ACTION_GET_CONTENT.equals(intent.getAction())) {
                    actions.add(intent.getAction());
                    throw new ActivityNotFoundException("QA: no system file picker at initial entry");
                }
                return null;
            }
        };
        Instrumentation.ActivityMonitor screen = probe.addMonitor("cc.huevia.RawDevelopActivity", null, false);
        probe.addMonitor(unavailable);
        Activity page = null;
        try {
            probe.runOnMainSync(() -> host.startActivityForResult(new Intent().setClassName("cc.huevia", "cc.huevia.RawDevelopActivity")
                    .putExtra("raw_owner", owner), 7319));
            page = probe.waitForMonitorWithTimeout(screen, 10000);
            check(checks, "empty-entry-starts-real-raw-activity", page != null);
            probe.waitForIdleSync();
            check(checks, "empty-entry-tries-both-import-handlers", actions.equals(java.util.Arrays.asList(Intent.ACTION_OPEN_DOCUMENT, Intent.ACTION_GET_CONTENT)));
            check(checks, "empty-entry-survives-missing-file-picker", !page.isFinishing() && !page.isDestroyed());
            check(checks, "empty-entry-releases-picker-state", !(Boolean)get(page, "picking"));
            check(checks, "empty-entry-has-readable-recovery-message", ((TextView)get(page, "status")).getText().toString().contains("重试"));
            check(checks, "empty-entry-keeps-export-disabled", !((View)get(page, "save")).isEnabled() && !((View)get(page, "edit")).isEnabled());
        } finally {
            probe.removeMonitor(screen); probe.removeMonitor(unavailable);
            if (page != null) {
                Activity finished = page; probe.runOnMainSync(finished::finish); probe.waitForIdleSync();
                long deadline = android.os.SystemClock.uptimeMillis() + 5000;
                while (!finished.isDestroyed() && android.os.SystemClock.uptimeMillis() < deadline) android.os.SystemClock.sleep(20);
                check(checks, "empty-entry-test-activity-destroyed", finished.isDestroyed());
            }
        }
    }

    static void run(Instrumentation probe, Activity page, JSONArray checks) throws Exception {
        Object preview = get(page, "preview"), result = get(page, "result");
        scenario(probe, page, checks, "missing-open-document", Intent.ACTION_OPEN_DOCUMENT, false, false,
                "raw-development-choose", Intent.ACTION_OPEN_DOCUMENT, Intent.ACTION_GET_CONTENT);
        scenario(probe, page, checks, "both-import-handlers-missing", "both", false, false,
                "raw-development-choose", Intent.ACTION_OPEN_DOCUMENT, Intent.ACTION_GET_CONTENT);
        scenario(probe, page, checks, "import-security-denied", Intent.ACTION_OPEN_DOCUMENT, true, false,
                "raw-development-choose", Intent.ACTION_OPEN_DOCUMENT);
        scenario(probe, page, checks, "fallback-security-denied", "both", false, true,
                "raw-development-choose", Intent.ACTION_OPEN_DOCUMENT, Intent.ACTION_GET_CONTENT);
        scenario(probe, page, checks, "save-handler-missing", Intent.ACTION_CREATE_DOCUMENT, false, false,
                "raw-development-save-png", Intent.ACTION_CREATE_DOCUMENT);
        scenario(probe, page, checks, "save-security-denied", Intent.ACTION_CREATE_DOCUMENT, true, false,
                "raw-development-save-png", Intent.ACTION_CREATE_DOCUMENT);
        scenario(probe, page, checks, "retry-import-after-failure", "none", false, false,
                "raw-development-choose", Intent.ACTION_OPEN_DOCUMENT);
        check(checks, "document-failures-preserve-developed-photo", preview == get(page, "preview") && result == get(page, "result"));
    }

    private static void scenario(Instrumentation probe, Activity page, JSONArray checks, String name,
            String failedAction, boolean denied, boolean fallbackDenied, String buttonTag, String... expected) throws Exception {
        List<String> actions = new ArrayList<>();
        Instrumentation.ActivityMonitor monitor = new Instrumentation.ActivityMonitor() {
            @Override public Instrumentation.ActivityResult onStartActivity(Intent intent) {
                String action = intent.getAction();
                if (!Intent.ACTION_OPEN_DOCUMENT.equals(action) && !Intent.ACTION_GET_CONTENT.equals(action)
                        && !Intent.ACTION_CREATE_DOCUMENT.equals(action)) return null;
                actions.add(action);
                if ("both".equals(failedAction) || action.equals(failedAction)) {
                    if (denied || fallbackDenied && Intent.ACTION_GET_CONTENT.equals(action))
                        throw new SecurityException("QA: system document provider denied launch");
                    throw new ActivityNotFoundException("QA: system document provider unavailable");
                }
                return new Instrumentation.ActivityResult(Activity.RESULT_CANCELED, null);
            }
        };
        Throwable[] escaped = {null};
        probe.addMonitor(monitor);
        try {
            probe.runOnMainSync(() -> {
                try {
                    View button = page.getWindow().getDecorView().findViewWithTag(buttonTag);
                    if (button == null || !button.isEnabled()) throw new AssertionError("button unavailable: " + buttonTag);
                    button.performClick();
                } catch (Throwable error) { escaped[0] = error; }
            });
            probe.waitForIdleSync();
            check(checks, name + "-does-not-escape-main-thread", escaped[0] == null);
            check(checks, name + "-expected-system-actions", actions.equals(java.util.Arrays.asList(expected)));
            check(checks, name + "-picker-state-cleared", !(Boolean)get(page, "picking"));
            check(checks, name + "-pending-save-cleared", get(page, "pendingSave") == null);
            if (!"none".equals(failedAction) && !"missing-open-document".equals(name)) {
                String status = ((TextView)get(page, "status")).getText().toString();
                check(checks, name + "-readable-recovery-message", status.contains("文件") && status.contains("重试"));
            }
        } finally { probe.removeMonitor(monitor); }
    }

    private static Object get(Object value, String name) throws Exception {
        Field field = value.getClass().getDeclaredField(name); field.setAccessible(true); return field.get(value);
    }
    private static void check(JSONArray checks, String name, boolean passed) throws Exception {
        checks.put(new JSONObject().put("name", name).put("passed", passed));
        if (!passed) throw new AssertionError(name);
    }
}
