package cc.huevia.ncp;

import cc.huevia.library.PresetFile;
import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;

/** File-to-file Picture Control conversion. Camera wire data has a different parameter set. */
public final class PresetFormatConversion {
    private static final int[] CLASSIC_BASES = {1, 0x03c2, 0x00c3, 0x064d, 0x0486, 0x04c7};
    private static final int MONO = 0x064d, NEUTRAL = 0x03c2, FLAT = 0x028e, FLEXIBLE = 0x0020;
    private static final long COMMENT = 0x10100L;
    private static final byte[] MIXER_DEFAULT = mixerDefault();
    private static final byte[] GRADING_DEFAULT = {
            (byte) 128, 0, (byte) 128, (byte) 128, (byte) 128, 0, (byte) 128, (byte) 128,
            (byte) 128, 0, (byte) 128, (byte) 128, 1, 1, 1, 0, (byte) 178, 1, (byte) 128, 1};

    private PresetFormatConversion() { }

    public static final class Row {
        public final String label, status, note;
        private Row(String label, String status, String note) {
            this.label = label; this.status = status; this.note = note;
        }
    }

    public static final class Plan {
        public final String sourceFormat, targetFormat, cameraName;
        public final List<Row> rows;
        private final byte[] output;
        private Plan(String source, String target, Picture picture, byte[] output) {
            sourceFormat = source; targetFormat = target; cameraName = picture.name;
            rows = Collections.unmodifiableList(picture.rows);
            this.output = output;
        }
        public byte[] bytes() { return output.clone(); }
    }

    // Spatial, tone and colour values use quarter units; filter and toning are enum codes.
    private enum Control {
        SHARP(6, 4, 28, -12, 36, "锐化"), CLARITY(7, 4, -1, -20, 20, "清晰度"),
        CONTRAST(8, 4, 29, -12, 12, "对比度"), BRIGHTNESS(9, 4, 30, -6, 6, "亮度"),
        SATURATION(10, 4, 31, -12, 12, "饱和度"), HUE(11, 4, 32, -12, 12, "色相"),
        FILTER(12, 0, 33, 0, 4, "单色滤镜"), TONING(13, 0, 34, 0, 9, "单色调色"),
        DENSITY(14, 4, 35, 4, 28, "单色浓度"), MID(22, 4, -1, -20, 20, "中范围锐化");

        final int field, type, ncpOffset, min, max;
        final String label;
        Control(int field, int type, int ncpOffset, int min, int max, String label) {
            this.field = field; this.type = type; this.ncpOffset = ncpOffset;
            this.min = min; this.max = max; this.label = label;
        }
    }

    private static final class Picture {
        String name;
        int base = -1;
        byte[] curve, comment;
        final Map<Control, Integer> controls = new EnumMap<>(Control.class);
        final List<Row> rows = new ArrayList<>();
        void report(String label, String status, String note) { rows.add(new Row(label, status, note)); }
        void omit(String label, String note) { report(label, "omitted", note); }
        void keep(String label) { report(label, "retained", ""); }
        void approximate(String label, String note) { report(label, "approximate", note); }
        int value(Control control) { return controls.getOrDefault(control, control == Control.DENSITY ? 16 : 0); }
    }

    public static Plan plan(byte[] source, String target) throws IOException {
        PresetFile input = PresetFile.validate(source);
        PresetFile.requireFormat(target);
        if (input.fileFormat.equals(target)) throw new IOException("请选择与源文件不同的目标格式。");
        Picture picture = new Picture();
        picture.name = input.registrationName;
        if (picture.name.isEmpty()) {
            picture.name = "Huevia Preset";
            picture.approximate("机内名称", "源文件名称为空或无法读取，已使用 Huevia Preset");
        } else if (picture.name.length() > 19) {
            picture.name = picture.name.substring(0, 19).trim();
            picture.approximate("机内名称", "输出名称最多保留 19 个字符");
        } else picture.keep("机内名称");
        if (input.fileFormat.equals(PresetFile.NCP)) readNcp(source, picture);
        else readTagged(source, input.fileFormat, picture);
        prepareTarget(picture, target);
        byte[] bytes = target.equals(PresetFile.NCP) ? writeNcp(picture) : writeTagged(picture, target);
        PresetFile result = PresetFile.validate(bytes);
        if (!target.equals(result.fileFormat) || !picture.name.equals(result.registrationName))
            throw new IOException("转换文件未通过格式和机内名称校验。");
        return new Plan(input.fileFormat, target, picture, bytes);
    }

