package cc.huevia.ncp;

import java.io.IOException;

/** Rich Tone Portrait (NP3 0310), approximated on the app's rendered sRGB input. */
final class Np3RichTonePortraitProfile implements PresetPreviewProfile {
    static final int BASE_CODE = 0x0493;
    static final String MODEL_VERSION = "np3-0310-rich-tone-portrait-v1";

    // Encoded-RGB residual fitted to NX Studio 1.11.0 Standard/Rich Tone Portrait
    // exports of a colour chart and a portrait scene, with a separate Z6 scene held out.
    // Basis: 1, r, g, b, r², rg, rb, g², gb, b², centred on middle grey.
    private static final double[][] RESIDUAL = {
        { .0043843, -.0329537, -.0169980, .0340457, .0010597, -.0089714,
            .0096960, .0438850, -.1237648, .0662328 },
        { .0010000, -.0274497, -.0049580, .0164306, .0545384, -.0309704,
            -.0053260, -.0232621, -.0381317, .0348375 },
        { -.0038356, -.0596983, .0707125, -.0258262, .0654439, -.0770509,
            .0147266, .0245823, -.0182235, -.0122782 }
    };

    private final String name;
    private final double contrast, brightness, saturation, hue;
    private final byte[] curve;
    private final SpatialPreviewFilter.Settings detail;

    private Np3RichTonePortraitProfile(Np3Container file) throws IOException {
        name = file.registrationName;
        curve = file.record(2);
        if (curve != null && !CameraPresetProjection.validCurve(curve)) {
            throw unsupported("自定义曲线结构无效。");
        }
        contrast = curve == null ? scalar(file, 8, -12, 12, 0) / 4.0 : 0;
        brightness = curve == null ? scalar(file, 9, -6, 6, 0) / 4.0 : 0;
        saturation = scalar(file, 10, -12, 12, 0) / 4.0;
        hue = scalar(file, 11, -12, 12, 0) / 4.0;

        // The reference already includes the base's default detail settings.
        // Apply relative detail changes on top of that look, in quarter units.
        int sharpening = scalar(file, 6, -12, 36, 8) - 8;
        int midRange = scalar(file, 22, -20, 20, 4) - 4;
        int clarity = scalar(file, 7, -20, 20, 4) - 4;
        detail = new SpatialPreviewFilter.Settings(sharpening / 36.0, midRange / 24.0, clarity / 24.0);
    }

    static Np3RichTonePortraitProfile fromNp3(byte[] bytes) throws IOException {
        Np3Container file = Np3Container.read(bytes);
        if (!file.canonical0310 || file.registrationName.isEmpty() || file.hasUnknownRecords()) {
            throw unsupported("参数布局尚未核验。");
        }
        if (!matches(file.field(3), 4, 0x93) || !matches(file.field(4), 0, 0)
                || !matches(file.field(5), 255, 1) || !matches(file.field(12), 255, 0)
                || !matches(file.field(13), 255, 0) || !matches(file.field(14), 255, 4)
                || !matches(file.field(20), 128, 1) || !matches(file.field(21), 255, 10)
                || !matches(file.field(23), 255, 4) || !matches(file.field(24), 255, 4)) {
            throw unsupported("检测到未经核验的基底控制参数。");
        }
        for (int i = 15; i <= 19; i++) {
            if (!matches(file.field(i), 255, 1)) throw unsupported("检测到未验证的自动色彩调整。");
        }
        for (int i = 25; i <= 30; i++) {
            if (!matches(file.field(i), 128, 1)) throw unsupported("检测到未验证的灵活颜色调整。");
        }
        byte[] mixer = file.field(31);
        for (int i = 0; i < 24; i++) {
            if ((mixer[i] & 255) != 128) throw unsupported("检测到未验证的混色器调整。");
        }
        if (mixer[24] != 1 || mixer[25] != 1 || mixer[26] != 1 || mixer[27] != 0
                || !matches(file.field(32), 128, 0, 128, 128, 128, 0, 128, 128, 128, 0,
                    128, 128, 1, 1, 1, 0, 178, 1, 128, 1)) {
            throw unsupported("检测到未验证的分区调色参数。");
        }
        return new Np3RichTonePortraitProfile(file);
    }

    @Override public String registrationName() { return name; }
    @Override public String modelVersion() { return MODEL_VERSION; }
    @Override public SpatialPreviewFilter.Settings spatialSettings() { return detail; }

    @Override public double mapTone(double x) {
        if (!Double.isFinite(x) || x < 0 || x > 1) throw new IllegalArgumentException("Tone must be within 0..1");
        double centred = 2 * x - 1;
        double weight = endpointWeight(x);
        return .2126 * tone(x, centred, centred, centred, 0, weight)
                + .7152 * tone(x, centred, centred, centred, 1, weight)
                + .0722 * tone(x, centred, centred, centred, 2, weight);
    }

    @Override public int applyArgb(int argb) {
        double red = ((argb >>> 16) & 255) / 255.0;
        double green = ((argb >>> 8) & 255) / 255.0;
        double blue = (argb & 255) / 255.0;
        double range = Math.max(red, Math.max(green, blue)) - Math.min(red, Math.min(green, blue));
        double weight = endpointWeight(.2126 * red + .7152 * green + .0722 * blue)
                * Math.min(1, (1 - range) / .45);
        double r = 2 * red - 1, g = 2 * green - 1, b = 2 * blue - 1;
        return Np2PreviewProfile.manualColor(argb, tone(red, r, g, b, 0, weight),
                tone(green, r, g, b, 1, weight), tone(blue, r, g, b, 2, weight), saturation, hue);
    }

    private double tone(double value, double r, double g, double b, int channel, double weight) {
        double[] c = RESIDUAL[channel];
        double delta = c[0] + r * (c[1] + c[4] * r + c[5] * g + c[6] * b)
                + g * (c[2] + c[7] * g + c[8] * b) + b * (c[3] + c[9] * b);
        // Reduce extrapolation at black, white and nearly clipped primaries.
        double base = Math.max(0, Math.min(1, value + Math.max(-.08, Math.min(.08, delta)) * weight));
        if (curve == null && contrast == 0 && brightness == 0) return base;
        return Np2PreviewProfile.manualTone(base, contrast, brightness, curve);
    }

    private static double endpointWeight(double luminance) {
        return Math.min(1, Math.min(luminance, 1 - luminance) / .08);
    }

    private static int scalar(Np3Container file, int index, int min, int max, int fallback) throws IOException {
        byte[] field = file.field(index);
        if (matches(field, 255, 4)) return fallback;
        int value = (field[0] & 255) - 128;
        if (field[1] != 4 || value < min || value > max) {
            throw unsupported(String.format(java.util.Locale.ROOT, "控制参数 0x%04X 超出已验证范围。", index * 256));
        }
        return value;
    }

    private static boolean matches(byte[] stored, int... values) {
        if (stored.length != values.length) return false;
        for (int i = 0; i < values.length; i++) if ((stored[i] & 255) != values[i]) return false;
        return true;
    }

    private static IOException unsupported(String reason) {
        return new IOException("此丰富色调人像 NP3 暂不支持手机预览。" + reason);
    }
}
