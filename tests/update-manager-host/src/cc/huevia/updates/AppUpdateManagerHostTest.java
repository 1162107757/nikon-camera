package cc.huevia.updates;

import android.app.DownloadManager;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.*;
import android.net.ConnectivityManager;
import android.os.Handler;
import org.json.JSONObject;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.BooleanSupplier;

/** Executes production manager state transitions with offline Android/HTTP object fixtures. */
public final class AppUpdateManagerHostTest {
    private static final String ID = "19bd1434-e597-4f27-808d-9b86eb8d983d";
    private static final byte[] APK = "offline apk-byte fixture".getBytes(StandardCharsets.UTF_8);
    private static final byte[] CERT = "offline signer fixture".getBytes(StandardCharsets.UTF_8);
    private static JSONObject reply;
    private static boolean networkFailure;
    private static volatile CountDownLatch httpEntered, httpContinue;
    private static final AtomicInteger requests = new AtomicInteger();
    private static int checks;

    public static void main(String[] args) throws Exception {
        URL.setURLStreamHandlerFactory(protocol -> "https".equals(protocol) ? new URLStreamHandler() {
            @Override protected URLConnection openConnection(URL url) {
                if (!url.toString().startsWith(AppUpdateManager.BASE + "/releases/latest?")) throw new AssertionError("unexpected outbound URL: " + url);
                return new HttpURLConnection(url) {
                    public void connect() {}
                    public void disconnect() {}
                    public boolean usingProxy() { return false; }
                    public int getResponseCode() throws IOException {
                        requests.incrementAndGet();
                        CountDownLatch entered = httpEntered, proceed = httpContinue;
                        if (entered != null) entered.countDown();
                        if (proceed != null) try { if (!proceed.await(5, TimeUnit.SECONDS)) throw new IOException("fixture gate timed out"); }
                        catch (InterruptedException failure) { Thread.currentThread().interrupt(); throw new IOException(failure); }
                        if (networkFailure) throw new IOException("offline fixture"); return 200;
                    }
                    public InputStream getInputStream() { return new ByteArrayInputStream(reply.toString().getBytes(StandardCharsets.UTF_8)); }
                };
            }
        } : null);
        File root = Files.createTempDirectory("huevia-update-manager-host-").toFile();
        try {
            defaultChannels(new FakeContext(new File(root, "channels")));
            policyAndDownloads(new FakeContext(new File(root, "policy")));
            capacityAndOversizedDownload(new FakeContext(new File(root, "capacity")));
            restoreAndRetry(new FakeContext(new File(root, "restore")));
            installBoundary(new FakeContext(new File(root, "install")));
            System.out.println("App update manager: " + checks + " checks passed (offline host fixtures; no device/real HTTP/APK install).");
        } finally { delete(root); }
    }

    private static void defaultChannels(FakeContext context) {
        context.packages.versionName = "0.21.0-beta";
        try (AppUpdateManager manager = manager(context, new AtomicInteger())) {
            require(manager.channel().equals("beta"), "beta installation without preference follows beta releases");
            require(context.preferences.getString("channel", null) == null, "inferred channel does not overwrite explicit user preference storage");
        }
        context.preferences.edit().putString("channel", "stable").apply();
        try (AppUpdateManager manager = manager(context, new AtomicInteger())) {
            require(manager.channel().equals("stable"), "beta installation preserves explicit stable preference");
        }
        context.preferences.edit().remove("channel").apply();
        context.packages.versionName = "0.21.0";
        try (AppUpdateManager manager = manager(context, new AtomicInteger())) {
            require(manager.channel().equals("stable"), "stable installation without preference follows stable releases");
        }
        context.preferences.edit().putString("channel", "beta").apply();
        try (AppUpdateManager manager = manager(context, new AtomicInteger())) {
            require(manager.channel().equals("beta"), "stable installation preserves explicit beta preference");
        }
    }

