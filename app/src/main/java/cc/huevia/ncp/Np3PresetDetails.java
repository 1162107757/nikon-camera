package cc.huevia.ncp;

import cc.huevia.library.PresetFile;
import java.io.IOException;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

/** Read-only inspection. Numeric labels are published only after the strict renderer accepts them. */
public final class Np3PresetDetails {
    public final String version, registrationName, baseLabel, note, previewReason;
    public final int baseCode;
    public final boolean hasCustomCurve, previewSupported;
    public final List<Group> groups;

    public static final class Row {
        public final String id, label;
        public final List<String> values;
        private Row(String id, String label, String... values) {
            this.id = id; this.label = label;
            this.values = Collections.unmodifiableList(new ArrayList<>(Arrays.asList(values)));
        }
    }

    public static final class Group {
        public final String id, title;
        public final List<String> columns;
        public final List<Row> rows;
        private Group(String id, String title, List<String> columns, List<Row> rows) {
            this.id = id; this.title = title;
            this.columns = Collections.unmodifiableList(new ArrayList<>(columns));
            this.rows = Collections.unmodifiableList(new ArrayList<>(rows));
        }
    }

    private Np3PresetDetails(PresetFile file, int base, String note, boolean curve,
            boolean supported, String reason, List<Group> groups) {
        version = file.version; registrationName = file.registrationName; baseCode = base;
        baseLabel = base == 0x0020 ? "Flexible Color" : base == 0x064d ? "单色"
                : base == 0x0655 ? "深色调单色" : String.format(Locale.ROOT, "未识别基底 · 0x%04X", base);
        this.note = note; hasCustomCurve = curve; previewSupported = supported;
        previewReason = reason; this.groups = Collections.unmodifiableList(new ArrayList<>(groups));
    }

    /** A bounded defensive snapshot, with no camera I/O or changes to stored source bytes. */
    public static Np3PresetDetails read(byte[] source) throws IOException {
        if (source == null || source.length > NcpFile.MAX_BYTES) throw new IOException("NP3 文件为空或超过 1 MB。");
        byte[] data = source.clone();
        PresetFile file = PresetFile.validate(data);
        if (!PresetFile.NP3.equals(file.fileFormat)) throw new IOException("请选择 NP3 预设。");
        byte[][] fields = new byte[33][]; int offset = 4;
        // PresetFile validated every ID, length, boundary and terminator before this extraction.
        for (int index = 1; index <= 32; index++) {
            int length = (int) u32(data, offset + 4); offset += 8;
            fields[index] = Arrays.copyOfRange(data, offset, offset + length); offset += length;
        }
        String note = ""; boolean curve = false;
        while (u32(data, offset) != 0) {
            long id = u32(data, offset); int length = (int) u32(data, offset + 4); offset += 8;
            if (id == 0x10100) {
                int end = offset; while (end < offset + length && data[end] != 0) end++;
                String text = new String(data, offset, end - offset, StandardCharsets.UTF_8);
                StringBuilder clean = new StringBuilder();
                for (int i = 0; i < text.length(); i++) clean.append(Character.isISOControl(text.charAt(i)) ? ' ' : text.charAt(i));
                note = clean.toString().trim();
            } else if (id == 2) curve = true;
            offset += length;
        }
        int base = (fields[3][0] & 255) << 8 | fields[3][1] & 255;
        List<Group> groups = new ArrayList<>(); PresetPreviewProfile profile;
        try { profile = PresetPreviewProfiles.fromPreset(data); }
        catch (IOException unsupported) {
            return new Np3PresetDetails(file, base, note, curve, false, unsupported.getMessage(), groups);
        }
        List<Row> sharpness = new ArrayList<>();
        sharpness.add(row("sharpening", "锐化", (fields[6][0] & 255) - 128, 4));
        sharpness.add(row("mid-range", "中范围锐化", (fields[22][0] & 255) - 128, 4));
        sharpness.add(row("clarity", "清晰度", (fields[7][0] & 255) - 128, 4));
        groups.add(scalarGroup("detail", "细节", sharpness));
        List<Row> tone = new ArrayList<>();
        tone.add(new Row("curve", "色调曲线", curve ? "自定义 · 257 点" : "未使用"));
        if (profile instanceof Np3PreviewProfile) {
            if (!curve) {
                String[] ids = {"contrast", "highlights", "shadows", "whites", "blacks"};
                String[] names = {"对比度", "高光", "阴影", "白色色阶", "黑色色阶"};
                for (int i = 0; i < names.length; i++) tone.add(row(ids[i], names[i], (fields[25 + i][0] & 255) - 128, 1));
            }
            tone.add(row("saturation", "饱和度", (fields[30][0] & 255) - 128, 1));
            groups.add(scalarGroup("tone", "色调", tone));
            List<Row> blender = new ArrayList<>();
            String[] names = {"红", "橙", "黄", "绿", "青", "蓝", "紫", "洋红"};
            for (int i = 0; i < names.length; i++) blender.add(new Row("color-" + i, names[i],
                    signed((fields[31][i * 3] & 255) - 128, 1),
                    signed((fields[31][i * 3 + 1] & 255) - 128, 1),
                    signed((fields[31][i * 3 + 2] & 255) - 128, 1)));
            groups.add(new Group("blender", "混色器", Arrays.asList("色相", "饱和", "亮度"), blender));
            List<Row> grading = new ArrayList<>();
            String[] zones = {"高光", "中间调", "阴影"};
            for (int i = 0; i < zones.length; i++) {
                int start = i * 4;
                int hue = ((fields[32][start] & 15) << 8) | fields[32][start + 1] & 255;
                grading.add(new Row("zone-" + i, zones[i], hue + "°",
                        signed((fields[32][start + 2] & 255) - 128, 1),
                        signed((fields[32][start + 3] & 255) - 128, 1)));
            }
            groups.add(new Group("grading", "色彩分级", Arrays.asList("色相", "浓度", "亮度"), grading));
            List<Row> blend = new ArrayList<>();
            blend.add(new Row("blending", "混合", Integer.toString((fields[32][16] & 255) - 128)));
            blend.add(row("balance", "平衡", (fields[32][18] & 255) - 128, 1));
            groups.add(scalarGroup("grading-blend", "分级混合", blend));
        } else {
            int filter = fields[12][0] & 255;
            tone.add(new Row("filter-effect", "滤镜效果", filter == 0x83 ? "红色" : filter == 0x84 ? "绿色" : "关闭"));
            tone.add(new Row("toning", "调色", "关闭"));
            groups.add(scalarGroup("tone", "单色", tone));
        }
        return new Np3PresetDetails(file, base, note, curve, true, "", groups);
    }

    private static Group scalarGroup(String id, String title, List<Row> rows) {
        return new Group(id, title, Collections.emptyList(), rows);
    }
    private static Row row(String id, String label, int numerator, int denominator) {
        return new Row(id, label, signed(numerator, denominator));
    }
    private static String signed(int numerator, int denominator) {
        return (numerator > 0 ? "+" : "") + BigDecimal.valueOf(numerator)
                .divide(BigDecimal.valueOf(denominator)).stripTrailingZeros().toPlainString();
    }
    private static long u32(byte[] bytes, int offset) {
        return ((long) (bytes[offset] & 255) << 24) | ((long) (bytes[offset + 1] & 255) << 16)
                | ((long) (bytes[offset + 2] & 255) << 8) | (bytes[offset + 3] & 255);
    }
}
