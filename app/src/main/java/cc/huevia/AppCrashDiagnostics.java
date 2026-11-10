package cc.huevia;

import android.app.ActivityManager;
import android.content.Context;
import android.os.Build;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.util.List;

/** Local, bounded evidence. Recording never replaces Android's uncaught-exception handling. */
public final class AppCrashDiagnostics {
    static final int MAX_BYTES = 65536, MAX_STACK_CHARS = 12000;
    private static final String DIRECTORY = "app-stability", RECORD = "last-crash.txt";
    private AppCrashDiagnostics() {}

    public static void install(Context context) {
        try {
            Thread.UncaughtExceptionHandler previous = Thread.getDefaultUncaughtExceptionHandler();
            if (previous == null || previous instanceof CrashRecorder) return;
            String version = context.getPackageManager().getPackageInfo(context.getPackageName(), 0).versionName;
            String header = "package=" + context.getPackageName() + "\nversion=" + version
                    + "\nsdk=" + Build.VERSION.SDK_INT + "\nmanufacturer=" + Build.MANUFACTURER
                    + "\nmodel=" + Build.MODEL + "\nfingerprint=" + Build.FINGERPRINT;
            Thread.setDefaultUncaughtExceptionHandler(new CrashRecorder(new File(context.getFilesDir(), DIRECTORY), header, previous));
        } catch (Exception | LinkageError | OutOfMemoryError unavailable) {
            // Optional evidence must not turn an otherwise healthy startup into a crash.
        }
    }

    /** Worker-only: called while the user explicitly exports a diagnostics report. */
    public static String appendToReport(Context context, String snapshot) {
        try {
            JSONObject report;
            try { report = new JSONObject(snapshot); }
            catch (Exception oldText) { report = new JSONObject().put("originalReport", snapshot == null ? "" : snapshot); }
            report.put("appStability", snapshot(context));
            return report.toString(2);
        } catch (Exception | LinkageError | OutOfMemoryError unavailable) { return snapshot; }
    }

    public static JSONObject snapshot(Context context) {
        JSONObject value = new JSONObject();
        try {
            value.put("sdk", Build.VERSION.SDK_INT).put("manufacturer", Build.MANUFACTURER).put("model", Build.MODEL)
                    .put("currentAppVersion", context.getPackageManager().getPackageInfo(context.getPackageName(), 0).versionName);
            File file = new File(new File(context.getFilesDir(), DIRECTORY), RECORD);
            if (file.isFile()) {
                try (InputStream in = new FileInputStream(file)) { value.put("lastJavaCrash", boundedRead(in, MAX_BYTES)); }
                value.put("lastJavaCrashRecordedAt", file.lastModified());
            } else value.put("lastJavaCrash", JSONObject.NULL);
            value.put("processExitHistoryAvailable", Build.VERSION.SDK_INT >= 30);
            if (Build.VERSION.SDK_INT >= 30) value.put("processExitHistory", Api30.exits(context));
        } catch (Exception | LinkageError | OutOfMemoryError unavailable) {
            try { value.put("collectionError", unavailable.getClass().getSimpleName()); } catch (Exception ignored) { }
        }
        return value;
    }

