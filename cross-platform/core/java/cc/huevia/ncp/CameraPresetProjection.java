package cc.huevia.ncp;

import cc.huevia.picturecontrol.PictureControlWriteValidation;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

/** Projects independently understood NP3 fields; unsupported effects never veto a valid container. */
public final class CameraPresetProjection {
    private CameraPresetProjection() { }

    public static final class Plan {
        public final NcpPictureControlConverter.Conversion conversion;
        public final List<String> retained, omitted, approximated;
        private final byte[] ncp;
        private Plan(byte[] ncp, NcpPictureControlConverter.Conversion conversion,
                List<String> retained, List<String> omitted, List<String> approximated) {
            this.ncp = ncp.clone(); this.conversion = conversion;
            this.retained = Collections.unmodifiableList(new ArrayList<>(retained));
            this.omitted = Collections.unmodifiableList(new ArrayList<>(omitted));
            this.approximated = Collections.unmodifiableList(new ArrayList<>(approximated));
        }
        public byte[] ncpBytes() { return ncp.clone(); }
    }

    /** Null tuning keeps the NP3 values. Explicit UI adjustments override only those two values. */
    public static Plan plan(byte[] original, Integer middle, Integer clarity) throws IOException {
        if (!Np3Container.isNp3(original)) {
            CameraPresetAdapter.Plan old = CameraPresetAdapter.plan(original, middle == null ? 4 : middle,
                    clarity == null ? 0 : clarity);
            return new Plan(original, old.approved(true), Collections.singletonList("原 NCP 的兼容参数"),
                    old.differences, Collections.emptyList());
        }
        byte[] source = original.clone();
        Np3Container file = Np3Container.read(source);
        List<String> kept = new ArrayList<>(), dropped = new ArrayList<>(), approx = new ArrayList<>();
        // Only this researched layout assigns semantics to scalar IDs. Future fields remain stored.
        boolean known = file.version.equals("0310");
        if (!known) dropped.add("未识别的 NP3 " + file.version + " 参数布局：已忽略专属参数");
        byte[] baseField = file.field(3);
        int baseCode = known && baseField != null && baseField.length == 2
                ? ((baseField[0] & 255) << 8) | (baseField[1] & 255) : -1;
        int base = base(baseCode);
        if (baseCode == 0x20) approx.add("灵活色彩基底改为自然；相机色彩响应会不同");
        else if (baseCode == 0x655) approx.add("深色调单色基底改为标准单色");
        else if (base == 2 && baseCode != 0x3c2)
            approx.add(String.format(Locale.ROOT, "未支持的基底（%s）改为自然", baseCode < 0 ? "未知" : String.format(Locale.ROOT, "0x%04X", baseCode)));
        else kept.add("兼容基础优化校准");

        String name = file.registrationName;
        if (name.isEmpty()) { name = "Converted NP3"; approx.add("相机登记名称改为 Converted NP3"); }
        if (name.length() > 19) { name = name.substring(0, 19); approx.add("相机登记名称缩短至 19 个字符"); }
        kept.add("登记名称");
        int sharp = known ? scalar(file, 6, 4, -12, 36, 0, "锐化", dropped) : 0;
        int ncpSharp = Math.max(0, Math.min(9, Math.round(sharp / 4f)));
        if (ncpSharp * 4 != sharp) approx.add("锐化按 NCP 的 0–9 整数档取值：" + ncpSharp);
        else kept.add("锐化");
        int mid = middle != null ? middle : known ? scalar(file, 22, 4, -20, 20, 0, "中范围锐化", dropped) : 0;
        int clear = clarity != null ? clarity : known ? scalar(file, 7, 4, -20, 20, 0, "清晰度", dropped) : 0;
        if (mid < -20 || mid > 20 || clear < -20 || clear > 20) throw new IOException("锐化与清晰度超出适配范围。");
        kept.add("中范围锐化与清晰度（通过相机兼容适配写入）");

        byte[] curve = file.record(2);
        boolean stored = validCurve(curve);
        if (stored) kept.add("原始自定义明暗曲线");
        else {
            if (curve != null) dropped.add("不兼容的自定义曲线：已使用中性曲线");
            curve = identityCurve();
            if (known && baseCode == 0x20 && file.record(2) == null) {
                int[] basic = new int[5]; boolean active = false;
                String[] labels = {"对比度", "高光", "阴影", "白色", "黑色"};
                for (int i = 0; i < 5; i++) {
                    basic[i] = scalar(file, 25 + i, 1, -100, 100, 0, labels[i], dropped);
                    active |= basic[i] != 0;
                }
                if (active) {
                    for (int i = 0; i <= 256; i++) {
                        double x = i / 256.0, upper = x * x * (3 - 2 * x), y = 1 - x;
                        double lower = y * y * (3 - 2 * y);
                        double tone = x + basic[1] / 250.0 * upper * (1 - x)
                                + basic[2] / 250.0 * lower * x + basic[3] / 500.0 * x * x
                                + basic[4] / 500.0 * (1 - x) * (1 - x)
                                - .0008 * basic[0] * Math.sin(2 * Math.PI * x);
                        sample(curve, i, tone);
                    }
                    approx.add("灵活色彩的对比度、高光、阴影、白色、黑色合成为近似明暗曲线");
                } else kept.add("中性明暗曲线");
            } else kept.add("中性明暗曲线");
        }

        int sat = 0, hue = 0;
        if (known) {
            if (baseCode == 0x20) {
                dropped.add("灵活色彩全局饱和度：NCP 不支持，已忽略");
            } else if (base != 4) {
                sat = legacyScalar(file, 10, "饱和度", dropped, approx);
                hue = legacyScalar(file, 11, "色相", dropped, approx);
                kept.add("兼容的饱和度与色相");
            }
            for (int index : new int[]{8, 9}) {
                byte[] f = file.field(index);
                if (f != null && f.length == 2 && (f[0] & 255) != 1 && (f[0] & 255) != 255 && (f[0] & 255) != 128)
                    dropped.add((index == 8 ? "传统对比度" : "传统亮度") + "：当前 NCP 自定义曲线模式不单独应用，已忽略");
            }
            if (base == 4) {
                dropped.add("专用单色响应：已忽略，使用标准单色");
                dropped.add("单色色彩滤镜：已忽略");
                dropped.add("单色调色：已忽略");
                dropped.add("单色浓度：已忽略");
            }
            if (baseCode != 0x20) dropped.add("NP3 专属色彩：NCP 不支持，已忽略");
            dropped.add("色彩混合器：NCP 不支持，已忽略");
            dropped.add("分区调色：NCP 不支持，已忽略");
            dropped.add("Quick Sharp 联动：已忽略，使用已转换的独立参数");
            dropped.add("自动参数：已忽略，使用已转换的独立参数");
            dropped.add("创意效果强度：NCP 不支持，已忽略");
        }
        if (file.hasUnknownRecords()) dropped.add("未识别的扩展参数：已忽略");

        byte[] ncp = ncp(name, base, ncpSharp, sat, hue, curve);
        NcpFile.validate(ncp);
        byte[] wire = new byte[614]; wire[0] = (byte) base;
        System.arraycopy(ncp, 16, wire, 2, 20);
        wire[25] = (byte) (ncpSharp * 4); wire[26] = (byte) mid; wire[27] = (byte) clear;
        wire[30] = (byte) (sat * 4); wire[31] = (byte) (hue * 4); wire[35] = 1;
        System.arraycopy(curve, 0, wire, 36, 578);
        PictureControlWriteValidation.validateConvertedData(wire);
        String report = "NP3 已转换为兼容 NCP，原文件保留。\n保留：" + String.join("；", kept)
                + (approx.isEmpty() ? "" : "\n近似转换：" + String.join("；", approx))
                + (dropped.isEmpty() ? "" : "\n不导入：" + String.join("；", dropped))
                + "\n可继续导入以上兼容部分；机身效果请试拍确认。";
        return new Plan(ncp, NcpPictureControlConverter.adapted(source, wire, report), kept, dropped, approx);
    }