    private static void policyAndDownloads(FakeContext context) throws Exception {
        AtomicInteger available = new AtomicInteger();
        try (AppUpdateManager manager = manager(context, available)) {
            require(!manager.metadataChecked() && !manager.mandatory(), "fresh manager starts ungated");
            JSONObject legacy = release(null, 99, sha(APK));
            fetch(manager, legacy, "available", true);
            require(manager.release != null && !manager.mandatory(), "legacy metadata remains optional");
            require(manager.metadataChecked() && available.get() == 1, "successful automatic metadata notifies UI");
            require(!context.preferences.getString("release", "").isEmpty(), "available metadata cached before downloading");
            fetch(manager, release(true, 99, sha(APK)), "available", false);
            require(manager.mandatory(), "mandatory server flag gates newer version");
            int before = requests.get(); manager.channel("beta");
            require(manager.channel().equals("stable") && requests.get() == before, "mandatory update prevents channel bypass");
            manager.download(false);
            require(manager.downloading && context.downloads.id == 1, "required download starts through existing manager");
            int removed = context.downloads.removals;
            fetch(manager, release(false, 99, sha(APK)), "available", false);
            require(!manager.mandatory() && manager.downloading && context.downloads.removals == removed, "policy withdrawal preserves same-artifact download");
            fetch(manager, release(true, 99, sha(APK)), "available", false);
            require(manager.mandatory() && manager.downloading, "mandatory can refresh during a download");
            networkFailure = true; manager.check(false); await(() -> !manager.checking); networkFailure = false;
            require(manager.mandatory() && manager.downloading && !manager.error.isEmpty(), "network failure cannot invent a mandatory withdrawal");
            fetch(manager, null, "withdrawn", false);
            require(!manager.mandatory() && manager.release == null && !manager.downloading, "server withdrawal releases gate and download");
            require(context.downloads.removals == removed + 1, "withdrawn download removed exactly once");
            require(context.preferences.getString("release", "").isEmpty(), "withdrawn metadata removed from persistent cache");
            fetch(manager, release(true, 97, sha(APK)), "up_to_date", false);
            require(manager.release == null && !manager.mandatory(), "already-installed required version never blocks");
        }
    }

    private static void capacityAndOversizedDownload(FakeContext context) throws Exception {
        // Metadata and DownloadManager counters are synthetic. No 9.5/32 MiB APK is parsed or installed here.
        long shippedBytes = 9_478_052L, cap = UpdatePolicy.MAX_APK_BYTES;
        try (AppUpdateManager manager = manager(context, new AtomicInteger())) {
            fetch(manager, release(false, 110, sha(APK)).put("byteLength", shippedBytes), "available", false);
            require(manager.release != null && manager.release.bytes == shippedBytes,
                    "real release byte length above the former 4 MiB cap is accepted as metadata");
            fetch(manager, release(true, 110, sha(APK)).put("byteLength", cap), "available", false);
            require(manager.release != null && manager.release.bytes == cap && manager.mandatory(),
                    "exact 32 MiB boundary is accepted without dropping mandatory policy");
            boolean refused = false;
            try { new AppUpdateManager.Release(release(true, 110, sha(APK)).put("byteLength", cap + 1), context); }
            catch (IOException expected) { refused = true; }
            require(refused, "release metadata rejects cap plus one byte");
            fetch(manager, release(true, 111, sha(APK)).put("byteLength", cap + 1), "available", false);
            require(manager.release.code == 110 && manager.release.bytes == cap && !manager.error.isEmpty(),
                    "oversized network metadata cannot replace the last valid candidate");

            manager.pause();
            int removed = context.downloads.removals;
            manager.download(false);
            require(manager.downloading && context.preferences.getLong("downloadId", -1) > 0,
                    "accepted capacity boundary starts a tracked synthetic system download");
            context.downloads.status = DownloadManager.STATUS_PAUSED;
            context.downloads.received = cap;
            manager.resume();
            require(manager.downloading && !manager.verified && manager.progress == 100 && context.downloads.removals == removed,
                    "reported received bytes exactly at cap do not falsely cancel or verify a paused download");
            context.downloads.received = cap + 1;
            manager.resume();
            require(!manager.downloading && !manager.verifying && !manager.verified && manager.installerUri() == null,
                    "reported received bytes above cap stop download and expose no installer URI");
            require(context.downloads.removals == removed + 1,
                    "oversized reported download is removed from DownloadManager exactly once");
            require(context.preferences.getLong("downloadId", -1) == -1 && context.preferences.getString("verified", null) == null,
                    "oversized reported download clears persisted download and verification state");
            require(manager.release != null && manager.mandatory() && !manager.error.isEmpty(),
                    "capacity rejection retains a retryable mandatory candidate and reports failure");
        }
    }