    @android.annotation.TargetApi(30)
    private static final class Api30 {
        static JSONArray exits(Context context) throws Exception {
            JSONArray rows = new JSONArray();
            ActivityManager manager = context.getSystemService(ActivityManager.class);
            if (manager == null) return rows;
            List<android.app.ApplicationExitInfo> history = manager.getHistoricalProcessExitReasons(context.getPackageName(), 0, 8);
            for (android.app.ApplicationExitInfo item : history) {
                int reason = item.getReason();
                if (reason != android.app.ApplicationExitInfo.REASON_CRASH && reason != android.app.ApplicationExitInfo.REASON_CRASH_NATIVE
                        && reason != android.app.ApplicationExitInfo.REASON_ANR && reason != android.app.ApplicationExitInfo.REASON_LOW_MEMORY
                        && reason != android.app.ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE) continue;
                JSONObject row = new JSONObject().put("reason", reason).put("status", item.getStatus()).put("timestamp", item.getTimestamp())
                        .put("pid", item.getPid()).put("processName", limited(item.getProcessName(), 256))
                        .put("description", limited(item.getDescription(), 2048)).put("pssKb", item.getPss()).put("rssKb", item.getRss());
                if (rows.length() == 0) try (InputStream trace = item.getTraceInputStream()) {
                    if (trace != null) {
                        byte[] bytes = boundedBytes(trace, MAX_BYTES);
                        row.put("traceByteLimit", MAX_BYTES).put("traceMayBeTruncated", bytes.length == MAX_BYTES);
                        if (reason == android.app.ApplicationExitInfo.REASON_CRASH_NATIVE)
                            row.put("traceFormat", "native-tombstone-protobuf-prefix").put("traceBase64", android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP));
                        else row.put("traceFormat", "utf-8-prefix").put("trace", new String(bytes, StandardCharsets.UTF_8));
                    }
                } catch (Exception unavailable) { row.put("traceUnavailable", unavailable.getClass().getSimpleName()); }
                rows.put(row); if (rows.length() >= 4) break;
            }
            return rows;
        }
    }

    static String boundedRead(InputStream input, int limit) throws IOException {
        return new String(boundedBytes(input, limit), StandardCharsets.UTF_8);
    }
    private static byte[] boundedBytes(InputStream input, int limit) throws IOException {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream(Math.min(4096, limit));
        byte[] buffer = new byte[4096]; int n, remaining = limit;
        while (remaining > 0 && (n = input.read(buffer, 0, Math.min(buffer.length, remaining))) != -1) {
            bytes.write(buffer, 0, n); remaining -= n;
        }
        return bytes.toByteArray();
    }
    private static String limited(String text, int limit) { return text == null ? "" : text.substring(0, Math.min(limit, text.length())); }

    static final class CrashRecorder implements Thread.UncaughtExceptionHandler {
        private final File directory;
        private final String header;
        private final Thread.UncaughtExceptionHandler previous;
        CrashRecorder(File directory, String header, Thread.UncaughtExceptionHandler previous) {
            if (directory == null || previous == null) throw new IllegalArgumentException("crash recorder");
            this.directory = directory; this.header = limited(header, 2048); this.previous = previous;
        }
        @Override public void uncaughtException(Thread thread, Throwable error) {
            try { record(thread, error); } catch (Throwable unavailable) { /* Preserve the original failure and delegate. */ }
            finally { previous.uncaughtException(thread, error); }
        }
        private synchronized void record(Thread thread, Throwable error) throws IOException {
            if (!directory.isDirectory() && !directory.mkdirs()) throw new IOException("crash directory");
            BoundedWriter stack = new BoundedWriter(MAX_STACK_CHARS);
            error.printStackTrace(new PrintWriter(stack));
            Runtime runtime = Runtime.getRuntime();
            String body = "recordedAtEpochMillis=" + System.currentTimeMillis() + "\n" + header
                    + "\nthread=" + limited(thread == null ? "unknown" : thread.getName(), 256)
                    + "\nheapMax=" + runtime.maxMemory() + "\nheapUsed=" + (runtime.totalMemory() - runtime.freeMemory())
                    + "\nstackTruncated=" + stack.truncated + "\n\n" + stack;
            byte[] data = body.getBytes(StandardCharsets.UTF_8);
            if (data.length > MAX_BYTES) throw new IOException("crash record bounds");
            File temporary = new File(directory, RECORD + ".tmp"), target = new File(directory, RECORD);
            try {
                try (FileOutputStream stream = new FileOutputStream(temporary)) { stream.write(data); stream.getFD().sync(); }
                try { Files.move(temporary.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE); }
                catch (AtomicMoveNotSupportedException unsupported) { Files.move(temporary.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING); }
            } finally { if (temporary.exists()) temporary.delete(); }
        }
    }
    private static final class BoundedWriter extends Writer {
        private final StringBuilder value = new StringBuilder();
        private final int limit;
        boolean truncated;
        BoundedWriter(int limit) { this.limit = limit; }
        @Override public void write(char[] text, int start, int length) {
            int accepted = Math.min(length, limit - value.length());
            if (accepted > 0) value.append(text, start, accepted);
            if (accepted < length) truncated = true;
        }
        @Override public void flush() { }
        @Override public void close() { }
        @Override public String toString() { return value.toString(); }
    }
}
