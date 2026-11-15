package cc.huevia.sharedapp;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/** Runs the production directory helper on the host JVM, without Android or a test framework. */
public final class UsbPhotoDirectoryBoundaryTest {
    private static final int CARD = 0x00010001;
    private static final int EMPTY_SLOT = 0x00020000;
    private static final int JPEG = 0x3801;
    private static int checks;

    private interface Action { void run() throws Exception; }

    private static void require(boolean value, String message) {
        checks++;
        if (!value) throw new AssertionError(message);
    }

    private static IOException fails(Action action) throws Exception {
        checks++;
        try {
            action.run();
        } catch (IOException failure) {
            require(failure.getClass() == IOException.class,
                    "Android null must not be converted into a fabricated PTP response");
            require(!failure.getMessage().contains("0x") && !failure.getMessage().contains("stage="),
                    "technical query parameters belong in the cause, not the product message");
            require(failure.getCause() != null &&
                            failure.getCause().getMessage().startsWith("USB_DIRECTORY stage="),
                    "failure must retain an internal directory stage");
            return failure;
        }
        throw new AssertionError("The failing MTP query was reported as a successful empty directory");
    }

    private static final class Reply {
        final int[] values;
        long elapsedNanos;
        Runnable after;
        IOException error;
        Reply(int... values) { this.values = values; }
        Reply slow(long nanos) { elapsedNanos = nanos; return this; }
        Reply after(Runnable action) { after = action; return this; }
        Reply error(IOException failure) { error = failure; return this; }
    }

    private static Reply missing() { return new Reply((int[]) null); }

    private static final class Query {
        final int storage, format, parent;
        Query(int storage, int format, int parent) {
            this.storage = storage;
            this.format = format;
            this.parent = parent;
        }
    }

    private static final class Fake implements UsbPhotoDirectory.Reader {
        final Object expectedClient = new Object(), expectedMtp = new Object();
        Object activeClient = expectedClient, mtp = expectedMtp;
        boolean open = true, attached = true;
        int opens = 1, closes, storageCalls, guards;
        long now;
        final List<Reply> storageReplies = new ArrayList<>(), handleReplies = new ArrayList<>();
        final List<Query> queries = new ArrayList<>();
        final List<Long> sleeps = new ArrayList<>();
        Runnable afterPause;

        Fake storages(Reply... replies) { storageReplies.addAll(Arrays.asList(replies)); return this; }
        Fake handles(Reply... replies) { handleReplies.addAll(Arrays.asList(replies)); return this; }

        @Override public void checkCurrent() throws IOException {
            guards++;
            if (!open || !attached || activeClient != expectedClient || mtp != expectedMtp) {
                throw new IOException("injected owner/detach boundary");
            }
        }

        private int[] answer(List<Reply> replies, int index) throws IOException {
            if (index >= replies.size()) throw new AssertionError("Unexpected extra MTP query " + index);
            Reply reply = replies.get(index);
            now += reply.elapsedNanos;
            if (reply.after != null) reply.after.run();
            if (reply.error != null) throw reply.error;
            return reply.values;
        }

        @Override public int[] getStorageIds() throws IOException {
            return answer(storageReplies, storageCalls++);
        }

        @Override public int[] getObjectHandles(int storage, int format, int parent) throws IOException {
            int index = queries.size();
            queries.add(new Query(storage, format, parent));
            return answer(handleReplies, index);
        }

        UsbPhotoDirectory directory() {
            return new UsbPhotoDirectory(this, milliseconds -> {
                sleeps.add(milliseconds);
                now += milliseconds * 1000000L;
                if (afterPause != null) afterPause.run();
            }, () -> now);
        }

        void requireHealthy() {
            require(open && attached && activeClient == expectedClient && mtp == expectedMtp,
                    "directory reads must retain the same healthy client and MTP owner");
            require(opens == 1 && closes == 0, "directory failure must neither reopen nor close the session");
        }
    }

