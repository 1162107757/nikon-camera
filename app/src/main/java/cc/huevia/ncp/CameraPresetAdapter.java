package cc.huevia.ncp;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/** A projection into the audited Z6II PC dataset, never a renamed or rewritten source file. */
public final class CameraPresetAdapter {
    private CameraPresetAdapter() {}

    public static final class Plan {
        public final NcpPictureControlConverter.Conversion conversion;
        public final List<String> differences;
        public final boolean approximate;
        private Plan(NcpPictureControlConverter.Conversion value, List<String> differences) {
            conversion = value;
            this.differences = Collections.unmodifiableList(new ArrayList<>(differences));
            approximate = !differences.isEmpty();
        }
        public String summary() {
            return approximate ? String.join("\n", differences) : "保留曲线、锐化、饱和度与色相；机身效果仍需试拍确认。";
        }
        public NcpPictureControlConverter.Conversion approved(boolean acceptApproximation) throws IOException {
            if (approximate && !acceptApproximation)
                throw new IOException("此预设只能部分适配，请先查看差异并确认；未发送相机写入请求。");
            return conversion;
        }
    }

    public static Plan plan(byte[] original, int middleQuarter, int clarityQuarter) throws IOException {
        if (middleQuarter < -20 || middleQuarter > 20 || clarityQuarter < -20 || clarityQuarter > 20)
            throw new IOException("锐化与清晰度超出适配范围。");
        if (original == null) throw new IOException("预设文件为空。");
        byte[] source = original.clone();
        boolean modern = source.length >= 8 && source[4] == 0 && source[5] == 0 && source[6] == 1 && source[7] == 0;
        boolean mono = source.length >= 38 && source[36] == 6 && (source[37] & 255) == 0x4d;
        if (!modern && !mono) {
            return new Plan(NcpPictureControlConverter.convert(source, middleQuarter, clarityQuarter), Collections.emptyList());
        }
        PresetPreviewProfile profile = PresetPreviewProfiles.fromPreset(source);
        List<String> differences = new ArrayList<>();
        byte[] wire = new byte[614];
        double sharpening;
        if (profile instanceof Np3PreviewProfile) {
            sharpening = ((Np3PreviewProfile) profile).sharpening();
            wire[0] = 2; // Neutral is an explicit fallback, never claimed as Flexible Color.
            differences.add("灵活色彩改为自然；色彩混合器、分区调色、全局饱和度不导入。");
            differences.add("仅近似保留明暗曲线；完整调色可在应用中使用。");
        } else if (profile instanceof Np3MonochromePreviewProfile) {
            sharpening = ((Np3MonochromePreviewProfile) profile).sharpening();
            wire[0] = 4;
            differences.add("使用标准单色基底，保留明暗曲线与锐化；专用单色响应、色彩滤镜不导入。");
        } else if (profile instanceof NcpMonochromePreviewProfile) {
            sharpening = ((NcpMonochromePreviewProfile) profile).sharpening();
            wire[0] = 4;
            differences.add("保留标准单色、明暗曲线与锐化；色彩滤镜、调色及浓度暂不导入。");
        } else throw new IOException("此配方暂不能适配到相机，可继续在应用中使用。原文件已保留。");
        byte[] name = profile.registrationName().getBytes(StandardCharsets.US_ASCII);
        if (name.length == 0 || name.length > 19) throw new IOException("相机预设名称须为 1–19 个字符。");
        System.arraycopy(name, 0, wire, 2, name.length);
        wire[25] = (byte) Math.round(sharpening * 4);
        wire[26] = (byte) middleQuarter; wire[27] = (byte) clarityQuarter;
        wire[35] = 1;
        // A valid legacy curve envelope and 257 unsigned big-endian Q15 samples.
        wire[36] = 0x49; wire[37] = 0x30; wire[39] = (byte) 255; wire[41] = (byte) 255;
        wire[42] = 1; wire[44] = 2; wire[47] = wire[48] = (byte) 255;
        for (int i = 0; i <= 256; i++) {
            double mapped = profile.mapTone(i / 256.0);
            if (!Double.isFinite(mapped) || mapped < 0 || mapped > 1) throw new IOException("曲线超出适配范围。");
            int value = (int) Math.round(mapped * 32767);
            wire[100 + i * 2] = (byte) (value >>> 8); wire[101 + i * 2] = (byte) value;
        }
        // Validated stored curves keep their metadata and samples byte for byte.
        if (profile instanceof NcpMonochromePreviewProfile) System.arraycopy(source, 56, wire, 36, 578);
        else {
            int offset = 4;
            while (offset + 8 <= source.length) {
                int id = be32(source, offset), length = be32(source, offset + 4); offset += 8;
                if (id == 2 && length == 578) { System.arraycopy(source, offset, wire, 36, 578); break; }
                if (length < 0 || length > source.length - offset) break;
                offset += length;
            }
        }
        return new Plan(NcpPictureControlConverter.adapted(source, wire,
                "部分适配\n" + String.join("\n", differences)
                        + "\n中等范围锐化 " + middleQuarter / 4.0 + "；清晰度 " + clarityQuarter / 4.0
                        + "。原始文件不变，实际效果请在相机试拍确认。"), differences);
    }

    public static Plan initialPlan(byte[] source) throws IOException {
        if (source != null && source.length >= 8 && source[6] == 1 && source[7] == 0) {
            PresetPreviewProfile profile = PresetPreviewProfiles.fromPreset(source);
            if (profile instanceof Np3PreviewProfile) {
                Np3PreviewProfile value = (Np3PreviewProfile) profile;
                return plan(source, (int) Math.round(value.midRangeSharpening() * 4), (int) Math.round(value.clarity() * 4));
            }
            if (profile instanceof Np3MonochromePreviewProfile) {
                Np3MonochromePreviewProfile value = (Np3MonochromePreviewProfile) profile;
                return plan(source, (int) Math.round(value.midRangeSharpening() * 4), (int) Math.round(value.clarity() * 4));
            }
        }
        return plan(source, 4, 0);
    }
    private static int be32(byte[] bytes, int offset) {
        return (bytes[offset] & 255) << 24 | (bytes[offset + 1] & 255) << 16
                | (bytes[offset + 2] & 255) << 8 | (bytes[offset + 3] & 255);
    }
}
