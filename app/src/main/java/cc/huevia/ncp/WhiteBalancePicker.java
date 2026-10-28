package cc.huevia.ncp;

/**
 * White balance picker for Phase 1.
 *
 * <p>Given a neutral-coloured sample taken from the original (unadjusted)
 * photo, compute the existing {@code TEMPERATURE} / {@code TINT} values
 * that neutralise it. This is the inverse of the channel gains used in
 * {@code AdjustedPreviewProfile}:
 *
 * <pre>
 * gainR = exp(0.35*t + 0.13*tint)
 * gainG = exp(-0.15*tint)
 * gainB = exp(-0.35*t + 0.13*tint)
 * </pre>
 *
 * <p>where {@code t = TEMPERATURE / 100.0} and {@code tint = TINT / 100.0}.
 * Requiring {@code gainR * r == gainG * g == gainB * b} (in linear light)
 * gives:
 *
 * <pre>
 * 0.35*t + 0.28*tint = log(g / r)
 * -0.35*t + 0.28*tint = log(g / b)
 * </pre>
 *
 * <p>Solving yields the temperature and tint below. No new adjustment
 * parameter is introduced, so draft, recipe and export identity handling
 * for temperature/tint is unchanged. The caller is responsible for
 * sampling from the original photo and for wiring the result into the
 * editor's existing temperature/tint controls (UI integration is the
 * next step, not part of this file).
 */
public final class WhiteBalancePicker {
    private WhiteBalancePicker() {
    }

    /** Return a copy of {@code current} with temperature/tint set from {@code rgb}. */
    public static PhotoAdjustments pick(int rgb, PhotoAdjustments current) {
        if (current == null) {
            throw new IllegalArgumentException("current adjustments must not be null");
        }
        int[] values = computeTemperatureTint(rgb);
        return current
                .with(PhotoAdjustments.Parameter.TEMPERATURE, values[0])
                .with(PhotoAdjustments.Parameter.TINT, values[1]);
    }

    /**
     * Compute {@code {temperature, tint}} in the existing -100..100 range
     * for an sRGB sample packed as {@code 0xRRGGBB} (alpha is ignored).
     * A sample that is already neutral returns {@code {0, 0}}.
     */
    public static int[] computeTemperatureTint(int rgb) {
        int r = Math.max(1, (rgb >>> 16) & 255);
        int g = Math.max(1, (rgb >>> 8) & 255);
        int b = Math.max(1, rgb & 255);
        double lr = linear(r / 255.0);
        double lg = linear(g / 255.0);
        double lb = linear(b / 255.0);
        double logRg = Math.log(lg / lr);
        double logBg = Math.log(lg / lb);
        double t = (logRg - logBg) / 0.70;
        double tint = (logRg + logBg) / 0.56;
        return new int[]{
                clamp((int) Math.round(t * 100.0), -100, 100),
                clamp((int) Math.round(tint * 100.0), -100, 100)
        };
    }

    private static double linear(double v) {
        return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
    }

    private static int clamp(int value, int min, int max) {
        return Math.max(min, Math.min(max, value));
    }
}