    private static int scalar(Np3Container f, int index, int type, int min, int max, int fallback,
            String label, List<String> dropped) {
        byte[] value = f.field(index);
        if (value != null && value.length == 2 && (value[1] & 255) == type) {
            int number = (value[0] & 255) - 128;
            if (number >= min && number <= max) return number;
        }
        dropped.add(label + "：自动、未知或超出兼容范围，已使用 " + fallback);
        return fallback;
    }
    private static int legacyScalar(Np3Container f, int index, String label, List<String> dropped, List<String> approx) {
        byte[] b = f.field(index);
        if (b != null && b.length == 2 && (b[0] & 255) == 255 && (b[1] & 255) == 4) return 0;
        int quarter = scalar(f, index, 4, -12, 12, 0, label, dropped);
        int integer = Math.round(quarter / 4f);
        if (integer * 4 != quarter) approx.add(label + "按 NCP 整数档取值：" + integer);
        return integer;
    }
    private static int base(int code) {
        switch (code) {
            case 0x0001: return 1; case 0x03c2: return 2; case 0x00c3: return 3;
            case 0x064d: case 0x0655: return 4; case 0x0486: return 5; case 0x04c7: return 6;
            default: return 2;
        }
    }
    private static byte[] ncp(String name, int base, int sharp, int sat, int hue, byte[] curve) {
        byte[] b = new byte[638]; b[0] = 'N'; b[1] = 'C'; b[2] = 'P'; b[7] = 1; b[11] = 36;
        System.arraycopy("0100".getBytes(StandardCharsets.US_ASCII), 0, b, 12, 4);
        byte[] text = name.getBytes(StandardCharsets.US_ASCII); System.arraycopy(text, 0, b, 16, text.length);
        int[] codes = {0, 1, 0x3c2, 0xc3, 0x64d, 0x486, 0x4c7};
        b[36] = (byte) (codes[base] >>> 8); b[37] = (byte) codes[base]; b[39] = (byte) 255;
        b[40] = (byte) (128 + sharp); b[41] = b[42] = 1;
        b[43] = (byte) (128 + sat); b[44] = (byte) (128 + hue);
        b[45] = b[46] = b[47] = (byte) 255;
        if (base == 4) { b[43] = b[44] = (byte) 255; b[45] = b[46] = (byte) 128; }
        b[51] = 2; b[54] = 2; b[55] = 0x42; System.arraycopy(curve, 0, b, 56, 578);
        return b;
    }
    private static boolean validCurve(byte[] c) {
        if (c == null || c.length != 578 || c[0] != 0x49 || c[1] != 0x30
                || (c[6] & 255) > 20 || (c[7] & 255) > 100 || (c[8] & 255) < 2 || (c[8] & 255) > 20) return false;
        for (int i = 49; i < 64; i++) if (c[i] != 0) return false;
        for (int i = 64; i < 578; i += 2) if ((((c[i] & 255) << 8) | (c[i + 1] & 255)) > 32767) return false;
        return true;
    }
    private static byte[] identityCurve() {
        byte[] c = new byte[578]; c[0] = 0x49; c[1] = 0x30; c[3] = c[5] = c[11] = c[12] = (byte) 255;
        c[6] = 1; c[8] = 2;
        for (int i = 0; i <= 256; i++) sample(c, i, i / 256.0);
        return c;
    }
    private static void sample(byte[] c, int i, double tone) {
        int value = (int) Math.round(Math.max(0, Math.min(1, tone)) * 32767);
        c[64 + i * 2] = (byte) (value >>> 8); c[65 + i * 2] = (byte) value;
    }
}
