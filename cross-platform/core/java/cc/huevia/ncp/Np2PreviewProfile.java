package cc.huevia.ncp;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

/**
 * Phone approximation of the independently verified NP2 0210 manual subset.
 * Scalar units and the stored curve are preserved. Colour/contrast response is
 * this app's encoded-sRGB model, not Nikon's proprietary base rendering.
 * Unknown/automatic active controls never silently pass as an exact preview.
 */
public final class Np2PreviewProfile implements PresetPreviewProfile {
    public static final String MODEL_VERSION = "np2-0210-manual-quarter-v1";
    private final String name;
    private final double saturation, hue, contrast, brightness;
    private final byte[] curve;
    private final PresetPreviewProfile monochrome;
    private final SpatialPreviewFilter.Settings spatial;

    private Np2PreviewProfile(Np2File file, int sharp, int mid, int clear, int sat, int hue,
            int contrast, int brightness, byte[] curve, PresetPreviewProfile mono) {
        name = file.container.registrationName;
        saturation = sat / 4.0; this.hue = hue / 4.0;
        this.contrast = contrast / 4.0; this.brightness = brightness / 4.0;
        this.curve = curve; monochrome = mono;
        spatial = new SpatialPreviewFilter.Settings(sharp < 0 ? sharp / 12.0 : sharp / 36.0, mid / 20.0, clear / 20.0);
    }

    public static Np2PreviewProfile fromNp2(byte[] source) throws IOException {
        return fromNp2(source, 0);
    }

    static Np2PreviewProfile fromManualNcp(byte[] source) throws IOException {
        return fromNp2(exactParameters(source, false), 0);
    }

    static Np2PreviewProfile fromClassicNp3(byte[] source) throws IOException {
        Np3Container file = Np3Container.read(source);
        if (!file.canonical0310) throw unsupported("尚未核验此 NP3 布局。");
        byte[] field = file.field(22);
        int mid = (field[0] & 255) == 255 ? 0 : (field[0] & 255) - 128;
        if (field[1] != 4 || mid < -20 || mid > 20) throw unsupported("中范围锐化超出已核验范围。");
        return fromNp2(exactParameters(source, true), mid);
    }

    private static byte[] exactParameters(byte[] source, boolean allowMid) throws IOException {
        PresetFormatConversion.Plan plan = PresetFormatConversion.plan(source, "NP2");
        for (PresetFormatConversion.Row row : plan.rows) {
            if (row.status.equals("retained")) continue;
            if (allowMid && row.label.equals("中范围锐化") && row.note.equals("NP2 文件不支持此参数")) continue;
            throw unsupported(row.label + "超出已核验的手机预览范围。");
        }
        return plan.bytes();
    }

    private static Np2PreviewProfile fromNp2(byte[] source, int mid) throws IOException {
        Np2File file = new Np2File(source);
        if (!file.known) throw unsupported("尚未核验此版本的参数布局。");
        if (file.base() == 0) throw unsupported("此基础优化校准尚未核验；原文件可保留并转换兼容部分导入相机。");
        List<String> errors = new ArrayList<>();
        int sharp = file.scalar(6, 4, -12, 36, 0, "锐化", errors);
        int clear = file.scalar(7, 4, -20, 20, 0, "清晰度", errors);
        byte[] curve = file.container.record(2);
        if (curve != null && !CameraPresetProjection.validCurve(curve)) throw unsupported("自定义曲线结构尚未核验。");
        int contrast = curve == null ? file.scalar(8, 4, -12, 12, 0, "对比度", errors) : 0;
        int brightness = curve == null ? file.scalar(9, 4, -6, 6, 0, "亮度", errors) : 0;
        int sat = 0, hue = 0;
        PresetPreviewProfile mono = null;
        if (file.base() == 4) {
            int filter = file.scalar(12, 0, 0, 4, 0, "单色滤镜", errors);
            int tone = file.scalar(13, 0, 0, 9, 0, "单色调色", errors);
            int density = tone == 0 ? 0 : file.scalar(14, 4, 4, 28, 16, "单色浓度", errors);
            if ((tone != 0 && tone != 1 && tone != 4) || density % 4 != 0)
                throw unsupported("此单色调色类型或浓度尚未核验；机内导入仍可转换兼容部分。");
            String name = file.container.registrationName;
            if (name.isEmpty()) name = "NP2 Preview";
            byte[] normalized = CameraPresetProjection.ncp(name.substring(0, Math.min(19, name.length())), 4,
                    Math.max(0, Math.round(sharp / 4f)), 0, 0, curve == null ? CameraPresetProjection.identityCurve() : curve);
            normalized[45] = (byte) (128 + filter); normalized[46] = (byte) (128 + tone);
            normalized[47] = tone == 0 ? (byte) 255 : (byte) (128 + density / 4);
            mono = NcpMonochromePreviewProfile.fromNcp(normalized);
        } else {
            sat = file.scalar(10, 4, -12, 12, 0, "饱和度", errors);
            hue = file.scalar(11, 4, -12, 12, 0, "色相", errors);
        }
        file.extraControls(errors);
        if (!errors.isEmpty()) throw unsupported(String.join("；", errors) + "。原文件已保留，可继续转换导入相机。");
        return new Np2PreviewProfile(file, sharp, mid, clear, sat, hue, contrast, brightness, curve, mono);
    }

