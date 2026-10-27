package cc.huevia.connectionqa;

import android.app.*;
import android.content.*;
import android.net.Uri;
import android.os.*;
import cc.huevia.album.ConnectionTrace;
import java.io.*;
import java.lang.reflect.*;
import java.nio.file.*;
import java.security.*;
import java.util.concurrent.atomic.AtomicReference;
import org.json.*;

/** Production export methods on an owned emulator. No camera, media, or new UI design. */
public final class ConnectionReportProbe extends Instrumentation {
    private Bundle args;
    private final JSONArray checks = new JSONArray();
    private Activity activity;
    private String originalReport;
    private File exported;
    @Override public void onCreate(Bundle args) { super.onCreate(args); this.args = args; start(); }
    @Override public void onStart() {
        Bundle result = new Bundle(); JSONObject report = new JSONObject(); boolean passed = false;
        try {
            check(Build.HARDWARE.equals("ranchu") || Build.HARDWARE.equals("goldfish"), "owned-emulator-only");
            check(sha(new File(getTargetContext().getApplicationInfo().sourceDir)).equals(args.getString("apkSha256")), "installed-candidate-hash");
            activity = startActivitySync(new Intent().setClassName("cc.huevia", "cc.huevia.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            long deadline = System.nanoTime() + 20_000_000_000L;
            while (!onMain(() -> (Boolean) field("ready").get(activity)) && System.nanoTime() < deadline) Thread.sleep(50);
            check(onMain(() -> (Boolean) field("ready").get(activity)), "production-main-ready");
            originalReport = onMain(() -> (String) field("report").get(activity));
            ConnectionTrace.mark("EXPORT_QA");
            String empty = onMain(() -> { field("report").set(activity, ""); return snapshot(); });
            JSONObject value = new JSONObject(empty);
            check(value.getString("appVersion").equals("0.20.3-beta"), "export-version");
            check(value.getString("connectionTrace").contains("event=EXPORT_QA"), "trace-without-preset-report");
            JSONObject legacy = new JSONObject(onMain(() -> { field("report").set(activity, "{\"legacyResult\":true,\"appVersion\":\"legacy-version\",\"items\":[1,2]}"); return snapshot(); }));
            check(legacy.getBoolean("legacyResult") && legacy.getJSONArray("items").length() == 2 && legacy.has("connectionTrace")
                    && legacy.getString("appVersion").equals("legacy-version") && legacy.getString("reportExportAppVersion").equals("0.20.3-beta"), "legacy-json-fields-and-original-version-retained");
            JSONObject text = new JSONObject(onMain(() -> { field("report").set(activity, "legacy plain report"); return snapshot(); }));
            check(text.getString("originalReport").equals("legacy plain report") && text.has("connectionTrace"), "legacy-text-retained");
            exported = new File(getTargetContext().getExternalFilesDir(null), "connection-export-qa.json");
            if (exported.exists()) check(exported.delete(), "old-owned-test-output-cleared");
            onMain(() -> { field("report").set(activity, ""); Method callback = method("onActivityResult", int.class, int.class, Intent.class);
                callback.invoke(activity, 102, Activity.RESULT_OK, new Intent().setData(Uri.fromFile(exported))); return null; });
            deadline = System.nanoTime() + 10_000_000_000L;
            while ((!exported.isFile() || exported.length() == 0) && System.nanoTime() < deadline) Thread.sleep(50);
            JSONObject saved = new JSONObject(Files.readString(exported.toPath()));
            check(saved.getString("connectionTrace").contains("event=EXPORT_QA") && saved.getString("appVersion").equals("0.20.3-beta"), "activity-result-writes-valid-current-json-through-content-resolver");
            passed = true;
        } catch (Throwable failure) {
            try { report.put("error", failure.toString()); } catch (Exception ignored) { }
        } finally {
            try { if (activity != null && originalReport != null) onMain(() -> { field("report").set(activity, originalReport); return null; });
                if (exported != null && exported.exists()) check(exported.delete(), "owned-export-output-cleaned");
                if (activity != null) onMain(() -> { activity.finish(); return null; });
                report.put("status", passed ? "PASS" : "FAIL").put("apkSha256", args.getString("apkSha256")).put("assertions", checks)
                        .put("scope", "Production JSON export path only; no physical camera or throughput measurement");
                result.putString("report", report.toString());
            } catch (Exception cleanup) { passed = false; result.putString("cleanupError", cleanup.toString()); }
            finish(passed ? Activity.RESULT_OK : Activity.RESULT_CANCELED, result);
        }
    }
    private String snapshot() throws Exception { return (String) method("exportReportSnapshot").invoke(activity); }
    private Field field(String name) throws Exception { Field f = activity.getClass().getDeclaredField(name); f.setAccessible(true); return f; }
    private Method method(String name, Class<?>... parameters) throws Exception { Method m = activity.getClass().getDeclaredMethod(name, parameters); m.setAccessible(true); return m; }
    private void check(boolean ok, String name) {
        if (!ok) throw new AssertionError(name); checks.put(name);
        Bundle status = new Bundle(); status.putString("checkpoint", name); sendStatus(0, status);
    }
    private interface Work<T> { T get() throws Exception; }
    private <T> T onMain(Work<T> work) throws Exception {
        AtomicReference<T> result = new AtomicReference<>(); AtomicReference<Throwable> error = new AtomicReference<>();
        runOnMainSync(() -> { try { result.set(work.get()); } catch (Throwable t) { error.set(t); } });
        if (error.get() != null) throw new Exception(error.get()); return result.get();
    }
    private static String sha(File file) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (InputStream in = new FileInputStream(file)) { byte[] b = new byte[65536]; int n; while ((n = in.read(b)) >= 0) digest.update(b, 0, n); }
        StringBuilder out = new StringBuilder(); for (byte b : digest.digest()) out.append(String.format("%02x", b & 255)); return out.toString();
    }
}
