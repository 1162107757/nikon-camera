package cc.huevia.ncp;

import cc.huevia.picturecontrol.PictureControlWriteValidation;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

/** Compatible camera dataset, with partial conversion and an explicit loss report. */
final class Np2CameraProjection {
    private Np2CameraProjection() { }

    static CameraPresetProjection.Plan plan(byte[] original, Integer middle, Integer clarity) throws IOException {
        byte[] source = original.clone();
        Np2File file = new Np2File(source);
        List<String> kept = new ArrayList<>(), omitted = new ArrayList<>(), approx = new ArrayList<>();
        if (!file.known) omitted.add("未识别的 NP2 " + file.container.version + " 参数布局：已忽略专属参数");
        int base = file.base();
        if (base == 0) {
            base = 2;
            approx.add((file.baseCode == 0x028e ? "平面基底" : "未支持的基础优化校准") + "改为自然；机身色彩响应会不同");
        } else kept.add("兼容基础优化校准");
        String name = file.container.registrationName;
        if (name.isEmpty()) { name = "Converted NP2"; approx.add("相机登记名称改为 Converted NP2"); }
        if (name.length() > 19) { name = name.substring(0, 19); approx.add("相机登记名称缩短至 19 个字符"); }
        kept.add("登记名称");
        int sharp = file.scalar(6, 4, -12, 36, 0, "锐化", omitted);
        int clear = clarity == null ? file.scalar(7, 4, -20, 20, 0, "清晰度", omitted) : clarity;
        int mid = middle == null ? 0 : middle;
        if (clear < -20 || clear > 20 || mid < -20 || mid > 20) throw new IOException("锐化与清晰度超出适配范围。");
        kept.add("兼容锐化与清晰度（机内写入保留 1/4 档）");
        byte[] curve = file.known ? file.container.record(2) : null;
        if (curve != null && !CameraPresetProjection.validCurve(curve)) {
            omitted.add("不兼容的自定义曲线：已忽略，使用兼容的对比度与亮度"); curve = null;
        }
        int contrast = 0, brightness = 0;
        if (curve == null) {
            contrast = file.scalar(8, 4, -12, 12, 0, "对比度", omitted);
            brightness = file.scalar(9, 4, -6, 6, 0, "亮度", omitted);
            kept.add("兼容对比度与亮度（机内写入保留 1/4 档）");
        } else {
            kept.add("原始自定义明暗曲线");
            if (!file.inactive(8, 4) || !file.inactive(9, 4))
                omitted.add("曲线模式的独立对比度与亮度：不重复叠加，保留自定义曲线");
        }
        int sat = 0, hue = 0, filter = 0, tone = 0, density = 0;
        if (base == 4) {
            filter = file.scalar(12, 0, 0, 4, 0, "单色滤镜", omitted);
            tone = file.scalar(13, 0, 0, 9, 0, "单色调色", omitted);
            if (tone != 0) density = file.scalar(14, 4, 0, 28, 16, "单色浓度", omitted);
            kept.add("兼容单色滤镜、调色与浓度");
        } else {
            sat = file.scalar(10, 4, -12, 12, 0, "饱和度", omitted);
            hue = file.scalar(11, 4, -12, 12, 0, "色相", omitted);
            kept.add("兼容饱和度与色相（机内写入保留 1/4 档）");
        }
        file.extraControls(omitted);
        byte[] wire = new byte[curve == null ? 36 : 614];
        wire[0] = (byte) base;
        byte[] ascii = name.getBytes(StandardCharsets.US_ASCII); System.arraycopy(ascii, 0, wire, 2, ascii.length);
        wire[25] = (byte) sharp; wire[26] = (byte) mid; wire[27] = (byte) clear;
        wire[28] = (byte) contrast; wire[29] = (byte) brightness;
        wire[30] = (byte) sat; wire[31] = (byte) hue;
        wire[32] = (byte) filter; wire[33] = (byte) tone; wire[34] = (byte) density;
        if (curve != null) { wire[35] = 1; System.arraycopy(curve, 0, wire, 36, 578); }
        PictureControlWriteValidation.validateConvertedData(wire);
        // The legacy NCP companion has integer scalar units. Transport uses the independently
        // validated dataset above, never reconverts this rounded companion.
        byte[] ncp = CameraPresetProjection.ncp(name, base, Math.max(0, Math.round(sharp / 4f)),
                Math.round(sat / 4f), Math.round(hue / 4f), curve == null ? CameraPresetProjection.identityCurve() : curve);
        if (curve == null) {
            byte[] manual = new byte[52]; System.arraycopy(ncp, 0, manual, 0, 48); ncp = manual;
            ncp[41] = (byte) (128 + Math.round(contrast / 4f));
            ncp[42] = (byte) (128 + Math.max(-1, Math.min(1, Math.round(brightness / 4f))));
        }
        if (base == 4) {
            ncp[45] = (byte) (128 + filter); ncp[46] = (byte) (128 + tone);
            ncp[47] = tone == 0 ? (byte) 255 : (byte) (128 + Math.max(1, Math.round(density / 4f)));
        }
        NcpFile.validate(ncp);
        String report = "NP2 已转换为机内兼容预设，原文件保留。\n保留：" + String.join("；", kept)
                + (approx.isEmpty() ? "" : "\n近似转换：" + String.join("；", approx))
                + (omitted.isEmpty() ? "" : "\n不导入：" + String.join("；", omitted))
                + "\n可继续导入兼容部分；机身效果请试拍确认。";
        return new CameraPresetProjection.Plan(ncp, NcpPictureControlConverter.adaptedParameters(source, wire, report),
                kept, omitted, approx);
    }
}
