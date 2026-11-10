package cc.huevia.library;

import java.io.File;
import java.io.IOException;
import java.io.InterruptedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.Arrays;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.FutureTask;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

/** Disk/network orchestration tests; actual Android image decoding retains PreviewImages validation. */
public final class PreviewImageCacheTest {
    private static int checks;
    private static final byte[] IMAGE = {42, 1, 2, 3};
    private static final PreviewImageCache.Validator VALIDATOR = bytes -> {
        if (bytes[0] != 42) throw new IOException("invalid image");
    };
    private static File scratch;

    public static void main(String[] args) throws Exception {
        scratch = new File(args[0]); scratch.mkdirs();
        persistentAndChanged(); invalidAndFailures(); boundedAndSaved(); singleFlight();
        System.out.println("Online sample image cache: " + checks + " checks passed (no network I/O).");
    }

    private static PreviewImageCache cache(File root, long bytes, int count) throws IOException {
        return new PreviewImageCache(new File(root, "cache"), new File(root, "saved"), 16, VALIDATOR, bytes, count);
    }
    private static File fresh() throws IOException { return Files.createTempDirectory(scratch.toPath(), "images-").toFile(); }
    private static File file(File root, String dir, String url) {
        return new File(root, dir + "/" + LibraryFiles.sha256(url.getBytes(StandardCharsets.UTF_8)) + ".image");
    }
    private static PreviewImageCache.Fetcher offline() { return () -> { throw new IOException("offline"); }; }
    private static synchronized void yes(boolean value, String why) {
        checks++; if (!value) throw new AssertionError(why);
    }
    private static void fail(PreviewImageCache cache, String url, PreviewImageCache.Fetcher fetcher) throws Exception {
        try { cache.read(url, fetcher); throw new AssertionError("expected IOException"); }
        catch (IOException expected) { yes(true, "expected I/O failure"); }
    }

    private static void persistentAndChanged() throws Exception {
        File root = fresh(); AtomicInteger calls = new AtomicInteger();
        PreviewImageCache.Fetcher fetch = () -> { calls.incrementAndGet(); return IMAGE.clone(); };
        PreviewImageCache first = cache(root, 100, 10);
        byte[] read = first.read("https://example.test/a.jpg", fetch); read[0] = 0;
        yes(Arrays.equals(IMAGE, first.read("https://example.test/a.jpg", offline())), "repeat read is detached and offline");
        yes(Arrays.equals(IMAGE, cache(root, 100, 10).read("https://example.test/a.jpg", offline())), "disk cache survives repository restart");
        yes(calls.get() == 1, "repeated reads transfer once");
        first.read("https://example.test/b.jpg", fetch);
        yes(calls.get() == 2, "changed asset URL requests new sample");
        Files.write(file(root, "cache", "https://example.test/a.jpg").toPath(), new byte[]{0});
        yes(Arrays.equals(IMAGE, first.read("https://example.test/a.jpg", fetch)), "corrupt cache is repaired");
        yes(calls.get() == 3, "corruption causes one refetch");
    }

    private static void invalidAndFailures() throws Exception {
        File root = fresh(); PreviewImageCache cache = cache(root, 100, 10); AtomicInteger calls = new AtomicInteger();
        for (int i = 0; i < 2; i++) fail(cache, "invalid", () -> { calls.incrementAndGet(); return new byte[]{0}; });
        yes(calls.get() == 2 && !file(root, "cache", "invalid").exists(), "invalid responses are never cached");
        fail(cache, "large", () -> new byte[17]);
        fail(cache, "empty", () -> new byte[0]);
        fail(cache, "retry", offline());
        yes(Arrays.equals(IMAGE, cache.read("retry", () -> IMAGE.clone())), "failed transfer can retry");
        File blocked = fresh(); Files.write(new File(blocked, "cache").toPath(), new byte[]{1});
        yes(Arrays.equals(IMAGE, cache(blocked, 100, 10).read("a", () -> IMAGE.clone())), "cache write failure still displays a downloaded sample");
    }

    private static void boundedAndSaved() throws Exception {
        File root = fresh(); PreviewImageCache cache = cache(root, 8, 10);
        cache.read("a", () -> IMAGE.clone()); cache.read("b", () -> IMAGE.clone());
        yes(file(root, "cache", "a").setLastModified(1), "seed oldest timestamp");
        yes(file(root, "cache", "b").setLastModified(2), "seed newer timestamp");
        cache.read("a", offline()); // Touch a; b becomes the least recently used.
        File unrelated = new File(root, "cache/user-note.txt"); Files.write(unrelated.toPath(), new byte[50]);
        File saved = file(root, "saved", "saved"); LibraryFiles.atomicWrite(saved, IMAGE);
        cache.read("c", () -> IMAGE.clone());
        yes(file(root, "cache", "a").isFile() && !file(root, "cache", "b").exists(), "byte budget evicts least recently used");
        yes(file(root, "cache", "c").isFile(), "new response survives trimming");
        yes(unrelated.isFile() && saved.isFile(), "unrelated and saved user files survive eviction");
        yes(Arrays.equals(IMAGE, cache.read("saved", offline())), "existing saved samples work offline");
        yes(!file(root, "cache", "saved").exists(), "saved sample is reused without duplicating cache storage");
        File countRoot = fresh(); PreviewImageCache countCache = cache(countRoot, 1000, 2);
        countCache.read("a", () -> IMAGE.clone()); file(countRoot, "cache", "a").setLastModified(1);
        countCache.read("b", () -> IMAGE.clone()); file(countRoot, "cache", "b").setLastModified(2);
        countCache.read("c", () -> IMAGE.clone());
        yes(!file(countRoot, "cache", "a").exists(), "file count is bounded independently of byte budget");
    }

