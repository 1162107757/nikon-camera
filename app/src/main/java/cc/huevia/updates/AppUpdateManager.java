package cc.huevia.updates;

import android.app.DownloadManager;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.database.Cursor;
import android.net.ConnectivityManager;
import android.net.NetworkCapabilities;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import org.json.JSONObject;
import java.io.*;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Public metadata only. The OS owns the download across process death; nothing binds camera networking. */
public final class AppUpdateManager implements AutoCloseable {
    public static final String BASE = "https://nikon-d8girdjsr252fd90e-1252602548.ap-shanghai.app.tcloudbase.com/preset-library";
    public static final String PREFS = "huevia-app-updates";
    public interface Listener { void changed(); void available(); }
    public static final class Release {
        public final String id, name, notes, hash, signer, url, channel, packageName;
        public final long code, bytes, revision;
        public final int minSdk;
        public final boolean mandatory;
        final JSONObject json;
        Release(JSONObject value, Context context) throws IOException {
            json = value;
            id = value.optString("id"); name = value.optString("versionName"); notes = value.optString("notes");
            hash = value.optString("sha256"); signer = value.optString("signerSha256"); url = value.optString("downloadUrl");
            packageName = value.optString("packageName"); channel = value.optString("channel");
            code = value.optLong("versionCode"); bytes = value.optLong("byteLength"); minSdk = value.optInt("minSdk");
            revision = value.optLong("revision", 0);
            try { mandatory = UpdatePolicy.mandatoryField(value.has("mandatory") ? value.get("mandatory") : null); }
            catch (Exception invalid) { throw new IOException("版本更新策略校验失败", invalid); }
            if (!context.getPackageName().equals(packageName) || !UpdatePolicy.hash(hash) || !UpdatePolicy.hash(signer)
                    || !UpdatePolicy.trustedUrl(BASE, url, id) || bytes <= 0 || bytes > UpdatePolicy.MAX_APK_BYTES
                    || code <= 0 || revision < 0 || name.isEmpty() || name.length() > 100 || notes.length() > 12000 || !UpdatePolicy.compatible(Build.VERSION.SDK_INT, minSdk)
                    || !(channel.equals("stable") || channel.equals("beta"))) throw new IOException("版本信息校验失败，请稍后重新检查。");
        }
        /** Policy and release notes can change without invalidating the already downloaded APK. */
        boolean sameArtifact(Release other) {
            return other != null && id.equals(other.id) && code == other.code && bytes == other.bytes && minSdk == other.minSdk
                    && hash.equals(other.hash) && signer.equals(other.signer) && url.equals(other.url)
                    && channel.equals(other.channel) && packageName.equals(other.packageName);
        }
    }
    private static final class Metadata {
        final Release release;
        final String reason;
        Metadata(Release release, String reason) { this.release = release; this.reason = reason; }
    }
    private final Context context;
    private final SharedPreferences prefs;
    private final DownloadManager downloads;
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final Handler main = new Handler(Looper.getMainLooper());
    private Listener listener;
    public Release release;
    public String status = "检查是否有新版本", error = "";
    public boolean checking, downloading, verifying, verified;
    public int progress;
    private boolean closed, foreground, metadataChecked, automaticStarted;
    private long downloadId, epoch;
    private final Runnable poll = this::queryDownload;

