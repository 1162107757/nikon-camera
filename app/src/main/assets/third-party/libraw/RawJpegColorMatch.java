package cc.huevia.ncp;

import java.io.IOException;
import java.io.InterruptedIOException;
import java.util.ArrayList;
import java.util.List;
import java.util.function.BooleanSupplier;

/** Conservative, same-frame JPEG color approximation. Never supplies spatial image detail. */
public final class RawJpegColorMatch {
    public static final String MODEL = "same-raw-jpeg-crop-ridge-cubic-lut17-white-v2";
    public static final int GRID = 17;
    private static final int FEATURES = 12;
    private RawJpegColorMatch() {}

    public static final class Fit {
        public final boolean accepted;
        public final String reason;
        public final int samples, orientation;
        public final double referenceScale, correlation, beforeError, afterError;
        private final float[] table;
        private Fit(boolean accepted, String reason, int samples, int orientation,
                double referenceScale, double correlation, double beforeError, double afterError, float[] table) {
            this.accepted = accepted; this.reason = reason; this.samples = samples; this.orientation = orientation;
            this.referenceScale = referenceScale; this.correlation = correlation; this.beforeError = beforeError; this.afterError = afterError; this.table = table;
        }
        public float[] table() { return table.clone(); }
        public int applyArgb(int argb) {
            if (!accepted || table.length == 0) return argb;
            double r = ((argb >>> 16) & 255) / 255.0, g = ((argb >>> 8) & 255) / 255.0, b = (argb & 255) / 255.0;
            return argb & 0xff000000 | channel(lookup(table, r, g, b, 0)) << 16
                    | channel(lookup(table, r, g, b, 1)) << 8 | channel(lookup(table, r, g, b, 2));
        }
    }
    public static Fit unavailable(String reason) { return new Fit(false, reason, 0, 0, 1, 0, 0, 0, new float[0]); }