    static boolean isManualNcp(byte[] data) {
        if (data == null || data.length != 52) return false;
        ByteBuffer input = ByteBuffer.wrap(data);
        return input.getInt() == 0x4e435000 && input.getInt() == 1 && input.getInt() == 36
                && input.getInt() == 0x30313030 && input.getInt(48) == 0;
    }

    private static void readNcp(byte[] source, Picture picture) {
        // PresetFile validated the envelope, including the profile record and all lengths.
        ByteBuffer input = ByteBuffer.wrap(source);
        input.position(4);
        byte[] profile = null;
        boolean extended = false;
        for (int tag = input.getInt(); tag != 0; tag = input.getInt()) {
            int length = input.getInt();
            if (tag == 1 || tag == 2) {
                byte[] record = new byte[length]; input.get(record);
                if (tag == 1) { profile = record; extended |= length != 36; }
                else if (picture.curve == null) readCurve(picture, record);
                else extended = true;
            } else {
                input.position(input.position() + length);
                extended = true;
            }
        }
        picture.base = unsignedShort(profile, 24);
        if (profile[26] != 0 && profile[26] != 2) picture.omit("修改状态", "未识别的修改标记");
        if (extended || (profile[27] & 255) != 255) picture.omit("NCP 扩展参数", "未识别的附加字段");
        for (Control control : Control.values()) {
            if (control.ncpOffset < 0 || !uses(picture, control)) continue;
            int raw = profile[control.ncpOffset] & 255;
            if (raw == 255) continue;
            if (tone(control) && raw == 1) {
                if (picture.curve == null) picture.omit(control.label, "源文件指定了未能读取的曲线");
                continue;
            }
            int value = (raw - 128) * (control.type == 4 ? 4 : 1);
            store(picture, control, value);
        }
    }

    private static void readTagged(byte[] source, String format, Picture picture) throws IOException {
        Np3Container file = Np3Container.read(source);
        readCurve(picture, file.record(2));
        picture.comment = file.record(COMMENT);
        boolean np3 = format.equals(PresetFile.NP3);
        if (!file.version.equals(np3 ? "0310" : "0210")) {
            picture.omit(format + " 专属参数", "暂无法识别 " + file.version + " 版本的参数布局");
            return;
        }
        byte[] base = file.field(3);
        if (base != null && base.length == 2) picture.base = unsignedShort(base, 0);
        for (Control control : Control.values()) {
            if ((!np3 && control == Control.MID) || !uses(picture, control)) continue;
            byte[] value = file.field(control.field);
            if (inactive(value, control.type)) continue;
            if (tone(control) && pair(value, 1, control.type)) {
                if (picture.curve == null) picture.omit(control.label, "源文件指定了未能读取的曲线");
                continue;
            }
            if (value != null && value.length == 2 && (value[1] & 255) == control.type)
                store(picture, control, (value[0] & 255) - 128);
            else if (value != null) picture.omit(control.label, "参数编码不兼容，使用目标格式默认值");
        }
        if (np3 && picture.base == FLEXIBLE) {
            if (picture.curve == null) {
                int[] adjustment = new int[5];
                String[] labels = {"灵活色彩对比度", "高光", "阴影", "白色色阶", "黑色色阶"};
                boolean active = false;
                for (int i = 0; i < adjustment.length; i++) {
                    byte[] value = file.field(25 + i);
                    if (value == null || inactive(value, 1) || pair(value, 1, 1)) continue;
                    int scalar = value.length == 2 ? (value[0] & 255) - 128 : 101;
                    if (Math.abs(scalar) > 100 || value[1] != 1) {
                        picture.omit(labels[i], "超出可转换范围"); continue;
                    }
                    adjustment[i] = scalar; active |= scalar != 0;
                }
                if (active) {
                    picture.curve = CameraPresetProjection.flexibleToneCurve(adjustment);
                    picture.approximate("灵活色彩明暗", "对比度、高光、阴影、白色与黑色合成为近似曲线");
                }
            } else {
                for (int i = 25; i <= 29; i++) {
                    byte[] value = file.field(i);
                    if (active(value, 1) && !pair(value, 1, 1) && !pair(value, 128, 1)) {
                        picture.omit("灵活色彩明暗", "已保留自定义曲线，省略独立明暗调节"); break;
                    }
                }
            }
            byte[] saturation = file.field(30);
            if (saturation != null && !pair(saturation, 128, 1) && !inactive(saturation, 1)) {
                int value = saturation.length == 2 ? (saturation[0] & 255) - 128 : 101;
                if (saturation.length == 2 && saturation[1] == 1 && Math.abs(value) <= 100) {
                    picture.controls.put(Control.SATURATION, Math.round(value * 12f / 100));
                    picture.approximate("灵活色彩全局饱和度", "换算为目标格式的普通饱和度");
                } else picture.omit("灵活色彩全局饱和度", "超出可转换范围");
            }
        }
        if (np3) {
            if (activeBlock(file.field(31), MIXER_DEFAULT)) picture.omit("色彩混合器", "目标格式没有独立颜色通道");
            if (activeBlock(file.field(32), GRADING_DEFAULT)) picture.omit("分区调色", "目标格式没有高光、中间调和阴影分级");
            if (active(file.field(21), 10)) picture.omit("创意效果强度", "目标格式不支持此效果");
            if (active(file.field(23), 4) || active(file.field(24), 4)) picture.omit("扩展锐化控制", "使用可独立转换的锐化参数");
        }
        if (active(file.field(5), 1)) picture.omit("快速调整", "保留可单独转换的参数");
        for (int field = 15; field <= (np3 ? 20 : 18); field++) {
            if (active(file.field(field), 1)) picture.omit("扩展参数 " + field, "目标格式缺少对应控制");
        }
        for (long tag : file.recordIds()) {
            if (tag != 2 && tag != COMMENT && (tag < 0x100 || tag > (np3 ? 0x2000 : 0x1200) || tag % 256 != 0)) {
                picture.omit("未识别的扩展记录", "已保留在源预设中"); break;
            }
        }
    }

