package cc.huevia.library;

import cc.huevia.ncp.NcpFile;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.Map;

/** Storage-only checks for researched preset containers; not a camera/rendering capability claim. */
public final class PresetFile {
    public static final String NCP = "NCP", NP3 = "NP3";
    public final String fileFormat, version, registrationName;

    private PresetFile(String format, String version, String name) {
        this.fileFormat = format; this.version = version; this.registrationName = name;
    }

    public static String requireFormat(String value) throws IOException {
        if (!NCP.equals(value) && !NP3.equals(value)) throw new IOException("预设格式须为 NCP 或 NP3。");
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
            throw new IOException("文件不是已支持的 NCP 或 NP3 预设（签名不符）。");
        // The common magic cannot distinguish NP3. Its version is the first 0x100 record.
        if (uint32be(data, 4) == 0x100) return validateNp3(data);
        try { return new PresetFile(NCP, NcpFile.validate(data), ""); }
        catch (IllegalArgumentException error) { throw new IOException(error.getMessage(), error); }
    }

    private static PresetFile validateNp3(byte[] data) throws IOException {
        cc.huevia.ncp.Np3Container file = cc.huevia.ncp.Np3Container.read(data);
        return new PresetFile(NP3, file.version, file.registrationName);
    }

    private static long uint32be(byte[] data, int offset) {
        return ((long) (data[offset] & 255) << 24) | ((long) (data[offset + 1] & 255) << 16)
                | ((long) (data[offset + 2] & 255) << 8) | (data[offset + 3] & 255);
    }
}