    private static void storageReadinessAndTwoSlots() throws Exception {
        Fake fake = new Fake().storages(missing(), new Reply(CARD, EMPTY_SLOT))
                .handles(new Reply(11, 12));
        UsbPhotoDirectory directory = fake.directory();
        int[] storages = directory.storageIds();
        require(Arrays.equals(storages, new int[]{CARD}), "one empty logical slot must not hide the mounted card");
        require(fake.storageCalls == 2 && fake.sleeps.equals(Arrays.asList(100L)),
                "a transient null must retry within the same owner with a short bounded backoff");
        for (int storage : storages) {
            require(Arrays.equals(directory.objectHandles(storage, JPEG, 0), new int[]{11, 12}),
                    "the mounted card must remain browsable");
        }
        require(fake.queries.size() == 1 && fake.queries.get(0).storage == CARD,
                "no object-handle request may target the known empty slot");
        require(fake.queries.get(0).parent == 0, "all-object parent zero must be preserved");
        fake.requireHealthy();

        Fake unavailable = new Fake().storages(new Reply(0x00010000, EMPTY_SLOT));
        IOException failure = fails(() -> unavailable.directory().storageIds());
        require(failure.getMessage().contains("没有可读存储卡"), "all unavailable slots need an explicit product state");
        require(unavailable.storageCalls == 1 && unavailable.sleeps.isEmpty() && unavailable.queries.isEmpty(),
                "known unmounted slots must not trigger directory requests or readiness retries");
        unavailable.requireHealthy();
    }

    private static void persistentNullDoesNotBecomeEmptyOrClose() throws Exception {
        Fake fake = new Fake().storages(missing(), missing(), missing(), new Reply(CARD))
                .handles(new Reply(31));
        UsbPhotoDirectory directory = fake.directory();
        IOException failure = fails(directory::storageIds);
        require(failure.getMessage().contains("存储"), "storage enumeration needs a distinct short message");
        require(failure.getCause().getMessage().contains("getStorageIds") &&
                        failure.getCause().getMessage().contains("attempt=3"),
                "persistent storage failure needs the actual stage and bounded attempt count");
        require(fake.storageCalls == 3 && fake.sleeps.equals(Arrays.asList(100L, 200L)),
                "persistent null storage must stop after three attempts");
        fake.requireHealthy();
        require(Arrays.equals(directory.storageIds(), new int[]{CARD}),
                "a later explicit retry must reuse the existing healthy session");
        require(Arrays.equals(directory.objectHandles(CARD, 0, 0), new int[]{31}),
                "a failed directory read must not prevent later browsing on the same session");
        fake.requireHealthy();
    }

    private static void emptyIsSuccessfulAndSnapshotsAreIndependent() throws Exception {
        Fake empty = new Fake().storages(new Reply()).handles(new Reply());
        require(empty.directory().storageIds().length == 0, "an actual empty storage list is valid");
        require(empty.directory().objectHandles(CARD, JPEG, 0).length == 0,
                "an actual empty handle list is valid even with a JPEG filter");
        require(empty.storageCalls == 1 && empty.queries.size() == 1 && empty.sleeps.isEmpty(),
                "empty arrays must not be retried or treated as an unsupported filter");
        empty.requireHealthy();

        Reply ids = new Reply(0x80010001), handles = new Reply(0x80000001);
        Fake snapshots = new Fake().storages(ids).handles(handles);
        int[] storageCopy = snapshots.directory().storageIds();
        int[] handleCopy = snapshots.directory().objectHandles(storageCopy[0], 0, 0);
        storageCopy[0] = 1;
        handleCopy[0] = 2;
        require(ids.values[0] == 0x80010001 && handles.values[0] == 0x80000001,
                "returned arrays must not expose mutable MTP results or change unsigned ID bits");
        require(snapshots.queries.get(0).storage == 0x80010001,
                "high-bit storage IDs must reach MTP unchanged");
    }

