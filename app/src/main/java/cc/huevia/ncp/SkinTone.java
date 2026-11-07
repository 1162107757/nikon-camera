package cc.huevia.ncp;

import java.util.List;
import java.util.Arrays;
import java.util.Collections;

/** Stable skin-colour catalogue and perceptual, detail-preserving target adaptation. */
public final class SkinTone {
    public static final int ORIGINAL = 0, CUSTOM = 10;
    public static final class Entry {
        public final int id, colorRGB;
        public final String label;
        private Entry(int id, String label, int colorRGB) { this.id = id; this.label = label; this.colorRGB = colorRGB; }
    }
    private static final List<Entry> PRESETS = Collections.unmodifiableList(Arrays.asList(
            new Entry(0, "原肤", 0),
            new Entry(1, "自然米色", 0xe1bfa5),
            new Entry(2, "粉白", 0xefd0c6),
            new Entry(3, "冷白", 0xe9d4cb),
            new Entry(4, "暖白", 0xefd4b9),
            new Entry(5, "暖杏", 0xe5b98f),
            new Entry(6, "蜜桃", 0xedb5a1),
            new Entry(7, "冷米", 0xcfb5a1),
            new Entry(8, "小麦色", 0xbb8f69),
            new Entry(9, "美黑", 0x9e7052)));
    private SkinTone() { }
    public static List<Entry> presets() { return PRESETS; }
    public static Entry byId(int id) {
        if (id < ORIGINAL || id >= CUSTOM) throw new IllegalArgumentException("肤色预设无效。");
        return PRESETS.get(id);
    }
    public static PhotoPortrait.Tone preset(int id, double amount, boolean body) {
        return new PhotoPortrait.Tone(id, byId(id).colorRGB, amount, body);
    }
    public static PhotoPortrait.Tone custom(int colorRGB, double amount, boolean body) {
        return new PhotoPortrait.Tone(CUSTOM, colorRGB, amount, body);
    }

    /* Oklab's published sRGB matrices: https://bottosson.github.io/posts/oklab/ .
       Adapt the sampled skin's colour, rather than painting the target over each pixel.
       The lightness curve remains strictly increasing even at maximum strength; chroma
       retains pixel-to-pixel differences, with hue-preserving gamut compression at edges. */
    static final class Transform {
        private final double lightness, redGreen, yellowBlue, amount;
        Transform(PhotoPortrait.Tone tone, int skinR, int skinG, int skinB) {
            amount = tone.isNeutral() ? 0 : tone.amount;
            double[] source = lab((skinR << 16) | (skinG << 8) | skinB), target = lab(tone.colorRGB);
            lightness = Math.max(-.18, Math.min(.18, target[0] - source[0]));
            double da = target[1] - source[1], db = target[2] - source[2], chroma = Math.hypot(da, db);
            double safe = chroma > .12 ? .12 / chroma : 1;
            redGreen = da * safe; yellowBlue = db * safe;
        }
        int apply(int argb, double coverage) {
            double strength = amount * Math.max(0, Math.min(1, coverage));
            if (strength == 0 || (argb >>> 24) == 0 || (Math.abs(lightness) + Math.abs(redGreen) + Math.abs(yellowBlue)) < 1e-12) return argb;
            double r = Transfer.LINEAR[(argb >>> 16) & 255], g = Transfer.LINEAR[(argb >>> 8) & 255], b = Transfer.LINEAR[argb & 255];
            double l = Math.cbrt(.4122214708 * r + .5363325363 * g + .0514459929 * b);
            double m = Math.cbrt(.2119034982 * r + .6806995451 * g + .1073969566 * b);
            double s = Math.cbrt(.0883024619 * r + .2817188376 * g + .6299787005 * b);
            double originalL = .2104542553 * l + .7936177850 * m - .0040720468 * s;
            double outL = originalL + lightness * strength * 4 * originalL * (1 - originalL);
            double outA = 1.9779984951 * l - 2.4285922050 * m + .4505937099 * s + redGreen * strength;
            double outB = .0259040371 * l + .7827717662 * m - .8086757660 * s + yellowBlue * strength;
            // Neutral chroma at this lightness is always a legal, detail-preserving fallback.
            double bestR = outL * outL * outL, bestG = bestR, bestB = bestR, lo = 0, hi = 1, scale = 1;
            for (int attempt = 0; attempt < 9; attempt++) {
                double aa = outA * scale, bb = outB * scale;
                double ll = outL + .3963377774 * aa + .2158037573 * bb;
                double mm = outL - .1055613458 * aa - .0638541728 * bb;
                double ss = outL - .0894841775 * aa - 1.2914855480 * bb;
                ll *= ll * ll; mm *= mm * mm; ss *= ss * ss;
                double rr = 4.0767416621 * ll - 3.3077115913 * mm + .2309699292 * ss;
                double gg = -1.2684380046 * ll + 2.6097574011 * mm - .3413193965 * ss;
                double blue = -.0041960863 * ll - .7034186147 * mm + 1.7076147010 * ss;
                if (rr >= 0 && rr <= 1 && gg >= 0 && gg <= 1 && blue >= 0 && blue <= 1) {
                    bestR = rr; bestG = gg; bestB = blue; lo = scale;
                    if (attempt == 0) break;
                } else hi = scale;
                scale = (lo + hi) * .5;
            }
            return (argb & 0xff000000) | (encoded(bestR) << 16) | (encoded(bestG) << 8) | encoded(bestB);
        }
    }
    /** Defer transfer-table initialization until a render, so opening the catalogue stays cheap. */
    private static final class Transfer {
        static final double[] LINEAR = new double[256];
        static final int[] ENCODED = new int[65536];
        static {
            for (int i = 0; i < LINEAR.length; i++) { double x = i / 255.0; LINEAR[i] = x <= .04045 ? x / 12.92 : Math.pow((x + .055) / 1.055, 2.4); }
            for (int i = 0; i < ENCODED.length; i++) { double x = i / 65535.0; ENCODED[i] = (int) Math.round(255 * (x <= .0031308 ? 12.92 * x : 1.055 * Math.pow(x, 1 / 2.4) - .055)); }
        }
    }
    private static int encoded(double linear) { return Transfer.ENCODED[Math.max(0, Math.min(65535, (int) Math.round(linear * 65535)))]; }
    private static double[] lab(int rgb) {
        double r = Transfer.LINEAR[(rgb >>> 16) & 255], g = Transfer.LINEAR[(rgb >>> 8) & 255], b = Transfer.LINEAR[rgb & 255];
        double l = Math.cbrt(.4122214708 * r + .5363325363 * g + .0514459929 * b);
        double m = Math.cbrt(.2119034982 * r + .6806995451 * g + .1073969566 * b);
        double s = Math.cbrt(.0883024619 * r + .2817188376 * g + .6299787005 * b);
        return new double[]{.2104542553 * l + .7936177850 * m - .0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + .4505937099 * s,
                .0259040371 * l + .7827717662 * m - .8086757660 * s};
    }
}
