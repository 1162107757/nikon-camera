package cc.huevia.album;

import java.util.Locale;

/** Compact source labels. A RAW-derived workspace remains identifiable after reopening. */
public final class PhotoSourceFormat {
    public static final String[] RAW_MIMES = {"image/x-nikon-nef", "image/x-nikon-nrw", "image/x-adobe-dng", "image/dng",
            "image/x-canon-cr2", "image/x-canon-cr3", "image/x-sony-arw", "image/x-fuji-raf", "image/x-panasonic-rw2",
            "image/x-olympus-orf", "image/x-pentax-pef", "image/x-samsung-srw", "image/x-raw"};
    private static final String EXTENSIONS = "nef nrw dng cr2 cr3 arw raf rw2 orf pef srw raw";
    private PhotoSourceFormat() { }
    public static String rawExtension(String name) {
        String safe = name == null ? "" : name.toLowerCase(Locale.ROOT);
        int dot = safe.lastIndexOf('.');
        String extension = dot < 0 ? "" : safe.substring(dot + 1);
        return (" " + EXTENSIONS + " ").contains(" " + extension + " ") && !extension.isEmpty() ? extension : "";
    }
    public static boolean raw(String name, String mime) {
        if (!rawExtension(name).isEmpty()) return true;
        for (String supported : RAW_MIMES) if (supported.equalsIgnoreCase(mime)) return true;
        return false;
    }
    public static String label(String name, String mime) {
        String raw = rawExtension(name);
        if (!raw.isEmpty()) return raw.toUpperCase(Locale.ROOT);
        if (raw(name, mime)) return "RAW";
        return "image/png".equalsIgnoreCase(mime) || name != null && name.toLowerCase(Locale.ROOT).endsWith(".png") ? "PNG" : "JPEG";
    }
    public static String label(DownloadedPhoto photo) {
        if (photo == null) return "JPEG";
        String internal = photo.file().getName().toLowerCase(Locale.ROOT);
        if (internal.startsWith("raw-developed-")) return "RAW";
        if (internal.startsWith("raw-")) {
            int end = internal.indexOf('-', 4);
            if (end > 4) {
                String extension = internal.substring(4, end);
                if (!rawExtension("source." + extension).isEmpty()) return extension.toUpperCase(Locale.ROOT);
            }
        }
        return photo.filename().contains("_PNG白底") ? "PNG" : label(photo.filename(), "");
    }
}
