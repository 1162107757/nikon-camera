package cc.huevia.album;

import java.io.ByteArrayOutputStream;
import java.io.EOFException;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.net.SocketTimeoutException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;
import java.util.regex.Pattern;

/** Bounded local connection evidence. Never records camera data or exception messages. */
public final class ConnectionTrace {
    static final int MAX_EVENTS = 256;
    static final int MAX_BYTES = 64 * 1024;
    private static final int MAX_LINE_LENGTH = 512;
    private static final long NORMAL_FLUSH_NANOS = TimeUnit.SECONDS.toNanos(10);
    private static final Pattern TOKEN = Pattern.compile("[A-Z][A-Z0-9_]{0,63}");
    private static final Pattern LINE = Pattern.compile("wall_ms=[0-9]+ mono_ms=[0-9]+ event=[A-Z][A-Z0-9_]{0,63}"
            + "(?: conn=[0-9]+)?(?: op=0x[0-9a-f]{4} tx=[0-9]+)?(?: elapsed_ms=[0-9]+)?"
            + "(?: count=[0-9]+)?(?: detail=[0-9]+)?(?: response=0x[0-9a-f]{4})?"
            + "(?: bytes=[0-9]+ total_bytes=[0-9]+ payload_read_ms=[0-9]+ sink_write_ms=[0-9]+ progress_callback_ms=[0-9]+ timeouts=[0-9]+)?"
            + "(?: category=(?:EOF|TIMEOUT|IO|CANCEL|EXPLICIT|PROTOCOL|REFUSED|NO_ROUTE|PERMISSION))?");
    private static final AtomicLong IDS = new AtomicLong();
    private static final ScheduledExecutorService WRITER = Executors.newSingleThreadScheduledExecutor(task -> {
        Thread thread = new Thread(task, "camera-connection-trace"); thread.setDaemon(true); return thread;
    });
    private static volatile State enabled;

    private ConnectionTrace() { }

    /** Call with an app-owned external-files path. Reads and writes run only on the trace worker. */
    public static synchronized void configure(File file) {
        if (file == null) {
            State previous = enabled; enabled = null;
            if (previous != null) synchronized (previous) {
                previous.ticket++;
                if (previous.pending != null) previous.pending.cancel(false);
                previous.pending = null;
            }
            return;
        }
        File target = file.getAbsoluteFile();
        State previous = enabled;
        if (previous != null && previous.file.equals(target)) return;
        State state = new State(target);
        enabled = state;
        add(state, "TRACE_CONFIGURED", "", true);
        try { WRITER.execute(() -> loadAndWrite(state)); }
        catch (RuntimeException unavailable) { enabled = null; }
    }

    /** Only fixed uppercase event tokens are accepted; arbitrary UI/network text is discarded. */
    public static void mark(String event) {
        State state = enabled;
        if (state == null || event == null || !TOKEN.matcher(event).matches()) return;
        add(state, event, "", true);
    }

    /** Safe bounded text snapshot; performs no file I/O. Empty while tracing is disabled. */
    public static String snapshot() {
        State state = enabled;
        if (state == null) return "";
        synchronized (state) { return joined(state.lines); }
    }

    public static long diagnosticStarted(String stage) {
        diagnostic("DIAG_" + stage + "_BEGIN", -1, -1, -1, null);
        return System.nanoTime();
    }

    public static void diagnosticFinished(String stage, long started, long count, long detail, Throwable failure) {
        diagnostic("DIAG_" + stage + (failure == null ? "_OK" : "_FAILED"),
                Math.max(0, (System.nanoTime() - started) / 1_000_000L), count, detail, failure);
    }

    /** Fixed reason tokens and numbers only. Repeated identical wait states are coalesced. */
    public static void diagnosticReason(String reason, long count, long detail) {
        State state = enabled;
        if (state == null || reason == null || !TOKEN.matcher(reason).matches()) return;
        String key = reason + ":" + count + ":" + detail;
        synchronized (state) {
            if (key.equals(state.lastDiagnosticReason)) return;
            state.lastDiagnosticReason = key;
        }
        diagnostic("DIAG_" + reason, -1, count, detail, null);
    }

    private static void diagnostic(String event, long elapsed, long count, long detail, Throwable failure) {
        State state = enabled;
        if (state == null || !TOKEN.matcher(event).matches()) return;
        String fields = (elapsed < 0 ? "" : " elapsed_ms=" + elapsed)
                + (count < 0 ? "" : " count=" + count) + (detail < 0 ? "" : " detail=" + detail)
                + responseField(failure) + (failure == null ? "" : " category=" + category(failure));
        synchronized (state) { if (event.endsWith("_BEGIN")) state.lastDiagnosticReason = ""; }
        add(state, event, fields, event.endsWith("_FAILED"));
    }

