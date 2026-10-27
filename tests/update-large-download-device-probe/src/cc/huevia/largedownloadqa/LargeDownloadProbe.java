package cc.huevia.largedownloadqa;

import android.app.Activity;
import android.app.DownloadManager;
import android.app.Instrumentation;
import android.content.Context;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.SystemClock;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.net.URL;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

/** A real system DownloadManager test. No installer, account, or editor activity is started. */
public final class LargeDownloadProbe extends Instrumentation {
    private static final String PACKAGE = "cc.huevia";
    private static final String STORAGE_HOST = "nikon-d8girdjsr252fd90e.api.tcloudbasegateway.com";
    private Bundle args;
    private Context context;
    private DownloadManager downloads;
    private long downloadId = -1, expectedBytes;
    private File target, downloadDirectory, evidence;
    private String stage = "arguments", expectedSha;
    private Throwable failure;
    private boolean downloadRemoved, targetRemoved, directoryRemoved;
    private final JSONArray checks = new JSONArray(), states = new JSONArray(), cleanupErrors = new JSONArray();
    private final JSONObject transport = new JSONObject();

    @Override public void onCreate(Bundle arguments) { super.onCreate(arguments); args = arguments; start(); }
    @Override public void onStart() {
        try {
            context = getTargetContext();
            check("target-package", PACKAGE.equals(context.getPackageName()));
            check("emulator-only", Build.HARDWARE.contains("ranchu") || Build.HARDWARE.contains("goldfish"));
            String run = args.getString("runId"), candidate = args.getString("candidateSha256");
            check("safe-run-id", run != null && run.matches("[a-zA-Z0-9.-]+"));
            expectedSha = args.getString("expectedSha256");
            check("expected-sha", expectedSha != null && expectedSha.matches("[a-f0-9]{64}"));
            expectedBytes = Long.parseLong(args.getString("expectedBytes"));
            check("large-apk-within-new-limit", expectedBytes > 4L * 1024 * 1024 && expectedBytes <= 32L * 1024 * 1024);
            check("installed-candidate-sha", sha(new File(context.getApplicationInfo().sourceDir)).equals(candidate));
            PackageInfo installed = context.getPackageManager().getPackageInfo(PACKAGE, PackageManager.GET_SIGNING_CERTIFICATES);
            check("installed-candidate-code", installed.getLongVersionCode() == Long.parseLong(args.getString("candidateVersionCode")));
            check("installed-candidate-name", installed.versionName.equals(args.getString("candidateVersionName")));
            File root = context.getExternalFilesDir(null);
            check("external-files-available", root != null);
            File evidenceParent = new File(root, "update-large-download-evidence");
            check("evidence-parent", evidenceParent.isDirectory() || evidenceParent.mkdir());
            evidence = new File(evidenceParent, run);
            check("fresh-evidence-directory", evidence.mkdir());
            File downloadParent = new File(root, "update-large-download-files");
            check("download-parent", downloadParent.isDirectory() || downloadParent.mkdir());
            downloadDirectory = new File(downloadParent, run);
            check("fresh-download-directory", downloadDirectory.mkdir());
            target = new File(downloadDirectory, "payload.apk");
            check("fresh-download-target", !target.exists());

            String canonical = args.getString("canonicalUrl");
            URI publicUri = new URI(canonical);
            Set<String> publicHosts = new HashSet<>(Arrays.asList("huevia.cc", "nikon-d8girdjsr252fd90e-1252602548.ap-shanghai.app.tcloudbase.com"));
            check("canonical-public-url", "https".equals(publicUri.getScheme()) && publicHosts.contains(publicUri.getHost())
                    && publicUri.getPort() == -1 && publicUri.getRawUserInfo() == null && publicUri.getRawQuery() == null && publicUri.getRawFragment() == null
                    && publicUri.getRawPath().matches("/preset-library/releases/[a-f0-9-]{36}/file"));
            stage = "public-redirect-preflight";
            preflight(canonical);

            stage = "download-manager";
            downloads = (DownloadManager) context.getSystemService(Context.DOWNLOAD_SERVICE);
            check("system-download-manager-available", downloads != null);
            DownloadManager.Request request = new DownloadManager.Request(Uri.parse(canonical));
            request.setTitle("Huevia download verification").setDescription("Temporary QA download")
                    .setMimeType("application/vnd.android.package-archive")
                    .setAllowedOverMetered(true).setAllowedOverRoaming(false)
                    .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
                    .setDestinationUri(Uri.fromFile(target));
            downloadId = downloads.enqueue(request);
            check("native-download-id", downloadId > 0);
            boolean complete = false;
            long end = SystemClock.elapsedRealtime() + 120_000;
            String previous = "";
            while (SystemClock.elapsedRealtime() < end) {
                try (Cursor row = downloads.query(new DownloadManager.Query().setFilterById(downloadId))) {
                    checkOnce("download-record-present", row != null && row.moveToFirst());
                    int status = row.getInt(row.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS));
                    int reason = row.getInt(row.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON));
                    long received = row.getLong(row.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR));
                    long total = row.getLong(row.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES));
                    checkOnce("reported-byte-count-bounded", received >= 0 && received <= expectedBytes);
                    if (total > 0) checkOnce("reported-total-exact", total == expectedBytes);
                    String snapshot = status + ":" + reason + ":" + received + ":" + total;
                    if (!snapshot.equals(previous)) {
                        states.put(new JSONObject().put("status", status).put("reason", reason).put("received", received).put("total", total));
                        previous = snapshot;
                    }
                    if (status == DownloadManager.STATUS_SUCCESSFUL) { complete = true; break; }
                    if (status == DownloadManager.STATUS_FAILED) throw new AssertionError("download-manager-failed-reason-" + reason);
                }
                SystemClock.sleep(250);
            }
            check("native-download-success", complete);
            stage = "downloaded-apk-verification";
            check("downloaded-file-present", target.isFile());
            check("downloaded-byte-length", target.length() == expectedBytes);
            check("downloaded-sha256", sha(target).equals(expectedSha));
            PackageInfo archive = context.getPackageManager().getPackageArchiveInfo(target.getAbsolutePath(), PackageManager.GET_SIGNING_CERTIFICATES);
            check("native-package-parser-accepts-apk", archive != null);
            check("downloaded-package-name", PACKAGE.equals(archive.packageName));
            check("downloaded-version-code", archive.getLongVersionCode() == Long.parseLong(args.getString("expectedVersionCode")));
            check("downloaded-version-name", archive.versionName.equals(args.getString("expectedVersionName")));
            check("downloaded-signing-info", archive.signingInfo != null && installed.signingInfo != null);
            check("single-installed-signer", installed.signingInfo.getApkContentsSigners().length == 1);
            check("single-downloaded-signer", archive.signingInfo.getApkContentsSigners().length == 1);
            Signature expectedSigner = installed.signingInfo.getApkContentsSigners()[0];
            check("downloaded-same-installed-signature", expectedSigner.equals(archive.signingInfo.getApkContentsSigners()[0]));
            stage = "complete";
        } catch (Throwable error) { failure = error; }
        finally {
            cleanup();
            report();
            Bundle result = new Bundle();
            result.putString("summary", failure == null ? "PASS " + checks.length() + " checks; real DownloadManager large APK" : "FAIL " + stage + " " + failure.getClass().getSimpleName());
            finish(failure == null ? Activity.RESULT_OK : Activity.RESULT_CANCELED, result);
        }
    }

    private void preflight(String value) throws Exception {
        HttpURLConnection connection = (HttpURLConnection) new URL(value).openConnection();
        connection.setInstanceFollowRedirects(false);
        connection.setConnectTimeout(20_000); connection.setReadTimeout(20_000);
        try {
            int status = connection.getResponseCode();
            transport.put("publicStatus", status);
            check("public-zero-body-307", status == 307 && connection.getContentLengthLong() == 0);
            URI location = new URI(connection.getHeaderField("Location"));
            check("redirect-https-private-storage-origin", "https".equals(location.getScheme()) && STORAGE_HOST.equals(location.getHost())
                    && location.getPort() == -1 && location.getUserInfo() == null && location.getFragment() == null);
            check("redirect-exact-sha-object", location.getRawPath().equals("/v1/storages/object/sign/nikon-presets/app-releases/" + expectedSha + ".bin"));
            // Never record the query or the provider-issued signed URL.
            transport.put("redirectHost", location.getHost()).put("redirectPath", location.getRawPath()).put("signedUrlRecorded", false);
        } finally { connection.disconnect(); }
    }

    private void check(String name, boolean pass) throws Exception {
        checks.put(new JSONObject().put("name", name).put("pass", pass));
        if (!pass) throw new AssertionError(name);
    }
    private final Set<String> once = new HashSet<>();
    private void checkOnce(String name, boolean pass) throws Exception {
        if (!pass || once.add(name)) check(name, pass);
    }
    private static String sha(File file) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (FileInputStream input = new FileInputStream(file)) {
            byte[] block = new byte[128 * 1024]; int count;
            while ((count = input.read(block)) >= 0) digest.update(block, 0, count);
        }
        StringBuilder hex = new StringBuilder();
        for (byte value : digest.digest()) hex.append(String.format(java.util.Locale.ROOT, "%02x", value & 255));
        return hex.toString();
    }
    private void cleanupStep(String label, Checked action) {
        try { action.run(); }
        catch (Throwable error) {
            cleanupErrors.put(label + ":" + error.getClass().getSimpleName());
            if (failure == null) failure = new AssertionError("cleanup-" + label);
        }
    }
    private interface Checked { void run() throws Exception; }
    private void cleanup() {
        if (downloadId > 0 && downloads != null) cleanupStep("download-record", () -> {
            int removed = downloads.remove(downloadId);
            try (Cursor cursor = downloads.query(new DownloadManager.Query().setFilterById(downloadId))) {
                downloadRemoved = cursor == null || !cursor.moveToFirst();
            }
            if (!downloadRemoved || removed != 1) throw new AssertionError("owned-download-not-removed");
        });
        if (target != null) cleanupStep("owned-target", () -> {
            targetRemoved = !target.exists() || target.delete();
            if (!targetRemoved) throw new AssertionError("owned-file-not-removed");
        });
        if (downloadDirectory != null) cleanupStep("owned-directory", () -> {
            directoryRemoved = !downloadDirectory.exists() || downloadDirectory.delete();
            if (!directoryRemoved) throw new AssertionError("owned-directory-not-empty");
        });
    }
    private void report() {
        if (evidence == null) return;
        try {
            JSONObject report = new JSONObject().put("pass", failure == null).put("stage", stage)
                    .put("candidateSha256", args.getString("candidateSha256")).put("candidateVersionCode", args.getString("candidateVersionCode"))
                    .put("candidateVersionName", args.getString("candidateVersionName"))
                    .put("downloadSha256", expectedSha).put("downloadBytes", expectedBytes)
                    .put("downloadVersionCode", args.getString("expectedVersionCode")).put("downloadVersionName", args.getString("expectedVersionName"))
                    .put("transport", transport).put("checks", checks).put("nativeDownloadStates", states)
                    .put("downloadRemoved", downloadRemoved).put("targetRemoved", targetRemoved).put("directoryRemoved", directoryRemoved)
                    .put("cleanupErrors", cleanupErrors).put("failure", failure == null ? JSONObject.NULL : stage + ":" + failure.getClass().getSimpleName())
                    .put("installerStarted", false).put("accountChanged", false)
                    .put("scope", "Real Android DownloadManager canonical HTTPS307 to private storage; downloaded length/SHA/native package parser/version/current signer; no installation or account/editor action. Emulator only.");
            try (FileOutputStream output = new FileOutputStream(new File(evidence, "report.json"))) {
                output.write(report.toString(2).getBytes(java.nio.charset.StandardCharsets.UTF_8));
            }
        } catch (Throwable error) { if (failure == null) failure = error; }
    }
}
