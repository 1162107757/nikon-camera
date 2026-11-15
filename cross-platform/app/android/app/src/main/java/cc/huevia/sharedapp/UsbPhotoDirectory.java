package cc.huevia.sharedapp;

import java.io.IOException;
import java.io.InterruptedIOException;
import java.util.Locale;
import java.util.Objects;
import java.util.function.LongSupplier;

/** Read-only MTP queries. The retry budget limits new calls, not an in-progress SDK operation. */
final class UsbPhotoDirectory {
    static final int MAX_ATTEMPTS = 3;
    static final int MAX_STORAGES = 64;
    static final int MAX_HANDLES = 20000;
    static final long RETRY_WINDOW_NANOS = 1000000000L;

    interface Reader {
        void checkCurrent() throws IOException;
        int[] getStorageIds() throws IOException;
        int[] getObjectHandles(int storageId, int format, int parent) throws IOException;
    }

    interface Backoff {
        void pause(long milliseconds) throws IOException;
    }

    private final Reader reader;
    private final Backoff backoff;
    private final LongSupplier clock;

    UsbPhotoDirectory(Reader reader) {
        this(reader, milliseconds -> {
            try {
                Thread.sleep(milliseconds);
            } catch (InterruptedException failure) {
                Thread.currentThread().interrupt();
                InterruptedIOException cancelled = new InterruptedIOException("USB 相机读取已取消。");
                cancelled.initCause(failure);
                throw cancelled;
            }
        });
    }

    UsbPhotoDirectory(Reader reader, Backoff backoff) {
        this(reader, backoff, System::nanoTime);
    }

    UsbPhotoDirectory(Reader reader, Backoff backoff, LongSupplier clock) {
        this.reader = Objects.requireNonNull(reader, "reader");
        this.backoff = Objects.requireNonNull(backoff, "backoff");
        this.clock = Objects.requireNonNull(clock, "clock");
    }

    int[] storageIds() throws IOException {
        String stage = "getStorageIds";
        long started = clock.getAsLong();
        for (int attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
            int[] values = read(stage, attempt, reader::getStorageIds, started, attempt > 1);
            if (values != null) {
                if (values.length > MAX_STORAGES) {
                    throw failure("USB 相机存储数量超出支持范围。", stage, attempt,
                            "count=" + values.length, null);
                }
                // As in the preserved USB probe, logical ID zero denotes an unmounted slot.
                int mounted = 0;
                for (int value : values) if ((value & 0xffff) != 0) mounted++;
                if (values.length > 0 && mounted == 0) {
                    throw failure("USB 相机没有可读存储卡，请检查后重试。", stage, attempt,
                            "all-logical-storages-unmounted count=" + values.length, null);
                }
                int[] result = new int[mounted];
                int index = 0;
                for (int value : values) if ((value & 0xffff) != 0) result[index++] = value;
                check(stage, attempt);
                return result; // An actual empty array is successful, not a failed/null read.
            }
            if (attempt == MAX_ATTEMPTS || !withinWindow(started)) {
                throw failure("USB 相机存储暂不可读，请稍后重试。", stage, attempt,
                        withinWindow(started) ? "null-result" : "null-result retry-window-exhausted", null);
            }
            pause(stage, attempt);
        }
        throw failure("USB 相机存储暂不可读，请稍后重试。", stage, MAX_ATTEMPTS,
                "null-result", null);
    }

    int[] objectHandles(int storageId, int requestedFormat, int parent) throws IOException {
        int format = requestedFormat;
        long started = clock.getAsLong();
        for (int attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
            String stage = handlesStage(storageId, requestedFormat, format, parent);
            final int queryFormat = format;
            int[] values = read(stage, attempt,
                    () -> reader.getObjectHandles(storageId, queryFormat, parent), started, attempt > 1);
            if (values == null && format != 0 && withinWindow(started)) {
                // Fall back once; subsequent attempts remain unfiltered.
                format = 0;
                stage = handlesStage(storageId, requestedFormat, format, parent);
                values = read(stage, attempt, () -> reader.getObjectHandles(storageId, 0, parent),
                        started, true);
            }
            if (values != null) {
                if (values.length > MAX_HANDLES) {
                    throw failure("USB 相机目录超出本版读取范围。", stage, attempt,
                            "count=" + values.length, null);
                }
                int[] result = values.clone();
                check(stage, attempt);
                return result;
            }
            if (attempt == MAX_ATTEMPTS || !withinWindow(started)) {
                throw failure("USB 相机目录暂不可读，请稍后重试。", stage, attempt,
                        withinWindow(started) ? "null-result" : "null-result retry-window-exhausted", null);
            }
            pause(stage, attempt);
        }
        throw failure("USB 相机目录暂不可读，请稍后重试。",
                handlesStage(storageId, requestedFormat, format, parent), MAX_ATTEMPTS,
                "null-result", null);
    }

    private interface Query { int[] read() throws IOException; }

    private int[] read(String stage, int attempt, Query query, long started, boolean retry)
            throws IOException {
        check(stage, attempt);
        if (retry && !withinWindow(started)) {
            throw failure(stage.equals("getStorageIds")
                            ? "USB 相机存储暂不可读，请稍后重试。" : "USB 相机目录暂不可读，请稍后重试。",
                    stage, attempt, "retry-window-exhausted", null);
        }
        final int[] result;
        try {
            result = query.read();
        } catch (IOException | RuntimeException error) {
            check(stage, attempt);
            throw failure("USB 相机目录暂不可读，请稍后重试。", stage, attempt,
                    "read-failed", error);
        }
        check(stage, attempt);
        return result;
    }

    private boolean withinWindow(long started) {
        return clock.getAsLong() - started < RETRY_WINDOW_NANOS;
    }

    private void pause(String stage, int attempt) throws IOException {
        check(stage, attempt);
        try {
            backoff.pause(attempt * 100L);
        } catch (IOException error) {
            throw failure("USB 相机读取已取消。", stage, attempt, "backoff-interrupted", error);
        }
        check(stage, attempt);
    }

    private void check(String stage, int attempt) throws IOException {
        if (Thread.currentThread().isInterrupted()) {
            throw failure("USB 相机读取已取消。", stage, attempt, "thread-interrupted", null);
        }
        try {
            reader.checkCurrent();
        } catch (IOException | RuntimeException error) {
            throw failure("USB 相机连接已改变，请重新连接。", stage, attempt,
                    "stale-client", error);
        }
    }

    private static String handlesStage(int storage, int requested, int format, int parent) {
        return String.format(Locale.ROOT,
                "getObjectHandles storage=0x%08x requestedFormat=0x%04x format=0x%04x parent=0x%08x",
                storage, requested, format, parent);
    }

    private static IOException failure(String message, String stage, int attempt,
                                       String result, Throwable error) {
        IOException diagnostic = new IOException(
                "USB_DIRECTORY stage=" + stage + " attempt=" + attempt + " result=" + result,
                error);
        return new IOException(message, diagnostic);
    }
}