    private static void restoreAndRetry(FakeContext context) throws Exception {
        try (AppUpdateManager first = manager(context, new AtomicInteger())) {
            fetch(first, release(true, 99, sha(APK)), "available", false);
        }
        try (AppUpdateManager restored = manager(context, new AtomicInteger())) {
            require(restored.mandatory() && !restored.metadataChecked(), "cached release restores requirement but is not reported freshly checked");
            context.connectivity.online = false; restored.check(false);
            require(restored.mandatory() && !restored.checking && !restored.error.isEmpty(), "offline restart keeps requirement and offers retry");
            context.connectivity.online = true;
            fetch(restored, release(true, 99, sha(APK)).put("mandatory", "true"), "available", false);
            require(restored.mandatory() && !restored.error.isEmpty(), "malformed mandatory field cannot overwrite trusted cached policy");
            fetch(restored, release(false, 99, sha(APK)), "available", false);
            require(!restored.mandatory() && restored.error.isEmpty(), "successful retry releases stale cached requirement");
            fetch(restored, release(true, 99, sha(APK)), "available", false);
        }
        context.packages.installed = 99;
        try (AppUpdateManager updated = manager(context, new AtomicInteger())) {
            require(updated.release == null && !updated.mandatory(), "newly installed version clears cached requirement");
        }
    }

    private static void installBoundary(FakeContext context) throws Exception {
        AtomicInteger accepted = new AtomicInteger();
        try (AppUpdateManager manager = manager(context, new AtomicInteger())) {
            fetch(manager, release(true, 99, sha(APK)), "available", false);
            ready(manager, context);
            require(manager.verified && manager.installerUri() != null && manager.mandatory(), "verified bytes do not pretend installation has completed");
            serve(release(false, 99, sha(APK)), "available");
            manager.verifyForInstall(accepted::incrementAndGet); await(() -> !manager.verifying);
            require(accepted.get() == 1 && manager.verified && !manager.mandatory(), "install recheck accepts same APK and applies changed optional policy");
            serve(release(false, 99, sha(APK)), "available");
            httpEntered = new CountDownLatch(1); httpContinue = new CountDownLatch(1);
            manager.verifyForInstall(accepted::incrementAndGet);
            require(httpEntered.await(2, TimeUnit.SECONDS), "installation metadata request reached offline gate");
            manager.check(false);
            require(manager.checking && manager.verifying, "policy refresh queues during active installation verification");
            httpContinue.countDown(); httpEntered = null; httpContinue = null;
            await(() -> !manager.checking && !manager.verifying);
            require(accepted.get() == 2 && manager.verified, "queued same-artifact policy refresh does not corrupt valid verification");
            fetch(manager, release(true, 99, sha(APK)), "available", false);
            require(manager.verified && manager.mandatory(), "same APK metadata check preserves verification");
            serve(release(true, 99, "a".repeat(64)), "available");
            manager.verifyForInstall(accepted::incrementAndGet); await(() -> !manager.verifying);
            require(accepted.get() == 2 && !manager.verified && manager.installerUri() == null, "same-id changed hash cannot reuse old verification or installer URI");
            require(manager.release.hash.equals("a".repeat(64)) && manager.mandatory(), "replacement metadata becomes retryable current candidate");
            fetch(manager, release(true, 99, sha(APK)), "available", false);
            ready(manager, context);
            serve(null, "withdrawn");
            manager.verifyForInstall(accepted::incrementAndGet); await(() -> !manager.verifying);
            require(accepted.get() == 2 && manager.release == null && !manager.mandatory(), "withdrawn install releases gate and never invokes installer callback");
            fetch(manager, release(true, 99, sha(APK)), "available", false);
            context.packages.signer = new Signature("wrong signer".getBytes(StandardCharsets.UTF_8));
            ready(manager, context);
            require(!manager.verified && manager.mandatory() && manager.installerUri() == null && !manager.error.isEmpty(), "APK signature failure retains mandatory retry without claiming update");
            context.packages.signer = new Signature(CERT);
            ready(manager, context);
            require(manager.verified && manager.mandatory(), "failed validation can be retried with valid bytes and signer");
            manager.pause(); manager.resume();
            require(manager.mandatory(), "return from installer without upgrading keeps requirement");
            context.packages.installed = 99;
            require(!manager.mandatory(), "actual package upgrade releases requirement");
        }
    }

