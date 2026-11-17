package cc.huevia.ncp;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

/** Bounded storage reader. Unknown effects are data, not a rendering capability gate. */
public final class Np3Container {
    private final Map<Long, byte[]> records;
    public final String version, registrationName;
    public final boolean canonical0310;

    private Np3Container(Map<Long, byte[]> records, boolean canonical) throws IOException {
        this.records = Collections.unmodifiableMap(records);
        byte[] v = records.get(0x100L);
        if (v == null || v.length != 4) throw new IOException("NP3 缺少版本记录。");
        version = new String(v, StandardCharsets.US_ASCII);
        if (!version.matches("[0-9]{4}")) throw new IOException("NP3 版本记录无效。");
        byte[] name = records.get(0x200L);
        StringBuilder text = new StringBuilder();
        if (name != null) for (byte b : name) {
            int c = b & 255;
            if (c == 0) break;
            if (c < 32 || c > 126) { text.setLength(0); break; }
            text.append((char) c);
        }
        registrationName = text.toString().trim();
        canonical0310 = canonical && version.equals("0310");
    }

    public static boolean isNp3(byte[] data) {
        return data != null && data.length >= 8 && data[0] == 'N' && data[1] == 'C'
                && data[2] == 'P' && data[3] == 0 && u32(data, 4) == 0x100;
    }

    public static Np3Container read(byte[] input) throws IOException {
        if (!isNp3(input) || input.length > NcpFile.MAX_BYTES)
            throw new IOException("NP3 签名无效或文件超过 1 MB。");
        byte[] data = input.clone();
        Map<Long, byte[]> records = new LinkedHashMap<>();
        int offset = 4, index = 1;
        boolean canonical = true;
        while (offset <= data.length - 4) {
            long id = u32(data, offset); offset += 4;
            if (id == 0) {
                if (offset != data.length) throw new IOException("NP3 终止标记后存在附加数据。");
                return new Np3Container(records, canonical && index > 32);
            }
            if (offset > data.length - 4) throw new IOException("NP3 记录缺少长度。");
            long size = u32(data, offset); offset += 4;
            if (size > data.length - offset) throw new IOException("NP3 记录长度超出文件范围。");
            if (records.size() >= 256 || records.containsKey(id))
                throw new IOException("NP3 记录过多或含重复记录。");
            if (index <= 32) {
                int expected = index == 1 ? 4 : index == 2 || index == 32 ? 20 : index == 31 ? 28 : 2;
                canonical &= id == index * 0x100L && size == expected;
            }
            records.put(id, Arrays.copyOfRange(data, offset, offset + (int) size));
            offset += (int) size; index++;
        }
        throw new IOException("NP3 缺少完整的终止标记。");
    }

    public byte[] field(int index) { return record(index * 0x100L); }
    public byte[] record(long id) {
        byte[] data = records.get(id);
        return data == null ? null : data.clone();
    }
    public boolean hasUnknownRecords() {
        for (long id : records.keySet())
            if (id != 2 && id != 0x10100 && (id < 0x100 || id > 0x2000 || id % 0x100 != 0)) return true;
        return false;
    }
    private static long u32(byte[] b, int o) {
        return ((long) (b[o] & 255) << 24) | ((long) (b[o + 1] & 255) << 16)
                | ((long) (b[o + 2] & 255) << 8) | (b[o + 3] & 255);
    }
}