    /** A description of observed evidence, not a guess about the physical camera. No file I/O. */
    public static String diagnosticSummary() {
        String[] lines = snapshot().split("\n");
        for (int i = lines.length - 1; i >= 0; i--) {
            String line = lines[i];
            if (line.contains("event=DIAG_ALBUM_INDEX_FAILED")) continue;
            if (line.contains("event=DIAG_ALBUM_INDEX_OK")) return "照片索引已读取。若图片仍未显示，请同时检查后续缩略图日志。";
            if (line.contains("event=DIAG_") && line.contains("_FAILED")) {
                String stage = line.contains("ALBUM_STORAGE") ? "读取存储卡" : line.contains("ALBUM_HANDLES") ? "读取照片索引"
                        : line.contains("ALBUM_CAPABILITY") ? "检查照片读取能力" : line.contains("ALBUM_IDENTITY") ? "识别相机信息"
                        : line.contains("DEVICE_INFO") ? "读取相机信息" : line.contains("COMMAND_SOCKET") ? "建立相机网络通道"
                        : line.contains("COMMAND_ACK") ? "等待相机确认" : line.contains("EVENT_SOCKET") ? "建立事件通道"
                        : line.contains("EVENT_ACK") ? "等待事件通道确认" : line.contains("OPEN_SESSION") ? "打开相机会话" : "读取相机照片";
                if (line.contains("response=0x2019")) return stage + "时，相机返回忙碌（0x2019）。";
                if (line.contains("response=")) return stage + "失败，相机返回 " + field(line, "response") + "。";
                if (line.contains("category=TIMEOUT")) return stage + "超时；日志包含耗时及前后阶段。";
                if (line.contains("category=REFUSED")) return stage + "被拒绝，请核对相机无线状态及其他相机应用。";
                if (line.contains("category=NO_ROUTE")) return stage + "失败，当前网络无法到达相机。";
                if (line.contains("ALBUM_CAPABILITY")) return "相机未提供必需的照片读取操作，操作编号为 " + field(line, "detail") + "（十进制）。";
                return stage + "未完成，错误分类为 " + field(line, "category") + "。";
            }
            if (line.contains("event=DIAG_ALBUM_INDEX_BEGIN")) return "照片列表读取已开始，尚未记录完成结果。";
        }
        return "尚无本次照片读取的诊断结果，请重试读取照片后导出。";
    }

    private static String field(String line, String key) {
        for (String token : line.split(" ")) if (token.startsWith(key + "=")) return token.substring(key.length() + 1);
        return "UNKNOWN";
    }

    private static String responseField(Throwable failure) {
        for (int i = 0; failure != null && i < 6; i++, failure = failure.getCause()) {
            if (failure instanceof cc.huevia.ptp.PtpResponseException)
                return " response=0x" + String.format(Locale.ROOT, "%04x", ((cc.huevia.ptp.PtpResponseException) failure).responseCode() & 0xffff);
        }
        return "";
    }

    static long nextConnectionId() { return IDS.incrementAndGet(); }

    static boolean isEnabled() { return enabled != null; }

    public static void originalSave(boolean complete) {
        State state = enabled;
        if (state != null) add(state, complete ? "ORIGINAL_PRIVATE_SAVE_COMPLETE" : "ORIGINAL_PRIVATE_SAVE_BEGIN", "", false);
    }

    /** Routine heartbeats share the normal batch; they must not force a disk write every tick. */
    public static void connectionHeartbeat(boolean queued, boolean failed) {
        State state = enabled;
        if (state != null) add(state, queued ? "CAMERA_HEARTBEAT_QUEUED"
                : failed ? "CAMERA_HEARTBEAT_FAILED" : "CAMERA_HEARTBEAT_COMPLETE", "", failed);
    }

    /** Numeric transfer evidence only; no handles, filenames, pixels, SSIDs, or exception text. */
    static void originalTransfer(long connection, long transaction, long started, long bytes, long total,
                                 long readNanos, long writeNanos, long callbackNanos, int timeouts,
                                 boolean complete, Throwable failure) {
        State state = enabled;
        if (state == null) return;
        String event = failure != null ? "PTP_ORIGINAL_FAILED" : complete ? "PTP_ORIGINAL_COMPLETE" : "PTP_ORIGINAL_PROGRESS";
        String fields = " conn=" + Math.max(0, connection) + " op=0x1009 tx=" + Math.max(0, transaction)
                + " elapsed_ms=" + Math.max(0, (System.nanoTime() - started) / 1_000_000L)
                + " bytes=" + Math.max(0, bytes) + " total_bytes=" + Math.max(0, total)
                + " payload_read_ms=" + Math.max(0, readNanos / 1_000_000L)
                + " sink_write_ms=" + Math.max(0, writeNanos / 1_000_000L)
                + " progress_callback_ms=" + Math.max(0, callbackNanos / 1_000_000L)
                + " timeouts=" + Math.max(0, timeouts)
                + (failure == null ? "" : " category=" + category(failure));
        add(state, event, fields, failure != null);
    }