    private static void prepareTarget(Picture picture, String target) {
        boolean ncp = target.equals(PresetFile.NCP), np3 = target.equals(PresetFile.NP3);
        int base = picture.base;
        if (baseIndex(base) != 0 || base == FLAT && !ncp) picture.keep("基础优化校准");
        else {
            picture.base = base == 0x0655 ? MONO : base == 0x0493 ? 0x0486 : NEUTRAL;
            String source = base == FLEXIBLE ? "灵活色彩" : base == FLAT ? "平面"
                    : base == 0x0655 ? "深色调单色" : base == 0x0493 ? "丰富色调人像" : "未兼容的基底";
            String replacement = picture.base == MONO ? "标准单色" : picture.base == 0x0486 ? "人像" : "自然";
            picture.approximate("基础优化校准", source + "改为" + replacement + "，色彩响应可能不同");
        }
        if (picture.curve != null && picture.rows.stream().noneMatch(row -> row.label.equals("灵活色彩明暗")
                && row.status.equals("approximate"))) picture.keep("色调曲线");
        for (Control control : Control.values()) {
            Integer initial = picture.controls.get(control);
            if (initial == null) continue;
            if (!np3 && control == Control.MID || ncp && control == Control.CLARITY) {
                if (initial != 0) picture.omit(control.label, target + " 文件不支持此参数");
                picture.controls.remove(control);
                continue;
            }
            if (picture.curve != null && tone(control)) {
                if (initial != 0) picture.omit(control.label, "使用自定义曲线，省略独立调节");
                picture.controls.remove(control);
                continue;
            }
            int value = initial;
            if (!np3 && control == Control.SHARP) value = Math.max(0, value);
            if (ncp && control == Control.BRIGHTNESS) value = Math.max(-4, Math.min(4, value));
            if (ncp && control.type == 4) value = Math.round(value / 4f) * 4;
            picture.controls.put(control, value);
            if (value != initial) picture.approximate(control.label, "按 " + target + " 的范围和步长调整");
            else picture.keep(control.label);
        }
        if (picture.comment != null) {
            if (ncp) picture.omit("预设备注", "NCP 输出仅保留图像参数和机内名称");
            else if (picture.comment.length > NcpFile.MAX_BYTES - 2048) {
                picture.omit("预设备注", "备注过长，保留于源文件");
                picture.comment = null;
            }
            else picture.keep("预设备注");
        }
    }

    private static byte[] writeNcp(Picture picture) {
        byte[] curve = picture.curve;
        byte[] output = CameraPresetProjection.ncp(picture.name, baseIndex(picture.base),
                picture.value(Control.SHARP) / 4, picture.value(Control.SATURATION) / 4,
                picture.value(Control.HUE) / 4, curve == null ? CameraPresetProjection.identityCurve() : curve);
        if (curve == null) {
            output = Arrays.copyOf(output, 52);
            Arrays.fill(output, 48, 52, (byte) 0);
            output[41] = (byte) (128 + picture.value(Control.CONTRAST) / 4);
            output[42] = (byte) (128 + picture.value(Control.BRIGHTNESS) / 4);
        }
        if (picture.base == MONO) {
            output[45] = (byte) (128 + picture.value(Control.FILTER));
            output[46] = (byte) (128 + picture.value(Control.TONING));
            output[47] = picture.value(Control.TONING) == 0 ? (byte) 255 : (byte) (128 + picture.value(Control.DENSITY) / 4);
        }
        return output;
    }

