package cc.huevia.library;

import cc.huevia.ncp.NcpFile;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.Map;

/** Storage-only checks for researched preset containers; not a camera/rendering capability claim. */
public final class PresetFile {
    public static final String NCP = "NCP", NP2 = "NP2", NP3 = "NP3";
    public final String fileFormat, version, registrationName;

    private PresetFile(String format, String version, String name) {
        this.fileFormat = format; this.version = version; this.registrationName = name;
    }

    public static String requireFormat(String value) throws IOException {
        if (!NCP.equals(value) && !NP2.equals(value) && !NP3.equals(value)) throw new IOException("预设格式须为 NCP、NP2 或 NP3。");
        return value;
    }

    /** Missing fields belong to the original NCP-only catalog/metadata schema. */
    static String formatFromMap(Map<String, Object> map) throws IOException {
        return map.containsKey("fileFormat")
                ? requireFormat(LibraryJson.string(map, "fileFormat", true, 3)) : NCP;
    }

    public static String extension(String format) throws IOException {
        return "." + requireFormat(format).toLowerCase(Locale.ROOT);
    }

    public static PresetFile validate(byte[] data) throws IOException {
        if (data == null || data.length < 8 || data.length > NcpFile.MAX_BYTES)
            throw new IOException("预设文件为空、过短或超过 1 MB。");
        if (data[0] != 'N' || data[1] != 'C' || data[2] != 'P' || data[3] != 0)
            throw new IOException("文件不是已支持的 NCP、NP2 或 NP3 预设（签名不符）。");
        // NP2/NP3 share the magic; the bounded version record determines the actual format.
        if (uint32be(data, 4) == 0x100) return validateTaggedPreset(data);
        try {
            String version = NcpFile.validate(data);
            return new PresetFile(NCP, version, ncpRegistrationName(data));
        }
        catch (IllegalArgumentException error) { throw new IOException(error.getMessage(), error); }
    }

    /** Read the camera's name field from the validated 0100 profile record. */
    private static String ncpRegistrationName(byte[] data) {
        int offset = 4;
        while (uint32be(data, offset) != 0) {
            long id = uint32be(data, offset);
            int size = (int) uint32be(data, offset + 4);
            offset += 8;
            if (id == 1) {
                int from = offset + 4;
                int end = from;
                while (end < from + 20 && data[end] != 0) {
                    if (data[end] < 32 || data[end] > 126) return "";
                    end++;
                }
                return new String(data, from, end - from, StandardCharsets.US_ASCII).trim();
            }
            offset += size;
        }
        return "";
    }

    private static PresetFile validateTaggedPreset(byte[] data) throws IOException {
        cc.huevia.ncp.Np3Container file = cc.huevia.ncp.Np3Container.read(data);
        return new PresetFile(file.version.startsWith("02") ? NP2 : NP3, file.version, file.registrationName);
    }

    private static long uint32be(byte[] data, int offset) {
        return ((long) (data[offset] & 255) << 24) | ((long) (data[offset + 1] & 255) << 16)
                | ((long) (data[offset + 2] & 255) << 8) | (data[offset + 3] & 255);
    }
}