    public String registrationName() { return name; }
    public String modelVersion() { return MODEL_VERSION; }
    public SpatialPreviewFilter.Settings spatialSettings() { return spatial; }

    public double mapTone(double x) {
        if (!Double.isFinite(x) || x < 0 || x > 1) throw new IllegalArgumentException("Tone must be within 0..1");
        return manualTone(x, contrast, brightness, curve);
    }

    static double manualTone(double x, double contrast, double brightness, byte[] curve) {
        if (curve != null) {
            double p = x * 256; int lower = Math.min(255, (int) p);
            int a = sample(curve, lower), b = sample(curve, lower + 1);
            return (a + (b - a) * (p - lower)) / 32767.0;
        }
        return clamp(.5 + (x - .5) * (1 + contrast / 6.0) + brightness / 6.0);
    }

    public int applyArgb(int argb) {
        if (monochrome != null) {
            int pixel = monochrome.applyArgb(argb);
            if (curve != null) return pixel;
            return (argb & 0xff000000) | channel(mapTone(((pixel >>> 16) & 255) / 255.0)) << 16
                    | channel(mapTone(((pixel >>> 8) & 255) / 255.0)) << 8 | channel(mapTone((pixel & 255) / 255.0));
        }
        return manualColor(argb, mapTone(((argb >>> 16) & 255) / 255.0),
                mapTone(((argb >>> 8) & 255) / 255.0), mapTone((argb & 255) / 255.0), saturation, hue);
    }

    static int manualColor(int argb, double r, double g, double b, double saturation, double hue) {
        double max = Math.max(r, Math.max(g, b)), min = Math.min(r, Math.min(g, b)), delta = max - min;
        if (delta != 0 && (saturation != 0 || hue != 0)) {
            double angle = max == r ? 60 * ((g - b) / delta) : max == g ? 60 * ((b - r) / delta + 2) : 60 * ((r - g) / delta + 4);
            angle = (angle + hue * 4 + 360) % 360;
            double chroma = max * Math.min(1, delta / max * (1 + saturation / 6));
            double x = chroma * (1 - Math.abs((angle / 60) % 2 - 1)), m = max - chroma;
            switch ((int) (angle / 60)) {
                case 0: r = chroma; g = x; b = 0; break; case 1: r = x; g = chroma; b = 0; break;
                case 2: r = 0; g = chroma; b = x; break; case 3: r = 0; g = x; b = chroma; break;
                case 4: r = x; g = 0; b = chroma; break; default: r = chroma; g = 0; b = x;
            }
            r += m; g += m; b += m;
        }
        return (argb & 0xff000000) | channel(r) << 16 | channel(g) << 8 | channel(b);
    }
    private static int sample(byte[] curve, int index) { return (curve[64 + index * 2] & 255) * 256 + (curve[65 + index * 2] & 255); }
    private static double clamp(double x) { return Math.max(0, Math.min(1, x)); }
    private static int channel(double x) { return (int) Math.round(clamp(x) * 255); }
    private static IOException unsupported(String reason) { return new IOException("此 NP2 暂不支持手机预览。" + reason); }
}