    private static void jpegFallbackAndPersistentHandleFailure() throws Exception {
        Fake supported = new Fake().handles(missing(), new Reply(71));
        require(Arrays.equals(supported.directory().objectHandles(CARD, JPEG, 0), new int[]{71}),
                "a null JPEG-filter result must still fall back to all formats");
        require(supported.queries.size() == 2 && supported.queries.get(0).format == JPEG &&
                        supported.queries.get(1).format == 0 && supported.sleeps.isEmpty(),
                "the initial format fallback must preserve its existing query sequence");
        supported.requireHealthy();

        Fake failed = new Fake().handles(missing(), missing(), missing(), missing());
        IOException failure = fails(() -> failed.directory().objectHandles(CARD, JPEG, 0));
        require(failed.queries.size() == 4, "three attempts may use only one extra initial format fallback");
        require(failed.queries.get(0).format == JPEG && failed.queries.subList(1, 4).stream().allMatch(q -> q.format == 0),
                "once rejected, the JPEG filter must not be repeated in later attempts");
        require(failed.queries.stream().allMatch(q -> q.storage == CARD && q.parent == 0),
                "fallback/retries must not change storage or parent semantics");
        require(failed.sleeps.equals(Arrays.asList(100L, 200L)), "handle retries need bounded short backoffs");
        String detail = failure.getCause().getMessage();
        require(detail.contains("getObjectHandles") && detail.contains("storage=0x00010001") &&
                        detail.contains("requestedFormat=0x3801") && detail.contains("format=0x0000") &&
                        detail.contains("parent=0x00000000"),
                "the cause must distinguish handle/storage/filter/root stages without UI technical text");
        failed.requireHealthy();

        Fake raw = new Fake().handles(missing(), new Reply(81));
        require(Arrays.equals(raw.directory().objectHandles(CARD, 0, 0), new int[]{81}),
                "unfiltered RAW-compatible discovery must retain a bounded readiness retry");
        require(raw.queries.size() == 2 && raw.queries.stream().allMatch(q -> q.format == 0),
                "RAW/all-format requests must never become JPEG-only requests");
    }

    private static void ownerAndDetachBoundaries() throws Exception {
        Fake closed = new Fake();
        closed.open = false;
        fails(() -> closed.directory().storageIds());
        require(closed.storageCalls == 0, "a closed owner must never start an SDK query");

        Fake detached = new Fake();
        detached.storages(new Reply(CARD).after(() -> detached.attached = false));
        fails(() -> detached.directory().storageIds());
        require(detached.storageCalls == 1 && detached.sleeps.isEmpty(),
                "a post-query detach must discard even a successful result without a retry");

        Fake replaced = new Fake();
        Object newClient = new Object();
        replaced.handles(missing().after(() -> replaced.activeClient = newClient));
        fails(() -> replaced.directory().objectHandles(CARD, JPEG, 0));
        require(replaced.queries.size() == 1 && replaced.activeClient == newClient && replaced.closes == 0,
                "a changed active client must stop before format fallback and leave the new client alone");

        Fake rebound = new Fake().storages(missing());
        Object newMtp = new Object();
        rebound.afterPause = () -> rebound.mtp = newMtp;
        fails(() -> rebound.directory().storageIds());
        require(rebound.storageCalls == 1 && rebound.mtp == newMtp && rebound.closes == 0,
                "a replaced MTP object during backoff must never be used or closed by an old retry");

        Fake removedWhileWaiting = new Fake().handles(missing(), missing());
        removedWhileWaiting.afterPause = () -> removedWhileWaiting.attached = false;
        fails(() -> removedWhileWaiting.directory().objectHandles(CARD, JPEG, 0));
        require(removedWhileWaiting.queries.size() == 2 && removedWhileWaiting.sleeps.size() == 1,
                "a detach during backoff must prevent every subsequent query");
    }

