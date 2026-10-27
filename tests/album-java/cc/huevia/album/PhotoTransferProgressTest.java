package cc.huevia.album;

public final class PhotoTransferProgressTest {
    private static int checks;
    private static void check(boolean ok, String message) { checks++; if (!ok) throw new AssertionError(message); }
    private static void near(double actual, double expected, String message) { check(Math.abs(actual - expected) < .01, message + ": " + actual); }
    public static void main(String[] args) {
        PhotoTransferProgress p = new PhotoTransferProgress();
        check(p.snapshot(0).compact(0).equals("准备接收"), "Queued tasks do not invent a transfer rate");
        p.start(10000000, 0); p.update(100000, 10000000, 200);
        check(p.snapshot(200).bytesPerSecond == 0, "No unstable ETA from the first small sample");
        p.update(800000, 10000000, 1000);
        PhotoTransferProgress.Snapshot s = p.snapshot(1000);
        near(s.bytesPerSecond, 800000, "Rate follows received bytes and monotonic elapsed time");
        check(s.remainingSeconds() == 12, "Remaining time rounds up");
        check(s.compact(1000).equals("800 KB/s · 剩余12秒"), "Compact line shows measured rate and ETA");
        check(!s.waiting(5999) && s.waiting(6000), "Silence is detected without receiving another callback");
        check(s.compact(6000).equals("等待相机"), "A stale snapshot never shows a convincing moving ETA");
        p.update(800000, 10000000, 6000);
        check(p.snapshot(6000).waiting(6000), "Repeated byte counts are not mistaken for incoming data");
        p.update(1600000, 10000000, 7000);
        check(!p.snapshot(7000).waiting(7000), "Incoming data clears the wait status");
        check(p.snapshot(7000).bytesPerSecond < 300000, "The speed window includes the quiet interval");
        p.start(20000000, 10000); p.update(4000000, 20000000, 12000);
        s = p.snapshot(12000);
        near(s.bytesPerSecond, 2000000, "New photo clears previous samples");
        check(s.compact(12000).equals("2.0 MB/s · 剩余8秒"), "Decimal MB/s units are explicit");
        p.update(3000000, 20000000, 11000);
        check(p.snapshot(12000).received == 4000000, "Out-of-order counters cannot move progress backwards");
        p.update(20000000, 20000000, 20000); s = p.snapshot(20000);
        check(s.complete() && !s.waiting(90000) && s.compact(90000).equals("保存中"), "Finished byte reception waits for durable save, not more camera data");
        check(s.details(90000).contains("10 秒"), "Completed reception duration does not grow after the read");
        p.start(0, 0); p.update(100000, 0, 1000);
        check(p.snapshot(1000).remainingSeconds() == -1 && !p.snapshot(1000).compact(1000).contains("剩余"), "Unknown totals have no fabricated ETA");
        p.update(200000, 400000, 2000);
        check(p.snapshot(2000).remainingSeconds() == 2, "A late known size enables ETA");
        p.start(20000000, 0); p.update(100000, 20000000, 1000);
        check(p.snapshot(1000).compact(1000).contains("约4分钟"), "Long durations stay short");
        p.start(1000000000, 0); p.update(10000, 1000000000, 1000);
        check(p.snapshot(1000).compact(1000).contains("小时"), "Very slow transfers do not create long labels");
        p.reset(); check(!p.snapshot(2000).started, "Reset removes stale speed");
        p.start(10000000, 0); p.update(1000000, 10000000, 0); p.update(2000000, 10000000, 1000);
        near(p.snapshot(1000).bytesPerSecond, 2000000, "Immediate first packet retains the zero-byte baseline");
        p.start(100000000, 0);
        for(int i=1;i<=20000;i++)p.update(i*1000L,100000000,i);
        check(Double.isFinite(p.snapshot(20000).bytesPerSecond) && p.snapshot(20000).bytesPerSecond>0, "High-frequency progress stays bounded and valid");
        check(PhotoTransferProgress.rate(200).equals("200 B/s"), "Tiny positive rates never round to a misleading zero KB/s");
        System.out.println("PhotoTransferProgressTest PASS " + checks + " checks");
    }
}