    private static AppUpdateManager manager(FakeContext context, AtomicInteger available) {
        return new AppUpdateManager(context, new AppUpdateManager.Listener() { public void changed() {} public void available() { available.incrementAndGet(); } });
    }
    private static void ready(AppUpdateManager manager, FakeContext context) throws Exception {
        manager.pause(); context.downloads.status = DownloadManager.STATUS_SUCCESSFUL; context.downloads.received = APK.length;
        manager.download(false); manager.resume(); await(() -> !manager.verifying && !manager.downloading);
    }
    private static JSONObject release(Boolean required, long code, String hash) throws Exception {
        JSONObject value = new JSONObject().put("id", ID).put("versionName", "0.21.0-beta").put("notes", "offline fixture")
                .put("sha256", hash).put("signerSha256", sha(CERT)).put("downloadUrl", AppUpdateManager.BASE + "/releases/" + ID + "/file")
                .put("packageName", "cc.huevia").put("channel", "stable").put("versionCode", code).put("byteLength", APK.length).put("minSdk", 26).put("revision", 1);
        if (required != null) value.put("mandatory", required);
        return value;
    }
    private static void fetch(AppUpdateManager manager, JSONObject release, String reason, boolean automatic) throws Exception {
        serve(release, reason); manager.check(automatic); await(() -> !manager.checking);
    }
    private static void serve(JSONObject release, String reason) { reply = new JSONObject().put("channel", "stable").put("reason", reason).put("release", release); }
    private static void await(BooleanSupplier ready) throws Exception {
        long end = System.nanoTime() + 5_000_000_000L;
        do { Handler.drain(); if (ready.getAsBoolean()) { Handler.drain(); return; } Thread.sleep(2); } while (System.nanoTime() < end);
        throw new AssertionError("asynchronous manager operation timed out");
    }
    private static String sha(byte[] bytes) throws Exception { return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes)); }
    private static void require(boolean value, String name) { if (!value) throw new AssertionError(name); checks++; }
    private static void delete(File file) throws IOException {
        File[] children = file.listFiles();
        if (children != null) for (File child : children) delete(child);
        if (file.isFile()) file.setWritable(true);
        Files.deleteIfExists(file.toPath());
    }

    private static final class Preferences implements SharedPreferences {
        final Map<String, Object> values = new HashMap<>();
        public String getString(String key, String fallback) { return values.get(key) instanceof String ? (String) values.get(key) : fallback; }
        public long getLong(String key, long fallback) { return values.get(key) instanceof Long ? (Long) values.get(key) : fallback; }
        public Editor edit() { return new Editor() {
            final Map<String, Object> pending = new HashMap<>();
            public Editor putString(String key, String value) { pending.put(key, value); return this; }
            public Editor putLong(String key, long value) { pending.put(key, value); return this; }
            public Editor remove(String key) { pending.put(key, null); return this; }
            public void apply() { pending.forEach((key, value) -> { if (value == null) values.remove(key); else values.put(key, value); }); }
        }; }
    }
    private static final class Packages extends PackageManager {
        int installed = 97;
        String versionName = "0.20.2";
        Signature signer = new Signature(CERT);
        public PackageInfo getPackageInfo(String name, int flags) { return info(installed, new Signature(CERT)); }
        public PackageInfo getPackageArchiveInfo(String path, int flags) { return info(99, signer); }
        private PackageInfo info(int code, Signature signature) {
            PackageInfo info = new PackageInfo(); info.packageName = "cc.huevia"; info.versionCode = code; info.versionName = versionName;
            info.applicationInfo = new ApplicationInfo(); info.applicationInfo.minSdkVersion = 26;
            info.signingInfo = new SigningInfo(signature); info.signatures = new Signature[]{signature}; return info;
        }
    }
    private static final class FakeContext extends Context {
        final File root;
        final Preferences preferences = new Preferences();
        final DownloadManager downloads = new DownloadManager();
        final ConnectivityManager connectivity = new ConnectivityManager();
        final Packages packages = new Packages();
        FakeContext(File root) { this.root = root; root.mkdirs(); downloads.payload = APK; }
        public SharedPreferences getSharedPreferences(String name, int mode) { return preferences; }
        public <T> T getSystemService(Class<T> type) { return type.cast(type == DownloadManager.class ? downloads : connectivity); }
        public String getPackageName() { return "cc.huevia"; }
        public PackageManager getPackageManager() { return packages; }
        public File getFilesDir() { File value = new File(root, "internal"); value.mkdirs(); return value; }
        public File getExternalFilesDir(String type) { File value = new File(root, "external/" + type); value.mkdirs(); return value; }
    }
}
