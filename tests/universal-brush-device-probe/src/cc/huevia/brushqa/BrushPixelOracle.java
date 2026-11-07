package cc.huevia.brushqa;

import android.graphics.Bitmap;
import java.lang.reflect.Method;
import org.json.JSONObject;

/** Uses the installed model's real painted-mask sampler; never packages a production filter copy. */
final class BrushPixelOracle {
    interface Assertion { void check(String label, boolean pass); }

    private final int width, height;
    private final boolean[] outside;
    final int zeroMaskPixels, coveredPixels;

    BrushPixelOracle(Object region, int width, int height) throws Exception {
        this(region, width, height, null);
    }

    BrushPixelOracle(Object region, int width, int height, Object skinRestriction) throws Exception {
        this.width = width;
        this.height = height;
        outside = new boolean[width * height];
        Method compile = region.getClass().getMethod("compileBrush", int.class, int.class);
        compile.setAccessible(true);
        Object mask = compile.invoke(region, width, height);
        Method sample = mask.getClass().getMethod("weight", double.class, double.class);
        sample.setAccessible(true);
        Method skinSample = skinRestriction == null ? null
                : skinRestriction.getClass().getMethod("weight", double.class, double.class);
        if (skinSample != null) skinSample.setAccessible(true);
        int zeros = 0;
        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                double coverage = ((Number) sample.invoke(mask, (x + .5) / width, (y + .5) / height)).doubleValue();
                boolean zero = coverage == 0 || skinSample != null
                        && ((Number) skinSample.invoke(skinRestriction, (x + .5) / width,
                                (y + .5) / height)).doubleValue() == 0;
                outside[y * width + x] = zero;
                if (zero) zeros++;
            }
        }
        zeroMaskPixels = zeros;
        coveredPixels = width * height - zeros;
    }

    JSONObject compare(Bitmap before, Bitmap after, String label, boolean requireVisibleChange,
            Assertion assertion) throws Exception {
        assertion.check(label + "-matching-oriented-preview-size", before.getWidth() == width
                && before.getHeight() == height && after.getWidth() == width && after.getHeight() == height);
        assertion.check(label + "-real-partial-painted-mask", zeroMaskPixels > width * height / 2
                && coveredPixels > 64);
        int[] baseline = new int[width * height], actual = new int[width * height];
        before.getPixels(baseline, 0, width, 0, 0, width, height);
        after.getPixels(actual, 0, width, 0, 0, width, height);
        int outsideErrors = 0, insideChanged = 0;
        for (int i = 0; i < baseline.length; i++) {
            if (baseline[i] != actual[i]) {
                if (outside[i]) outsideErrors++;
                else insideChanged++;
            }
        }
        assertion.check(label + "-zero-mask-packed-ARGB-exact", outsideErrors == 0);
        if (requireVisibleChange) assertion.check(label + "-painted-pixels-really-change", insideChanged > 0);
        return new JSONObject().put("case", label).put("width", width).put("height", height)
                .put("zeroMaskPixels", zeroMaskPixels).put("coveredPixels", coveredPixels)
                .put("zeroMaskDifferentPixels", outsideErrors).put("paintedDifferentPixels", insideChanged);
    }

    static double weight(Object region, int width, int height, double x, double y) throws Exception {
        Method compile = region.getClass().getMethod("compileBrush", int.class, int.class);
        compile.setAccessible(true);
        Object mask = compile.invoke(region, width, height);
        Method sample = mask.getClass().getMethod("weight", double.class, double.class);
        sample.setAccessible(true);
        return ((Number) sample.invoke(mask, x, y)).doubleValue();
    }
}
