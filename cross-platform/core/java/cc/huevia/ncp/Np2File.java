package cc.huevia.ncp;

import java.io.IOException;
import java.util.List;

/** NP2 0210 controls verified against NX Studio exports. Source bytes remain immutable. */
public final class Np2File {
    public final Np3Container container;
    public final boolean known;
    public final int baseCode;

    public Np2File(byte[] source) throws IOException {
        container = Np3Container.read(source);
        if (!container.version.startsWith("02")) throw new IOException("文件不是 NP2 预设。");
        known = container.version.equals("0210");
        byte[] base = known ? container.field(3) : null;
        baseCode = base != null && base.length == 2 ? (base[0] & 255) * 256 + (base[1] & 255) : -1;
    }

    public static boolean isNp2(byte[] data) throws IOException {
        return Np3Container.isNp3(data) && Np3Container.read(data).version.startsWith("02");
    }

    public int base() {
        switch (baseCode) {
            case 0x0001: return 1; case 0x03c2: return 2; case 0x00c3: return 3;
            case 0x064d: return 4; case 0x0486: return 5; case 0x04c7: return 6;
            default: return 0;
        }
    }

    public int scalar(int index, int type, int min, int max, int fallback, String label,
            List<String> omitted) {
        byte[] value = known ? container.field(index) : null;
        if (value != null && value.length == 2 && (value[1] & 255) == type) {
            int number = (value[0] & 255) - 128;
            if (number >= min && number <= max) return number;
        }
        omitted.add(label + "：自动、未知或超出兼容范围，已使用 " + fallback);
        return fallback;
    }

    public boolean inactive(int index, int type) {
        byte[] value = container.field(index);
        return value != null && value.length == 2 && (value[0] & 255) == 255
                && (value[1] & 255) == type;
    }

    public boolean hasUnknownRecords() {
        for (long id : container.recordIds())
            if (id != 2 && id != 0x10100 && (id < 0x100 || id > 0x1200 || id % 0x100 != 0)) return true;
        return false;
    }

    public void extraControls(List<String> omitted) {
        byte[] modification = container.field(4);
        if (modification == null || modification.length != 2 || modification[0] != 0
                || (modification[1] & 255) > 2) omitted.add("未识别的修改状态：已忽略");
        for (int id : new int[]{5, 15, 16, 17, 18})
            if (!inactive(id, 1)) omitted.add("快速调整或扩展参数（字段 " + id + "）：已忽略，使用独立参数");
        if (hasUnknownRecords()) omitted.add("未识别的 NP2 扩展参数：已忽略");
    }
}
