package cc.huevia.sharedapp;

import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

/** Cancellation belongs to a running invocation, never to its delivered result. */
final class NativeTaskCancellation extends AtomicBoolean {
    private static final int ACTIVE = 0, CANCELLED = 1, FINISHED = 2;
    private final AtomicInteger phase = new AtomicInteger(ACTIVE);

    boolean cancelIfActive() {
        if (!phase.compareAndSet(ACTIVE, CANCELLED)) return false;
        set(true);
        return true;
    }

    void finish() {
        phase.set(FINISHED);
    }
}
