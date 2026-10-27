package cc.huevia.updates;

import java.net.URI;
import java.util.Locale;

/** Checks shared by network metadata, persistent state and the installer boundary. */
public final class UpdatePolicy {
    private UpdatePolicy() {}
    public static final long MAX_APK_BYTES = 32L * 1024 * 1024;
    public static final long AUTOMATIC_INTERVAL_MS = 30L * 60 * 1000;
    public static final long RETRY_INTERVAL_MS = 60L * 1000;
    public static String defaultChannel(String installedVersionName) {
        return installedVersionName != null && installedVersionName.toLowerCase(Locale.ROOT).contains("-beta") ? "beta" : "stable";
    }
    public static boolean hash(String value) { return value != null && value.matches("[0-9a-f]{64}"); }
    public static boolean newer(long installed, long candidate) { return installed > 0 && candidate > installed; }
    public static boolean mandatory(long installed, long candidate, boolean required) {
        return required && newer(installed, candidate);
    }
    /** Missing fields from older metadata are optional; strings must never become a forced update. */
    public static boolean mandatoryField(Object value) {
        if (value == null) return false;
        if (!(value instanceof Boolean)) throw new IllegalArgumentException("mandatory must be boolean");
        return (Boolean) value;
    }
    /** A fresh process checks once; resume checks are throttled, including failed requests. */
    public static boolean automaticDue(long now, long lastAttempt, long lastSuccess, boolean required, boolean first) {
        if (now < 0) return false;
        long sinceAttempt = now >= lastAttempt ? now - lastAttempt : Long.MAX_VALUE;
        if (lastAttempt > 0 && sinceAttempt < RETRY_INTERVAL_MS) return false;
        if (first || required || lastAttempt > lastSuccess) return true;
        return lastSuccess <= 0 || now < lastSuccess || now - lastSuccess >= AUTOMATIC_INTERVAL_MS;
    }
    /** Other install IDs cannot update this app, including responses from an older server. */
    public static boolean otherPackage(String installed, String candidate) {
        return installed != null && candidate != null && !installed.isEmpty() && !candidate.isEmpty()
                && !installed.equals(candidate);
    }
    public static boolean compatible(int sdk, int minSdk) { return minSdk >= 26 && sdk >= minSdk; }
    public static boolean trustedUrl(String base, String value, String id) {
        try {
            URI origin = new URI(base), target = new URI(value);
            return "https".equals(target.getScheme()) && origin.getHost().equals(target.getHost())
                    && target.getPort() == origin.getPort() && target.getUserInfo() == null
                    && target.getRawQuery() == null && target.getRawFragment() == null
                    && id.matches("[0-9a-fA-F-]{36}")
                    && target.getRawPath().equals(origin.getRawPath() + "/releases/" + id + "/file");
        } catch (Exception ignored) { return false; }
    }
    public static int percent(long received, long total) {
        if (total <= 0 || received <= 0) return 0;
        return (int) Math.min(100L, Math.round(Math.min(received, total) * 100d / total));
    }
}