    public AppUpdateManager(Context context, Listener listener) {
        this.context = context.getApplicationContext(); this.listener = listener;
        prefs = this.context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        downloads = this.context.getSystemService(DownloadManager.class);
        downloadId = prefs.getLong("downloadId", -1);
        try { String saved = prefs.getString("release", ""); if (!saved.isEmpty()) release = new Release(new JSONObject(saved), context); }
        catch (Exception ignored) { prefs.edit().remove("release").apply(); }
        if (release == null || !UpdatePolicy.newer(installedCode(), release.code) || !release.channel.equals(channel())) { clear(true); release = null; prefs.edit().remove("release").apply(); }
        else if (downloadId > 0 && release != null) { downloading = true; status = "正在恢复下载进度…"; }
    }
    public String channel() {
        String chosen = prefs.getString("channel", null);
        if (chosen != null) return "beta".equals(chosen) ? "beta" : "stable";
        try { return UpdatePolicy.defaultChannel(context.getPackageManager().getPackageInfo(context.getPackageName(), 0).versionName); }
        catch (Exception ignored) { return "stable"; }
    }
    public boolean mandatory() { return release != null && UpdatePolicy.mandatory(installedCode(), release.code, release.mandatory); }
    public boolean metadataChecked() { return metadataChecked; }
    public void channel(String channel) {
        if (closed || mandatory() || downloading || verifying || checking) return;
        clear(true);
        prefs.edit().putString("channel", "beta".equals(channel) ? "beta" : "stable").remove("release").apply();
        release = null; verified = false; error = ""; check(false);
    }
    public long installedCode() {
        try { PackageInfo info = context.getPackageManager().getPackageInfo(context.getPackageName(), 0);
            return Build.VERSION.SDK_INT >= 28 ? info.getLongVersionCode() : info.versionCode;
        } catch (Exception ignored) { return 0; }
    }
    public boolean hasInternet() {
        try {
            ConnectivityManager cm = context.getSystemService(ConnectivityManager.class);
            NetworkCapabilities caps = cm == null ? null : cm.getNetworkCapabilities(cm.getActiveNetwork());
            return caps != null && caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
                    && caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET);
        } catch (RuntimeException ignored) { return false; }
    }
    public boolean metered() {
        ConnectivityManager cm = context.getSystemService(ConnectivityManager.class);
        return cm == null || cm.isActiveNetworkMetered();
    }
    public void autoCheck(boolean idle) {
        if (closed || checking || (!idle && !mandatory()) || !hasInternet()) return;
        if (UpdatePolicy.automaticDue(System.currentTimeMillis(), prefs.getLong("lastAttempt", 0), prefs.getLong("lastCheck", 0), mandatory(), !automaticStarted)) {
            automaticStarted = true; check(true);
        }
    }
    public void resume() { foreground = true; if (downloadId > 0) queryDownload(); }
    public void pause() { foreground = false; main.removeCallbacks(poll); }
    private void changed() { if (!closed && listener != null) listener.changed(); }
    public void check(boolean automatic) {
        if (closed || checking) return;
        if (!hasInternet()) { if (!automatic) { error = "当前网络无法上网。连接可上网的网络后，再检查更新。"; changed(); } return; }
        final String selectedChannel = channel();
        prefs.edit().putLong("lastAttempt", System.currentTimeMillis()).apply();
        checking = true; error = ""; if (!downloading && !verifying) status = "正在检查新版本…"; changed();
        worker.execute(() -> {
            try {
                final Metadata result = readMetadata(selectedChannel);
                main.post(() -> { if (closed || !selectedChannel.equals(channel())) return; checking = false;
                    applyMetadata(result);
                    changed(); if (automatic && result.release != null && listener != null) listener.available(); });
            } catch (Exception failure) { main.post(() -> { if (closed) return; checking = false;
                if (!automatic || mandatory()) error = "无法检查更新，请检查网络后重试。";
                if (!downloading && !verifying) status = "检查未完成"; changed(); }); }
        });
    }
    private Metadata readMetadata(String selectedChannel) throws Exception {
        JSONObject data = metadata(selectedChannel);
        JSONObject row = data.optJSONObject("release");
        String reason = data.optString("reason");
        boolean otherPackage = row != null && UpdatePolicy.otherPackage(context.getPackageName(), row.optString("packageName"));
        Release candidate = otherPackage || data.isNull("release") || "incompatible".equals(reason) || "withdrawn".equals(reason)
                || "no_release".equals(reason) || "client_newer".equals(reason) || "up_to_date".equals(reason)
                ? null : new Release(data.getJSONObject("release"), context);
        if (!selectedChannel.equals(data.optString("channel")) || candidate != null && !selectedChannel.equals(candidate.channel)) throw new IOException("更新通道不匹配");
        if (candidate != null && !UpdatePolicy.newer(installedCode(), candidate.code)) candidate = null;
        return new Metadata(candidate, otherPackage ? "no_release" : reason);
    }
    /** Only successful server responses replace cached policy; a network error cannot invent a withdrawal. */
    private void applyMetadata(Metadata result) {
        boolean same = release != null && release.sameArtifact(result.release);
        if (!same) clear(true);
        release = result.release; metadataChecked = true;
        SharedPreferences.Editor save = prefs.edit().putLong("lastCheck", System.currentTimeMillis());
        if (release == null) save.remove("release"); else save.putString("release", release.json.toString());
        save.apply();
        error = "";
        if (!downloading && !verifying && !verified) status = release != null ? mandatory() ? "需要更新后继续使用" : "有新版本可用"
                : "no_release".equals(result.reason) ? "此通道暂未发布版本"
                : "withdrawn".equals(result.reason) ? "此通道的更新已撤回" : "incompatible".equals(result.reason) ? "新版本暂不支持此 Android 版本"
                : "client_newer".equals(result.reason) ? "当前版本比此通道的发布版本更新" : "已是当前最新版本";
    }
    private JSONObject metadata(String selectedChannel) throws Exception {
        HttpURLConnection connection = (HttpURLConnection) new URL(BASE + "/releases/latest?channel=" + selectedChannel
                + "&packageName=" + context.getPackageName() + "&versionCode=" + installedCode() + "&sdk=" + Build.VERSION.SDK_INT).openConnection();
        connection.setConnectTimeout(15000); connection.setReadTimeout(15000); connection.setInstanceFollowRedirects(false);
        connection.setRequestProperty("Accept", "application/json"); connection.setRequestProperty("Cache-Control", "no-cache");
        java.util.concurrent.ScheduledExecutorService deadline = Executors.newSingleThreadScheduledExecutor();
        java.util.concurrent.ScheduledFuture<?> timeout = deadline.schedule(connection::disconnect, 25, java.util.concurrent.TimeUnit.SECONDS);
        try {
            if (connection.getResponseCode() != 200) throw new IOException("更新服务暂时不可用");
            ByteArrayOutputStream output = new ByteArrayOutputStream(); byte[] block = new byte[4096]; int count;
            try (InputStream input = connection.getInputStream()) { while ((count = input.read(block)) >= 0) { output.write(block, 0, count); if (output.size() > 64 * 1024) throw new IOException("版本信息过长"); } }
            return new JSONObject(output.toString(StandardCharsets.UTF_8.name()));
        } finally { timeout.cancel(false); deadline.shutdownNow(); connection.disconnect(); }
    }
    public void download(boolean mobileAllowed) {
        if (closed || release == null || checking || downloading || verifying) return;
        if (!hasInternet()) { error = "当前网络无法下载更新，请连接可上网的网络。"; changed(); return; }
        clear(true); final Release selected = release;
        try {
            File directory = context.getExternalFilesDir("app-updates");
            if (directory == null || (!directory.isDirectory() && !directory.mkdirs())) throw new IOException();
            File target = new File(directory, selected.hash + ".apk"); if (target.exists() && !target.delete()) throw new IOException();
            DownloadManager.Request request = new DownloadManager.Request(Uri.parse(selected.url));
            request.setTitle("Huevia " + selected.name).setDescription("下载完成后，在 Huevia 中确认安装")
                    .setMimeType("application/vnd.android.package-archive").setAllowedOverMetered(mobileAllowed)
                    .setAllowedOverRoaming(false).setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
                    .setDestinationInExternalFilesDir(context, "app-updates", selected.hash + ".apk");
            downloadId = downloads.enqueue(request); downloading = true; verified = false; progress = 0; error = ""; status = "正在下载更新…";
            prefs.edit().putLong("downloadId", downloadId).putString("release", selected.json.toString()).remove("verified").apply();
            changed(); if (foreground) main.post(poll);
        } catch (Exception ignored) { error = "无法开始下载，请检查可用空间和系统下载服务。"; downloading = false; changed(); }
    }
    public void cancel() { clear(true); status = "下载已取消，可以重新下载"; changed(); }
    private void clear(boolean removeDownload) {
        epoch++;
        if (removeDownload && downloadId > 0 && downloads != null) try { downloads.remove(downloadId); } catch (RuntimeException ignored) {}
        downloadId = -1; downloading = verifying = verified = false;
        prefs.edit().remove("downloadId").remove("verified").apply(); main.removeCallbacks(poll);
    }
    private void queryDownload() {
        if (closed || downloadId <= 0 || release == null || verifying) return;
        try (Cursor row = downloads.query(new DownloadManager.Query().setFilterById(downloadId))) {
            if (row == null || !row.moveToFirst()) { downloading = false; error = "下载记录已移除，请重新下载。"; changed(); return; }
            int code = row.getInt(row.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS));
            long received = row.getLong(row.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR));
            if (received > release.bytes || received > UpdatePolicy.MAX_APK_BYTES) { cancel(); error = "安装包大小异常，下载已停止。"; changed(); return; }
            progress = UpdatePolicy.percent(received, release.bytes);
            if (code == DownloadManager.STATUS_SUCCESSFUL) { downloading = false; if (!verified) verify(false, null); }
            else if (code == DownloadManager.STATUS_FAILED) { downloading = false; status = "下载未完成"; error = "下载失败，请检查网络和可用空间后重试。"; }
            else { downloading = true; status = code == DownloadManager.STATUS_PAUSED ? "下载已暂停，等待可用网络…" : "正在下载更新…"; }
            changed(); if (foreground && downloading) main.postDelayed(poll, 750);
        } catch (RuntimeException ignored) { downloading = false; error = "无法读取系统下载进度，请稍后重试。"; changed(); }
    }
    /** Rechecks publication and all bytes immediately before offering the native installer. */
    public void verifyForInstall(Runnable accepted) { if (!checking && !downloading && !verifying && release != null) verify(true, accepted); }
    private void verify(boolean publication, Runnable accepted) {
        verifying = true; error = ""; status = publication ? "正在核对版本状态…" : "正在校验安装包…"; changed();
        final long token = ++epoch; final Release selected = release; final String selectedChannel = channel();
        worker.execute(() -> {
            try {
                if (publication) {
                    final Metadata fresh = readMetadata(selectedChannel);
                    final boolean unchanged = selected.sameArtifact(fresh.release);
                    main.post(() -> {
                        if (closed || token != epoch) return;
                        applyMetadata(fresh);
                        if (!unchanged) error = fresh.release == null ? "此更新已撤回，请重新检查更新。" : "已有新版本，请下载当前更新。";
                        changed();
                    });
                    if (!unchanged) return;
                }
                File directory = new File(context.getFilesDir(), "app-updates");
                if (!directory.isDirectory() && !directory.mkdirs()) throw new IOException("无法保存安装包，请检查可用空间。");
                File safe = new File(directory, selected.hash + ".apk");
                if (safe.isFile()) try { verifyFile(safe, selected); }
                catch (Exception invalid) { if (!safe.delete()) throw new IOException("无法替换旧安装包，请检查可用空间。"); }
                if (!safe.isFile()) {
                    File source = new File(context.getExternalFilesDir("app-updates"), selected.hash + ".apk");
                    verifyFile(source, selected);
                    File stage = new File(directory, selected.hash + ".tmp");
                    try (InputStream in = new FileInputStream(source); FileOutputStream out = new FileOutputStream(stage)) {
                        byte[] block = new byte[16384]; int count; long total = 0;
                        while ((count = in.read(block)) >= 0) { if ((total += count) > selected.bytes) throw new IOException("安装包大小不匹配"); out.write(block, 0, count); } out.getFD().sync();
                    }
                    verifyFile(stage, selected);
                    if (!stage.renameTo(safe)) throw new IOException("无法保存已校验的安装包。");
                    safe.setReadOnly();
                }
                verifyFile(safe, selected);
                main.post(() -> { if (closed || token != epoch || release == null || !selected.sameArtifact(release)) return; verifying = false; verified = true; progress = 100; status = "下载完成，已通过校验";
                    prefs.edit().putString("verified", selected.hash).apply(); changed(); if (accepted != null) accepted.run(); });
            } catch (Exception failure) {
                final String text = failure instanceof IOException && failure.getMessage() != null ? failure.getMessage() : "安装包校验失败，请重新下载。";
                main.post(() -> { if (closed || token != epoch) return; verifying = false; verified = false; error = text; status = "暂时无法安装"; prefs.edit().remove("verified").apply(); changed(); });
            }
        });
    }
    private void verifyFile(File file, Release expected) throws Exception {
        if (!file.isFile() || file.length() != expected.bytes) throw new IOException("安装包大小不匹配，请重新下载。");
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (InputStream input = new FileInputStream(file)) { byte[] block = new byte[16384]; int count; while ((count = input.read(block)) >= 0) digest.update(block, 0, count); }
        if (!hex(digest.digest()).equals(expected.hash)) throw new IOException("安装包校验失败，请重新下载。");
        int flags = Build.VERSION.SDK_INT >= 28 ? PackageManager.GET_SIGNING_CERTIFICATES : PackageManager.GET_SIGNATURES;
        PackageManager pm = context.getPackageManager(); PackageInfo apk = pm.getPackageArchiveInfo(file.getPath(), flags), installed = pm.getPackageInfo(context.getPackageName(), flags);
        if (apk == null || !context.getPackageName().equals(apk.packageName)
                || (Build.VERSION.SDK_INT >= 28 ? apk.getLongVersionCode() : apk.versionCode) != expected.code
                || !UpdatePolicy.newer(installedCode(), expected.code) || apk.applicationInfo == null
                || apk.applicationInfo.minSdkVersion != expected.minSdk || !UpdatePolicy.compatible(Build.VERSION.SDK_INT, apk.applicationInfo.minSdkVersion)) throw new IOException("安装包与此设备不兼容，已阻止安装。");
        Signature[] signed = Build.VERSION.SDK_INT >= 28 ? apk.signingInfo == null ? null : apk.signingInfo.getApkContentsSigners() : apk.signatures;
        Signature[] existing = Build.VERSION.SDK_INT >= 28 ? installed.signingInfo == null ? null : installed.signingInfo.getApkContentsSigners() : installed.signatures;
        if (signed == null || existing == null || signed.length != 1 || existing.length != 1
                || !signed[0].equals(existing[0]) || !hex(MessageDigest.getInstance("SHA-256").digest(signed[0].toByteArray())).equals(expected.signer)) throw new IOException("安装包签名不匹配，已阻止安装。");
    }
    private static String hex(byte[] bytes) { StringBuilder result = new StringBuilder(); for (byte value : bytes) result.append(String.format(Locale.ROOT, "%02x", value & 255)); return result.toString(); }
    public Uri installerUri() { return release == null || !verified ? null : Uri.parse("content://" + context.getPackageName() + ".updates/apk/" + release.hash); }
    @Override public void close() { closed = true; listener = null; main.removeCallbacksAndMessages(null); worker.shutdownNow(); }
}