    private static byte[] writeTagged(Picture picture, String target) throws IOException {
        boolean np3 = target.equals(PresetFile.NP3);
        byte[][] fields = new byte[np3 ? 33 : 19][];
        fields[1] = (np3 ? "0310" : "0210").getBytes(StandardCharsets.US_ASCII);
        fields[2] = Arrays.copyOf(picture.name.getBytes(StandardCharsets.US_ASCII), 20);
        fields[3] = pair(picture.base >>> 8, picture.base);
        fields[4] = pair(0, 0);
        for (int i = 5; i <= 18; i++) fields[i] = pair(255, 1);
        if (np3) {
            fields[19] = fields[20] = pair(255, 1); fields[21] = pair(255, 10);
            fields[23] = fields[24] = pair(255, 4);
            for (int i = 25; i <= 29; i++) fields[i] = pair(picture.curve == null ? 128 : 1, 1);
            fields[30] = pair(128, 1); fields[31] = MIXER_DEFAULT; fields[32] = GRADING_DEFAULT;
        }
        for (Control control : Control.values()) {
            if (control.field >= fields.length) continue;
            int code = uses(picture, control) ? 128 + picture.value(control) : 255;
            if (tone(control) && picture.curve != null) code = np3 ? 1 : 255;
            fields[control.field] = pair(code, control.type);
        }
        ByteArrayOutputStream bytes = new ByteArrayOutputStream(1024);
        try (DataOutputStream out = new DataOutputStream(bytes)) {
            out.writeInt(0x4e435000);
            for (int i = 1; i < fields.length; i++) writeRecord(out, i * 256, fields[i]);
            if (picture.comment != null) writeRecord(out, (int) COMMENT, picture.comment);
            if (picture.curve != null) writeRecord(out, 2, picture.curve);
            out.writeInt(0);
        }
        return bytes.toByteArray();
    }

    private static void writeRecord(DataOutputStream out, int tag, byte[] value) throws IOException {
        out.writeInt(tag); out.writeInt(value.length); out.write(value);
    }

    private static void readCurve(Picture picture, byte[] bytes) {
        if (bytes == null) return;
        if (CameraPresetProjection.validCurve(bytes)) picture.curve = bytes;
        else picture.omit("色调曲线", "曲线结构不兼容，使用可转换的明暗参数");
    }

    private static void store(Picture picture, Control control, int value) {
        if (value >= control.min && value <= control.max) picture.controls.put(control, value);
        else picture.omit(control.label, "自动值或超出已识别范围，使用目标格式默认值");
    }

    private static boolean uses(Picture picture, Control control) {
        boolean mono = picture.base == MONO || picture.base == 0x0655;
        if (control == Control.HUE || control == Control.SATURATION) return !mono;
        if (control == Control.FILTER || control == Control.TONING) return mono;
        return control != Control.DENSITY || mono && picture.value(Control.TONING) != 0;
    }

    private static boolean tone(Control control) { return control == Control.CONTRAST || control == Control.BRIGHTNESS; }
    private static int unsignedShort(byte[] value, int offset) { return (value[offset] & 255) << 8 | value[offset + 1] & 255; }
    private static boolean inactive(byte[] value, int type) { return pair(value, 255, type); }
    private static boolean active(byte[] value, int type) { return value != null && !inactive(value, type); }
    private static boolean activeBlock(byte[] value, byte[] neutral) { return value != null && !Arrays.equals(value, neutral); }
    private static boolean pair(byte[] value, int a, int b) {
        return value != null && value.length == 2 && (value[0] & 255) == a && (value[1] & 255) == b;
    }
    private static byte[] pair(int a, int b) { return new byte[]{(byte) a, (byte) b}; }

    private static byte[] mixerDefault() {
        byte[] bytes = new byte[28];
        Arrays.fill(bytes, 0, 24, (byte) 128);
        Arrays.fill(bytes, 24, 27, (byte) 1);
        return bytes;
    }

    private static int baseIndex(int code) {
        for (int index = 0; index < CLASSIC_BASES.length; index++) if (code == CLASSIC_BASES[index]) return index + 1;
        return 0;
    }
}
