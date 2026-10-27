package android.os;
import java.util.concurrent.ConcurrentLinkedQueue;
public final class Handler {
    private static final ConcurrentLinkedQueue<Runnable> QUEUE = new ConcurrentLinkedQueue<>();
    public Handler(Looper ignored) {}
    public boolean post(Runnable value) { QUEUE.add(value); return true; }
    public boolean postDelayed(Runnable value, long delay) { return true; }
    public void removeCallbacks(Runnable ignored) {}
    public void removeCallbacksAndMessages(Object ignored) {}
    public static void drain() { Runnable task; while ((task = QUEUE.poll()) != null) task.run(); }
}