    private static void slowQueriesDoNotMultiplyTimeouts() throws Exception {
        long slow = UsbPhotoDirectory.RETRY_WINDOW_NANOS * 2;
        Fake storage = new Fake().storages(missing().slow(slow));
        IOException failure = fails(() -> storage.directory().storageIds());
        require(storage.storageCalls == 1 && storage.sleeps.isEmpty(),
                "a slow first storage null must not trigger another blocking call");
        require(failure.getCause().getMessage().contains("getStorageIds attempt=1") &&
                        failure.getCause().getMessage().contains("retry-window-exhausted"),
                "a slow query must report its original stage and actual attempt");
        storage.requireHealthy();

        Fake handles = new Fake().handles(missing().slow(slow));
        IOException handleFailure = fails(() -> handles.directory().objectHandles(CARD, JPEG, 0));
        require(handles.queries.size() == 1 && handles.queries.get(0).format == JPEG && handles.sleeps.isEmpty(),
                "a slow JPEG null must not launch a potentially slow all-format fallback");
        require(handleFailure.getCause().getMessage().contains("format=0x3801") &&
                        handleFailure.getCause().getMessage().contains("attempt=1"),
                "the original slow filtered stage must remain diagnosable");
        handles.requireHealthy();

        Fake waited = new Fake().storages(missing().slow(950000000L));
        fails(() -> waited.directory().storageIds());
        require(waited.storageCalls == 1 && waited.sleeps.equals(Arrays.asList(100L)),
                "an expired retry window after backoff must not start another SDK query");

        Fake slowSuccess = new Fake().storages(new Reply(CARD).slow(slow));
        require(Arrays.equals(slowSuccess.directory().storageIds(), new int[]{CARD}),
                "the retry budget must not discard a successful slow first operation");
        slowSuccess.requireHealthy();
    }

    private static void errorsInterruptionsAndBounds() throws Exception {
        Fake failed = new Fake().storages(new Reply().error(new IOException("injected SDK failure")));
        IOException failure = fails(() -> failed.directory().storageIds());
        require(failure.getCause().getMessage().contains("read-failed") &&
                        failure.getCause().getCause().getMessage().equals("injected SDK failure"),
                "SDK failures must retain their internal cause rather than becoming empty storage");
        require(failed.storageCalls == 1 && failed.sleeps.isEmpty(), "exceptions must not blindly replay SDK operations");
        failed.requireHealthy();

        Fake interrupted = new Fake().storages(missing());
        interrupted.afterPause = () -> Thread.currentThread().interrupt();
        try {
            fails(() -> interrupted.directory().storageIds());
            require(Thread.currentThread().isInterrupted() && interrupted.storageCalls == 1,
                    "interrupted retries must preserve cancellation and stop before another query");
        } finally {
            Thread.interrupted();
        }

        Fake tooManyStorages = new Fake().storages(new Reply(new int[UsbPhotoDirectory.MAX_STORAGES + 1]));
        fails(() -> tooManyStorages.directory().storageIds());
        require(tooManyStorages.storageCalls == 1 && tooManyStorages.sleeps.isEmpty(),
                "storage bounds must remain strict without retries or silent truncation");
        Fake tooManyHandles = new Fake().handles(new Reply(new int[UsbPhotoDirectory.MAX_HANDLES + 1]));
        fails(() -> tooManyHandles.directory().objectHandles(CARD, 0, 0));
        require(tooManyHandles.queries.size() == 1, "oversized handle arrays must fail instead of truncating");
    }

    public static void main(String[] args) throws Exception {
        storageReadinessAndTwoSlots();
        persistentNullDoesNotBecomeEmptyOrClose();
        emptyIsSuccessfulAndSnapshotsAreIndependent();
        jpegFallbackAndPersistentHandleFailure();
        ownerAndDetachBoundaries();
        slowQueriesDoNotMultiplyTimeouts();
        errorsInterruptionsAndBounds();
        System.out.println("PASS " + checks + " USB photo directory checks; bounded same-owner readiness, " +
                "empty/null distinction, dual-card placeholders, format fallback, detach/cancel and slow-query budget");
    }
}
