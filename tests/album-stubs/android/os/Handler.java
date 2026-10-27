package android.os;

/** Callbacks execute immediately in host tests; tests await completion using latches. */
public final class Handler {
    private static final java.util.ArrayDeque<Runnable> pending = new java.util.ArrayDeque<>();
    private static boolean paused;
    public Handler(Looper looper) { }
    public boolean post(Runnable runnable) {
        synchronized (pending) { if (paused) { pending.addLast(runnable); return true; } }
        runnable.run(); return true;
    }
    public static void pauseForTests() { synchronized (pending) { paused = true; } }
    public static void resumeForTests() {
        java.util.ArrayList<Runnable> ready;
        synchronized (pending) { paused = false; ready = new java.util.ArrayList<>(pending); pending.clear(); }
        ready.forEach(Runnable::run);
    }
}