    private static void singleFlight() throws Exception {
        File root = fresh(); AtomicInteger calls = new AtomicInteger(); CountDownLatch fetching = new CountDownLatch(1), release = new CountDownLatch(1);
        PreviewImageCache first = cache(root, 100, 10), second = cache(root, 100, 10);
        PreviewImageCache.Fetcher slow = () -> {
            calls.incrementAndGet(); fetching.countDown(); await(release); return IMAGE.clone();
        };
        FutureTask<byte[]> owner = new FutureTask<>(() -> first.read("shared", slow));
        Thread ownerThread = new Thread(owner, "image-owner"); ownerThread.start();
        yes(fetching.await(5, TimeUnit.SECONDS), "owner starts transfer");
        FutureTask<byte[]> waiter = new FutureTask<>(() -> second.read("shared", slow));
        Thread waiterThread = new Thread(waiter, "image-waiter"); waiterThread.start();
        try {
            waitUntilWaiting(waiterThread);
            yes(calls.get() == 1, "separate repository instances coalesce concurrent requests");
        } finally { release.countDown(); }
        byte[] a = owner.get(5, TimeUnit.SECONDS), b = waiter.get(5, TimeUnit.SECONDS);
        yes(a != b && Arrays.equals(a, b), "concurrent callers receive independent buffers");

        CountDownLatch retryStarted = new CountDownLatch(1), retryRelease = new CountDownLatch(1);
        AtomicInteger failedCalls = new AtomicInteger();
        PreviewImageCache.Fetcher failing = () -> { failedCalls.incrementAndGet(); retryStarted.countDown(); await(retryRelease); throw new IOException("failed"); };
        FutureTask<Boolean> failedOwner = new FutureTask<>(() -> { fail(first, "failed-flight", failing); return true; });
        new Thread(failedOwner, "failed-owner").start();
        yes(retryStarted.await(5, TimeUnit.SECONDS), "failed flight starts");
        FutureTask<Boolean> failedWaiter = new FutureTask<>(() -> { fail(second, "failed-flight", failing); return true; });
        Thread failedThread = new Thread(failedWaiter, "failed-waiter"); failedThread.start();
        try { waitUntilWaiting(failedThread); } finally { retryRelease.countDown(); }
        failedOwner.get(5, TimeUnit.SECONDS); failedWaiter.get(5, TimeUnit.SECONDS);
        yes(failedCalls.get() == 1, "concurrent failures also share one transfer");
        yes(Arrays.equals(IMAGE, second.read("failed-flight", () -> IMAGE.clone())), "failed flight is released for retry");

        CountDownLatch entered = new CountDownLatch(1), finish = new CountDownLatch(1);
        FutureTask<byte[]> active = new FutureTask<>(() -> first.read("interrupt", () -> { entered.countDown(); await(finish); return IMAGE.clone(); }));
        new Thread(active, "interrupt-owner").start();
        yes(entered.await(5, TimeUnit.SECONDS), "interrupt owner starts");
        FutureTask<Boolean> cancelled = new FutureTask<>(() -> {
            try { second.read("interrupt", offline()); return false; }
            catch (InterruptedIOException expected) { return Thread.currentThread().isInterrupted(); }
        });
        Thread interrupted = new Thread(cancelled, "interrupt-waiter"); interrupted.start();
        try {
            waitUntilWaiting(interrupted); interrupted.interrupt();
            yes(cancelled.get(5, TimeUnit.SECONDS), "cancelled waiter preserves interrupt without cancelling shared work");
        } finally { finish.countDown(); }
        yes(Arrays.equals(IMAGE, active.get(5, TimeUnit.SECONDS)), "owner completes after waiter cancellation");
    }

    private static void await(CountDownLatch latch) throws IOException {
        try { if (!latch.await(5, TimeUnit.SECONDS)) throw new IOException("test latch timeout"); }
        catch (InterruptedException e) { Thread.currentThread().interrupt(); throw new InterruptedIOException(); }
    }
    private static void waitUntilWaiting(Thread thread) throws Exception {
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5);
        while (thread.getState() != Thread.State.WAITING && thread.isAlive() && System.nanoTime() < deadline) Thread.sleep(2);
        yes(thread.getState() == Thread.State.WAITING, "concurrent waiter joined in-flight request");
    }
}
