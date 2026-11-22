package cc.huevia.sharedapp;

import java.nio.charset.StandardCharsets;
import java.util.regex.Pattern;

/** Recognize the published Google Motion Photo / Micro Video XMP flags. */
final class MotionPhotoMetadata {
    private static final Pattern FLAG = Pattern.compile(
        "(?:[A-Za-z_][\\w.-]*:)?(?:MotionPhoto|MicroVideo)\\s*=\\s*[\"']1[\"']"
        + "|<(?:[A-Za-z_][\\w.-]*:)?(?:MotionPhoto|MicroVideo)>\\s*1\\s*</");

    static boolean isMotion(byte[] bytes) {
        if (bytes == null || bytes.length == 0 || bytes.length > 512 * 1024) return false;
        String xmp = new String(bytes, StandardCharsets.UTF_8);
        return xmp.contains("http://ns.google.com/photos/1.0/camera/") && FLAG.matcher(xmp).find();
    }
}