    /** Small sRGB analysis images only. Full RAW resolution is processed separately with the resulting LUT. */
    public static Fit fit(int[] source, int width, int height, int[] reference, int refWidth, int refHeight,
            BooleanSupplier cancel) throws IOException {
        validate(source, width, height); validate(reference, refWidth, refHeight); check(cancel);
        if (Math.min(width, height) < 48 || Math.min(refWidth, refHeight) < 48) return unavailable("REFERENCE_TOO_SMALL");
        int step = Math.max(1, (int) Math.ceil(Math.sqrt(width * (double) height / 4096)));
        double best = -2, scale = 1; int orientation = 0;
        for (int transform = 0; transform < 8; transform++) {
            check(cancel); double aspect = (transform % 2 == 1 ? refHeight / (double) refWidth : refWidth / (double) refHeight);
            if (Math.abs(Math.log(aspect / (width / (double) height))) > .08) continue;
            // Camera JPEGs may include a modest central crop (e.g. distortion correction).
            // This registration is only for color sampling; output RAW pixels are never cropped.
            for (int candidate = 90; candidate <= 115; candidate += 5) {
                check(cancel);double zoom=candidate/100.0;
                double score = correlation(source, width, height, reference, refWidth, refHeight, transform, zoom, step, cancel);
                if (score > best) { best = score; orientation = transform; scale = zoom; }
            }
        }
        if(best < -1)return unavailable("UNRELIABLE_ALIGNMENT");
        int center=(int)Math.round(scale*100);
        for(int candidate=Math.max(90,center-4);candidate<=Math.min(115,center+4);candidate++) {
            check(cancel);double zoom=candidate/100.0;
            double score=correlation(source,width,height,reference,refWidth,refHeight,orientation,zoom,step,cancel);
            if(score>best){best=score;scale=zoom;}
        }
        if (best < .90) return new Fit(false, "UNRELIABLE_ALIGNMENT", 0, orientation, scale, Math.max(-1, best), 0, 0, new float[0]);
        List<double[]> training = new ArrayList<>(), validation = new ArrayList<>(), whiteValidation = new ArrayList<>();
        for (int y = 3, iy = 0; y < height - 3; y += step, iy++) {
            check(cancel);
            for (int x = 3, ix = 0; x < width - 3; x += step, ix++) {
                double[] s = sample(source, width, height, (x + .5) / width, (y + .5) / height);
                double[] t = reference(reference, refWidth, refHeight, width, height, x, y, orientation, scale);
                if(t==null)continue;
                // A neutral clipped JPEG highlight still tells us its expected color.
                // Discarding it lets a good midtone fit turn white into magenta.
                boolean white = Math.min(t[0], Math.min(t[1], t[2])) >= .985
                        && Math.max(t[0], Math.max(t[1], t[2])) - Math.min(t[0], Math.min(t[1], t[2])) <= .015;
                boolean usable = true;
                for (int c = 0; c < 3; c++) usable &= s[c] > .02 && (white || s[c] < .97)
                        && (white || (t[c] > .008 && t[c] < .992));
                if (!usable) continue;
                double[] pair = {s[0], s[1], s[2], t[0], t[1], t[2]};
                if ((ix + iy * 3) % 5 == 0) { validation.add(pair); if (white) whiteValidation.add(pair); }
                else training.add(pair);
            }
        }
        int count = training.size() + validation.size();
        if (training.size() < 192 || validation.size() < 64)
            return new Fit(false, "INSUFFICIENT_SAMPLES", count, orientation, scale, best, 0, 0, new float[0]);
        double before = error(validation, null);
        if (before < .008) return new Fit(true, "ALREADY_CLOSE", count, orientation, scale, best, before, before, new float[0]);
        double[][] normal = new double[FEATURES][FEATURES + 3];
        for (int p = 0; p < training.size(); p++) {
            if ((p & 63) == 0) check(cancel);
            double[] pair = training.get(p), f = features(pair[0], pair[1], pair[2]);
            for (int i = 0; i < FEATURES; i++) {
                for (int j = 0; j < FEATURES; j++) normal[i][j] += f[i] * f[j] / training.size();
                for (int c = 0; c < 3; c++) normal[i][FEATURES + c] += f[i] * (pair[c + 3] - pair[c]) / training.size();
            }
        }
        // Fit a bounded departure from identity. Ridge regularization stabilizes sparse scene colors.
        for (int i = 0; i < FEATURES; i++) normal[i][i] += .0002;
        double[][] coefficients = solve(normal);
        float[] table = new float[GRID * GRID * GRID * 3];
        for (int r = 0; r < GRID; r++) {
            check(cancel);
            for (int g = 0; g < GRID; g++) for (int b = 0; b < GRID; b++) {
                double[] rgb = {r / 16.0, g / 16.0, b / 16.0}; int index = ((r * GRID + g) * GRID + b) * 3;
                double[] f = features(rgb[0],rgb[1],rgb[2]);
                for (int c = 0; c < 3; c++) {
                    double value = rgb[c]; for (int i = 0; i < FEATURES; i++) value += f[i] * coefficients[i][c];
                    if (!Double.isFinite(value)) return unavailable("UNRELIABLE_FIT");
                    table[index + c] = (float) Math.max(0, Math.min(1, value));
                }
            }
        }
        double after = error(validation, table); check(cancel);
        // Most held-out pixels can be midtones: check highlight safety separately.
        if (!safeHighlights(table) || (!whiteValidation.isEmpty() && error(whiteValidation, table) > .04))
            return new Fit(false, "UNSAFE_HIGHLIGHTS", count, orientation, scale, best, before, after, new float[0]);
        // Held-out spatial samples, never the training residual, decide whether any correction is applied.
        boolean accepted = after <= before * .92 && after <= .10;
        return new Fit(accepted, accepted ? "MATCHED" : "UNRELIABLE_FIT", count, orientation, scale, best, before, after,
                accepted ? table : new float[0]);
    }

