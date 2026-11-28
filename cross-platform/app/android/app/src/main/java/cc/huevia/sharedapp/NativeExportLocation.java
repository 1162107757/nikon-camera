package cc.huevia.sharedapp;

import android.media.ExifInterface;
import android.content.ContentResolver;
import android.net.Uri;
import cc.huevia.shared.SharedRuntime;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.util.Map;

final class NativeExportLocation {
    private static final String[] TAGS = {
        ExifInterface.TAG_GPS_VERSION_ID,
        ExifInterface.TAG_GPS_LATITUDE, ExifInterface.TAG_GPS_LATITUDE_REF,
        ExifInterface.TAG_GPS_LONGITUDE, ExifInterface.TAG_GPS_LONGITUDE_REF,
        ExifInterface.TAG_GPS_ALTITUDE, ExifInterface.TAG_GPS_ALTITUDE_REF,
        ExifInterface.TAG_GPS_DATESTAMP, ExifInterface.TAG_GPS_TIMESTAMP,
        ExifInterface.TAG_GPS_MAP_DATUM, ExifInterface.TAG_GPS_STATUS,
        ExifInterface.TAG_GPS_MEASURE_MODE, ExifInterface.TAG_GPS_DOP,
        ExifInterface.TAG_GPS_SATELLITES, ExifInterface.TAG_GPS_PROCESSING_METHOD,
        ExifInterface.TAG_GPS_AREA_INFORMATION, ExifInterface.TAG_GPS_DIFFERENTIAL
    };

    private NativeExportLocation() {}

    static Boolean hasLocation(File file) {
        try { return valid(new ExifInterface(file.getPath()), new float[2]); }
        catch (IOException | RuntimeException unavailable) { return null; }
    }

    static Boolean hasLocation(ContentResolver resolver, Uri uri) {
        try (InputStream saved = resolver.openInputStream(uri)) {
            return saved == null ? null : valid(new ExifInterface(saved), new float[2]);
        } catch (IOException | RuntimeException unavailable) { return null; }
    }

    static String copy(SharedRuntime runtime, Map<String, Object> request, File source,
                       String sourceSha, File target) throws IOException {
        if (Boolean.FALSE.equals(request.get("preserveLocation"))) return "";
        ExifInterface location = new ExifInterface(source.getPath());
        float[] coordinates = new float[2];
        if (!valid(location, coordinates)) {
            if (!request.containsKey("locationSource")) return "";
            Map<String, Object> linked = SharedRuntime.object(request.get("locationSource"));
            sourceSha = SharedRuntime.text(linked, "sha256", 64);
            File original = runtime.exportLocationSource(SharedRuntime.text(linked, "path", 4096), sourceSha);
            if (original == null) return "";
            location = new ExifInterface(original.getPath());
            if (!valid(location, coordinates)) return "";
        }
        ExifInterface result = new ExifInterface(target.getPath());
        for (String tag : TAGS) {
            String value = location.getAttribute(tag);
            if (value != null) result.setAttribute(tag, value);
        }
        result.saveAttributes();
        float[] saved = new float[2];
        if (!valid(new ExifInterface(target.getPath()), saved)
            || saved[0] != coordinates[0] || saved[1] != coordinates[1]) {
            throw new IOException("导出文件的位置未能通过校验。");
        }
        return sourceSha;
    }

    private static boolean valid(ExifInterface exif, float[] coordinates) {
        return exif.getLatLong(coordinates) && Math.abs(coordinates[0]) <= 90 && Math.abs(coordinates[1]) <= 180;
    }
}
