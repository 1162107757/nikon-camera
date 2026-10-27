package cc.huevia.album;

import java.util.ArrayDeque;
import java.util.Locale;
import java.util.concurrent.TimeUnit;

/** Display estimates from delivered bytes and a monotonic clock; never controls camera traffic. */
public final class PhotoTransferProgress {
    private static final long WINDOW_MILLIS = 5000;
    public static final long WAIT_MILLIS = 5000;
    public static long now() { return TimeUnit.NANOSECONDS.toMillis(System.nanoTime()); }

    public static final class Snapshot {
        public static final Snapshot EMPTY = new Snapshot(false, 0, 0, 0, 0, 0, 0, 0);
        public final boolean started;
        public final long received, total, elapsedMillis, lastByteAt, sampledAt;
        public final double bytesPerSecond, averageBytesPerSecond;
        private Snapshot(boolean started, long received, long total, long elapsedMillis, long lastByteAt,
                         long sampledAt, double rate, double average) {
            this.started = started; this.received = received; this.total = total; this.elapsedMillis = elapsedMillis;
            this.lastByteAt = lastByteAt; this.sampledAt = sampledAt;
            bytesPerSecond = rate; averageBytesPerSecond = average;
        }
        public boolean complete() { return started && total > 0 && received >= total; }
        public boolean waiting(long now) { return started && !complete() && now - lastByteAt >= WAIT_MILLIS; }
        public long remainingSeconds() {
            if (total <= received || bytesPerSecond <= 0) return -1;
            return (long) Math.ceil((total - received) / bytesPerSecond);
        }
        public String compact(long now) {
            if (!started) return "准备接收";
            if (complete()) return "保存中";
            if (waiting(now)) return "等待相机";
            if (bytesPerSecond <= 0) return "接收中";
            long seconds = remainingSeconds();
            return rate(bytesPerSecond) + (seconds < 0 ? "" : " · " + remaining(seconds));
        }
        public String details(long now) {
            if (!started) return "等待开始接收原图。";
            long elapsed = elapsedMillis + (complete() ? 0 : Math.max(0, now - sampledAt));
            String result = "接收耗时 " + (elapsed / 1000) + " 秒";
            if (averageBytesPerSecond > 0) result += "\n平均速度 " + rate(received * 1000.0 / Math.max(1, elapsed));
            if (waiting(now)) result += "\n距上次收到数据 " + Math.max(0, (now - lastByteAt) / 1000) + " 秒";
            return result + "\n速度按接收字节估算；剩余时间会随传输变化。";
        }
    }

    private static final class Sample {
        final long at, bytes;
        Sample(long at, long bytes) { this.at = at; this.bytes = bytes; }
    }
    private final ArrayDeque<Sample> samples = new ArrayDeque<>();
    private boolean started;
    private long beganAt, lastByteAt, received, total;

    public void reset() { started = false; received = total = 0; samples.clear(); }
    public void start(long total, long now) {
        reset(); started = true; beganAt = lastByteAt = now; this.total = Math.max(0, total);
        samples.add(new Sample(now, 0));
    }
    public void update(long bytes, long expected, long now) {
        if (!started) start(expected, now);
        now = Math.max(now, samples.getLast().at);
        if (expected > 0) total = expected;
        bytes = Math.max(received, Math.max(0, bytes));
        if (bytes > received) lastByteAt = now;
        received = bytes;
        if (samples.size() > 1 && samples.getLast().at == now) samples.removeLast();
        samples.addLast(new Sample(now, received));
        while (samples.size() > 2) {
            Sample first = samples.removeFirst();
            if (samples.getFirst().at > now - WINDOW_MILLIS) { samples.addFirst(first); break; }
        }
        // Progress is normally delivered every 200 ms; also bound callers that report much more frequently.
        while (samples.size() > 64) samples.removeFirst();
    }
    public Snapshot snapshot(long now) {
        if (!started) return Snapshot.EMPTY;
        now = Math.max(now, samples.getLast().at);
        long elapsed = Math.max(0, now - beganAt);
        Sample first = samples.getFirst();
        double rate = elapsed >= 1000 && received >= 8192 && now > first.at
                ? (received - first.bytes) * 1000.0 / (now - first.at) : 0;
        return new Snapshot(true, received, total, elapsed, lastByteAt, now, rate,
                elapsed > 0 ? received * 1000.0 / elapsed : 0);
    }
    public static String rate(double bytesPerSecond) {
        if (bytesPerSecond >= 1000000) return String.format(Locale.ROOT, "%.1f MB/s", bytesPerSecond / 1000000);
        if (bytesPerSecond < 1000) return String.format(Locale.ROOT, "%.0f B/s", Math.max(0, bytesPerSecond));
        return String.format(Locale.ROOT, "%.0f KB/s", Math.max(0, bytesPerSecond / 1000));
    }
    private static String remaining(long seconds) {
        if (seconds < 60) return "剩余" + Math.max(1, seconds) + "秒";
        if (seconds < 3600) return "约" + (long) Math.ceil(seconds / 60.0) + "分钟";
        return "约" + (long) Math.ceil(seconds / 3600.0) + "小时";
    }
}