    private static void validate(int[] image, int width, int height) {
        if (image == null || width < 1 || height < 1 || (long) width * height > 1_048_576
                || (long) width * height != image.length) throw new IllegalArgumentException("Invalid color analysis image");
    }
    private static double[] features(double r, double g, double b) {
        // Zero correction at display white, enforced during fitting rather than
        // repainting bright pixels after the transform.
        return new double[] {r-1, g-1, b-1, r*r-1, g*g-1, b*b-1, r*g-1, r*b-1, g*b-1, r*r*r-1, g*g*g-1, b*b*b-1};
    }
    private static boolean safeHighlights(float[] table) {
        double brightest = 0;
        for (int n = 128; n <= 255; n++) {
            double v = n / 255.0;
            double r=lookup(table,v,v,v,0),g=lookup(table,v,v,v,1),b=lookup(table,v,v,v,2);
            double light = .2126*r + .7152*g + .0722*b;
            if (light + .01 < brightest) return false;
            if (n >= 220 && Math.min(r,b) - g > .025) return false;
            brightest = Math.max(brightest,light);
        }
        return true;
    }
    private static double[][] solve(double[][] a) throws IOException {
        for (int i = 0; i < FEATURES; i++) {
            int pivot = i; for (int j = i + 1; j < FEATURES; j++) if (Math.abs(a[j][i]) > Math.abs(a[pivot][i])) pivot = j;
            if (Math.abs(a[pivot][i]) < 1e-12) throw new IOException("相机色彩拟合不稳定。");
            double[] swap = a[i]; a[i] = a[pivot]; a[pivot] = swap;
            double scale = a[i][i]; for (int j = i; j < FEATURES + 3; j++) a[i][j] /= scale;
            for (int row = 0; row < FEATURES; row++) if (row != i) {
                double factor = a[row][i]; for (int j = i; j < FEATURES + 3; j++) a[row][j] -= factor * a[i][j];
            }
        }
        double[][] result = new double[FEATURES][3];
        for (int i = 0; i < FEATURES; i++) System.arraycopy(a[i], FEATURES, result[i], 0, 3); return result;
    }
    private static double error(List<double[]> pairs, float[] table) {
        double sum = 0;
        for (double[] p : pairs) for (int c = 0; c < 3; c++) {
            double delta = (table == null ? p[c] : lookup(table, p[0], p[1], p[2], c)) - p[c + 3]; sum += delta * delta;
        }
        return Math.sqrt(sum / (pairs.size() * 3.0));
    }
    private static double lookup(float[] table, double r, double g, double b, int c) {
        double[] v = {r * 16, g * 16, b * 16}; int[] base = new int[3]; double[] f = new double[3];
        for (int i = 0; i < 3; i++) { base[i] = Math.min(15, Math.max(0, (int) v[i])); f[i] = v[i] - base[i]; }
        double result = 0;
        for (int dr = 0; dr <= 1; dr++) for (int dg = 0; dg <= 1; dg++) for (int db = 0; db <= 1; db++)
            result += table[(((base[0] + dr) * GRID + base[1] + dg) * GRID + base[2] + db) * 3 + c]
                    * (dr == 0 ? 1 - f[0] : f[0]) * (dg == 0 ? 1 - f[1] : f[1]) * (db == 0 ? 1 - f[2] : f[2]);
        return result;
    }
    private static double correlation(int[] src, int w, int h, int[] ref, int rw, int rh, int transform, double scale, int step, BooleanSupplier cancel) throws InterruptedIOException {
        double n = 0, sx = 0, sy = 0, xx = 0, yy = 0, xy = 0;
        // Same central area for every scale prevents a tiny overlap from winning registration.
        for (int y = Math.max(3,h/10); y < Math.min(h-3,h*9/10); y += step) {
          check(cancel);for (int x = Math.max(3,w/10); x < Math.min(w-3,w*9/10); x += step) {
            double[] s = sample(src, w, h, (x + .5) / w, (y + .5) / h), t = reference(ref, rw, rh, w, h, x, y, transform, scale);
            if(t==null)continue;
            double a = .2126*s[0] + .7152*s[1] + .0722*s[2], b = .2126*t[0] + .7152*t[1] + .0722*t[2];
            n++; sx += a; sy += b; xx += a*a; yy += b*b; xy += a*b;
          }
        }
        double denominator = Math.sqrt(Math.max(0, (n*xx-sx*sx) * (n*yy-sy*sy)));
        return denominator < 1e-9 ? -1 : Math.max(-1, Math.min(1, (n*xy-sx*sy) / denominator));
    }
    private static double[] reference(int[] ref, int rw, int rh, int w, int h, int x, int y, int transform, double scale) {
        double u = (x + .5) / w, v = (y + .5) / h;
        double aspect = transform % 2 == 1 ? rh / (double) rw : rw / (double) rh, sourceAspect = w / (double) h;
        if (aspect > sourceAspect) u = .5 + (u - .5) * sourceAspect / aspect;
        else v = .5 + (v - .5) * aspect / sourceAspect;
        u=.5+(u-.5)*scale;v=.5+(v-.5)*scale;
        if (transform >= 4) u = 1 - u;
        double ru = u, rv = v;
        switch (transform % 4) { case 1: ru=v; rv=1-u; break; case 2: ru=1-u; rv=1-v; break; case 3: ru=1-v; rv=u; break; }
        if(ru<1.5/rw||rv<1.5/rh||ru>1-1.5/rw||rv>1-1.5/rh)return null;
        return sample(ref, rw, rh, ru, rv);
    }
    private static double[] sample(int[] image, int w, int h, double u, double v) {
        int x = Math.max(1, Math.min(w - 2, (int) (u*w))), y = Math.max(1, Math.min(h - 2, (int) (v*h)));
        double[] result = new double[3];
        for (int dy = -1; dy <= 1; dy++) for (int dx = -1; dx <= 1; dx++) {
            int pixel = image[(y+dy)*w+x+dx]; result[0] += (pixel >>> 16) & 255; result[1] += (pixel >>> 8) & 255; result[2] += pixel & 255;
        }
        for (int c = 0; c < 3; c++) result[c] /= 2295.0; return result;
    }
    private static int channel(double value) { return Math.max(0, Math.min(255, (int) Math.round(value * 255))); }
    private static void check(BooleanSupplier cancel) throws InterruptedIOException {
        if (Thread.currentThread().isInterrupted() || cancel != null && cancel.getAsBoolean()) throw new InterruptedIOException("RAW 色彩还原已取消。");
    }
}
