package cc.huevia.sharedapp;

import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

/** Host-runnable tests of the production Android task flag, without Android stubs. */
public final class NativeTaskCancellationBoundaryTest {
    private static int checks;
    private static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
        checks++;
    }

    private static void cancel(ConcurrentHashMap<String,NativeTaskCancellation> tasks,
                               String id, AtomicInteger closes) {
        NativeTaskCancellation task = tasks.get(id);
        if (task != null && task.cancelIfActive()) closes.incrementAndGet();
    }

    public static void main(String[] args) throws Exception {
        NativeTaskCancellation active = new NativeTaskCancellation();
        require(active.cancelIfActive() && active.get(), "active I/O must receive cancellation");
        require(!active.cancelIfActive(), "duplicate cancellation must not close twice");
        active.finish();
        require(!active.cancelIfActive() && active.get(), "finishing must retain the cancelled result");

        ConcurrentHashMap<String,NativeTaskCancellation> tasks = new ConcurrentHashMap<>();
        AtomicInteger closes = new AtomicInteger();
        NativeTaskCancellation old = new NativeTaskCancellation();
        tasks.put("camera-connect", old);
        old.finish(); // The GUI result has not been delivered, so the map still contains it.
        cancel(tasks, "camera-connect", closes);
        cancel(tasks, "unknown", closes);
        require(closes.get() == 0 && !old.get(), "completed/unknown tasks must not touch a camera");

        NativeTaskCancellation replacement = new NativeTaskCancellation();
        tasks.put("camera-connect", replacement);
        require(!tasks.remove("camera-connect", old), "old delivery must not remove a replacement");
        require(tasks.get("camera-connect") == replacement && !old.cancelIfActive(),
                "a stale task must not own the new session");
        cancel(tasks, "camera-connect", closes);
        cancel(tasks, "camera-connect", closes);
        require(closes.get() == 1 && replacement.get(), "the replacement owns exactly one close");

        NativeTaskCancellation reading = new NativeTaskCancellation();
        CountDownLatch started = new CountDownLatch(1), interrupted = new CountDownLatch(1);
        AtomicInteger readCancelled = new AtomicInteger();
        Thread worker = new Thread(() -> {
            started.countDown();
            try {
                if (interrupted.await(3, TimeUnit.SECONDS) && reading.get()) readCancelled.incrementAndGet();
            } catch (InterruptedException failure) { throw new AssertionError(failure); }
        });
        worker.start();
        require(started.await(3, TimeUnit.SECONDS), "I/O worker did not start");
        if (reading.cancelIfActive()) interrupted.countDown();
        worker.join(4000);
        require(!worker.isAlive() && readCancelled.get() == 1, "active cancellation must wake the I/O owner");
        reading.finish();

        for (int i = 0; i < 100; i++) {
            NativeTaskCancellation racing = new NativeTaskCancellation();
            CountDownLatch ready = new CountDownLatch(1);
            AtomicInteger callbacks = new AtomicInteger();
            Thread finisher = new Thread(() -> {
                try { ready.await(); } catch (InterruptedException failure) { throw new AssertionError(failure); }
                racing.finish();
            });
            Thread canceller = new Thread(() -> {
                try { ready.await(); } catch (InterruptedException failure) { throw new AssertionError(failure); }
                if (racing.cancelIfActive()) callbacks.incrementAndGet();
            });
            finisher.start(); canceller.start(); ready.countDown();
            finisher.join(3000); canceller.join(3000);
            require(!finisher.isAlive() && !canceller.isAlive(), "task transition must not deadlock");
            require(callbacks.get() <= 1 && racing.get() == (callbacks.get() == 1),
                    "completion/cancellation must have a single transition winner");
            require(!racing.cancelIfActive(), "a completed race cannot cancel again");
        }
        System.out.println("NativeTaskCancellation: " + checks + " checks passed; active, duplicate, completed, unknown, replacement, I/O wake and 100 transition races");
    }
}