    static long operationStarted(long connection, int operation, long transaction) {
        long start = System.nanoTime();
        structured("PTP_OP_BEGIN", connection, operation, transaction, -1, null);
        return start;
    }

    static void operationFinished(long connection, int operation, long transaction, long started, Throwable failure) {
        long millis = Math.max(0, (System.nanoTime() - started) / 1_000_000L);
        structured(failure == null ? "PTP_OP_COMPLETE" : "PTP_OP_FAILED", connection, operation, transaction,
                millis, failure == null ? null : category(failure), responseField(failure));
    }

    static void pingReplied(long connection, boolean eventChannel) {
        structured(eventChannel ? "PTP_EVENT_PING_REPLY" : "PTP_COMMAND_PING_REPLY", connection, -1, -1, -1, null);
    }

    static void closed(long connection, String category) {
        structured("PTP_CLOSED", connection, -1, -1, -1, category);
    }

    static void channelFailed(long connection, boolean eventChannel, Throwable failure) {
        structured(eventChannel ? "PTP_EVENT_CHANNEL_FAILED" : "PTP_COMMAND_CHANNEL_FAILED",
                connection, -1, -1, -1, category(failure));
    }

    static String category(Throwable failure) {
        if (Thread.currentThread().isInterrupted()) return "CANCEL";
        for (int i = 0; failure != null && i < 6; i++, failure = failure.getCause()) {
            if (failure instanceof InterruptedException || failure instanceof java.io.InterruptedIOException
                    && !(failure instanceof SocketTimeoutException)) return "CANCEL";
            if (failure instanceof SocketTimeoutException) return "TIMEOUT";
            if (failure instanceof EOFException) return "EOF";
            if (failure instanceof java.net.NoRouteToHostException) return "NO_ROUTE";
            if (failure instanceof java.net.ConnectException) return "REFUSED";
            if (failure instanceof SecurityException) return "PERMISSION";
            if (failure instanceof cc.huevia.ptp.PtpProtocolException) return "PROTOCOL";
        }
        return "IO";
    }

    private static void structured(String event, long connection, int operation, long transaction, long elapsed, String category) {
        structured(event, connection, operation, transaction, elapsed, category, "");
    }

    private static void structured(String event, long connection, int operation, long transaction, long elapsed, String category, String response) {
        State state = enabled;
        if (state == null) return;
        StringBuilder fields = new StringBuilder(100).append(" conn=").append(Math.max(0, connection));
        if (operation >= 0) fields.append(" op=0x").append(String.format(Locale.ROOT, "%04x", operation & 0xffff))
                .append(" tx=").append(Math.max(0, transaction));
        if (elapsed >= 0) fields.append(" elapsed_ms=").append(elapsed);
        fields.append(response);
        if (category != null) {
            if (!category.equals("EOF") && !category.equals("TIMEOUT") && !category.equals("IO") && !category.equals("CANCEL")
                    && !category.equals("EXPLICIT") && !category.equals("PROTOCOL") && !category.equals("REFUSED")
                    && !category.equals("NO_ROUTE") && !category.equals("PERMISSION")) category = "IO";
            fields.append(" category=").append(category);
        }
        add(state, event, fields.toString(), event.equals("PTP_OP_FAILED") || event.equals("PTP_CLOSED"));
    }

    private static void add(State state, String event, String fields, boolean urgent) {
        // Capture clocks before enqueueing so a slow disk cannot change the observed event order.
        String line = "wall_ms=" + System.currentTimeMillis() + " mono_ms=" + Math.max(0, System.nanoTime() / 1_000_000L)
                + " event=" + event + fields;
        synchronized (state) {
            if (enabled != state) return;
            state.lines.addLast(line);
            trimLines(state.lines);
            state.revision++;
            state.urgent |= urgent;
            if (!state.loaded || state.writing) return;
            scheduleLocked(state, urgent);
        }
    }

    /** One delayed normal batch, or one immediate urgent batch; never one disk task per PTP event. */
    private static void scheduleLocked(State state, boolean urgent) {
        if (enabled != state || state.writing) return;
        if (state.pending != null) {
            if (!urgent) return;
            state.pending.cancel(false); state.pending = null;
        }
        long ticket = ++state.ticket;
        long elapsed = System.nanoTime() - state.lastWrite;
        long delay = urgent || state.lastWrite == 0 ? 0 : Math.max(0, NORMAL_FLUSH_NANOS - elapsed);
        try { state.pending = WRITER.schedule(() -> writeBatch(state, ticket), delay, TimeUnit.NANOSECONDS); }
        catch (RuntimeException unavailable) { state.pending = null; }
    }

    private static void loadAndWrite(State state) {
        List<String> previous = readPrevious(state.file);
        synchronized (state) {
            if (enabled != state) return;
            ArrayDeque<String> merged = new ArrayDeque<>(previous);
            merged.addAll(state.lines);
            trimLines(merged);
            state.lines.clear(); state.lines.addAll(merged);
            state.loaded = true;
            state.urgent = true;
            scheduleLocked(state, true);
        }
    }

    private static List<String> readPrevious(File file) {
        List<String> lines = new ArrayList<>();
        try {
            if (!file.isFile() || file.length() > MAX_BYTES) return lines;
            try (FileInputStream input = new FileInputStream(file); ByteArrayOutputStream bytes = new ByteArrayOutputStream()) {
                byte[] buffer = new byte[4096]; int count;
                while ((count = input.read(buffer)) >= 0) {
                    if (bytes.size() + count > MAX_BYTES) return new ArrayList<>();
                    bytes.write(buffer, 0, count);
                }
                for (String line : bytes.toString(StandardCharsets.UTF_8.name()).split("\n")) {
                    if (line.length() <= MAX_LINE_LENGTH && LINE.matcher(line).matches()) lines.add(line);
                }
            }
        } catch (IOException | RuntimeException ignored) { }
        return lines;
    }

    private static void writeBatch(State state, long ticket) {
        String text; long revision;
        synchronized (state) {
            if (enabled != state || state.ticket != ticket) return;
            state.pending = null; state.writing = true; state.urgent = false;
            text = joined(state.lines); revision = state.revision;
        }
        try {
            byte[] bytes = text.getBytes(StandardCharsets.UTF_8);
            if (bytes.length > MAX_BYTES) return; // The fixed schema also bounds individual entries.
            File parent = state.file.getParentFile();
            if (parent != null && !parent.isDirectory() && !parent.mkdirs()) throw new IOException("Trace directory unavailable");
            File temporary = new File(parent, state.file.getName() + ".tmp");
            try (FileOutputStream output = new FileOutputStream(temporary)) {
                output.write(bytes); output.getFD().sync();
            }
            if (enabled == state) Files.move(temporary.toPath(), state.file.toPath(), StandardCopyOption.REPLACE_EXISTING);
            else temporary.delete();
        } catch (IOException | RuntimeException ignored) { /* Diagnostics must never terminate a connection. */ }
        finally {
            synchronized (state) {
                state.lastWrite = System.nanoTime(); state.attemptedRevision = revision; state.writing = false;
                if (enabled == state && revision != state.revision) scheduleLocked(state, state.urgent);
                state.notifyAll();
            }
        }
    }

    private static void trimLines(ArrayDeque<String> lines) {
        // The fixed schema is ASCII, so character lengths equal UTF-8 byte lengths.
        int bytes = 0;
        for (String line : lines) bytes += line.length() + 1;
        int diagnostics = 0;
        for (String line : lines) if (line.contains(" event=DIAG_")) diagnostics++;
        while (lines.size() > MAX_EVENTS || bytes > MAX_BYTES) {
            // Keep up to 64 recent setup/browse records when routine heartbeats fill the ring.
            java.util.Iterator<String> iterator = lines.iterator();
            while (iterator.hasNext()) {
                String line = iterator.next(); boolean diagnostic = line.contains(" event=DIAG_");
                if (diagnostic && diagnostics <= 64) continue;
                iterator.remove(); bytes -= line.length() + 1; if (diagnostic) diagnostics--; break;
            }
        }
    }

    private static String joined(Iterable<String> lines) {
        StringBuilder text = new StringBuilder();
        for (String line : lines) text.append(line).append('\n');
        return text.toString();
    }

    private static final class State {
        final File file;
        final ArrayDeque<String> lines = new ArrayDeque<>();
        String lastDiagnosticReason = "";
        long revision, attemptedRevision, lastWrite, ticket;
        boolean loaded, writing, urgent;
        ScheduledFuture<?> pending;
        State(File file) { this.file = file; }
    }
}
