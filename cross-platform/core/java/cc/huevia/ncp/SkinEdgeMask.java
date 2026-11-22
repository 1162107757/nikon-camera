package cc.huevia.ncp;

import java.io.IOException;
import java.io.InterruptedIOException;
import java.util.function.BooleanSupplier;

/** Upsamples automatic exposed-skin coverage along photo edges instead of across them. */
final class SkinEdgeMask {
    private static final int SIZE = PhotoPortrait.BodySkinMask.SIZE;
    private static final int STRIDE = SIZE + 1;
    private final byte[] coverage;
    private final int[] skin = new int[STRIDE * STRIDE];
    private final int[] outside = new int[STRIDE * STRIDE];

    SkinEdgeMask(PhotoPortrait.BodySkinMask mask, SpatialPreviewFilter.Pixels pixels, int exif,
                 BooleanSupplier cancel) throws IOException {
        coverage = mask.copyCoverage();
        int[] guide = new int[coverage.length];
        int width = pixels.width(), height = pixels.height();
        int[] row = new int[width];
        int loaded = -1;
        // Sample in raw row order, then place each sample in the mask's oriented coordinate frame.
        for (int y = 0; y < SIZE; y++) {
            if (Thread.currentThread().isInterrupted() || cancel != null && cancel.getAsBoolean()) {
                throw new InterruptedIOException("皮肤选区处理已取消。");
            }
            int sourceY = (2 * y + 1) * height / (2 * SIZE);
            if (sourceY != loaded) {
                pixels.read(row, sourceY, 1);
                loaded = sourceY;
            }
            double ny = (y + .5) / SIZE;
            for (int x = 0; x < SIZE; x++) {
                double nx = (x + .5) / SIZE;
                int ox = (int) (LocalEditsPreviewProfile.orientedX(nx, ny, exif) * SIZE);
                int oy = (int) (LocalEditsPreviewProfile.orientedY(nx, ny, exif) * SIZE);
                guide[oy * SIZE + ox] = row[(2 * x + 1) * width / (2 * SIZE)];
            }
        }
        // Skip uncertain samples and the grid points next to a mask transition. A guide sampled
        // right at a contour can pick up the other side when the grid lands between photo pixels.
        byte[] reliable = new byte[coverage.length];
        for (int y = 0; y < SIZE; y++) {
            for (int x = 0; x < SIZE; x++) {
                int i = y * SIZE + x;
                byte side = side(coverage[i] & 255);
                if (side != 0 && (guide[i] >>> 24) >= 128 && side == side(at(x - 1, y))
                        && side == side(at(x + 1, y)) && side == side(at(x, y - 1))
                        && side == side(at(x, y + 1))) reliable[i] = side;
            }
        }
        for (int y = -1; y < SIZE; y++) {
            for (int x = -1; x < SIZE; x++) {
                int a = at(x, y), b = at(x + 1, y), c = at(x, y + 1), d = at(x + 1, y + 1);
                if (a == b && a == c && a == d) continue;
                int cell = (y + 1) * STRIDE + x + 1;
                int nearestSkin = Integer.MAX_VALUE, nearestOutside = Integer.MAX_VALUE;
                for (int py = Math.max(0, y - 2); py <= Math.min(SIZE - 1, y + 3); py++) {
                    for (int px = Math.max(0, x - 2); px <= Math.min(SIZE - 1, x + 3); px++) {
                        int i = py * SIZE + px;
                        int dx = 2 * (px - x) - 1, dy = 2 * (py - y) - 1;
                        int distance = dx * dx + dy * dy;
                        if (reliable[i] == 1 && distance < nearestSkin) {
                            nearestSkin = distance;
                            skin[cell] = guide[i];
                        } else if (reliable[i] == -1 && distance < nearestOutside) {
                            nearestOutside = distance;
                            outside[cell] = guide[i];
                        }
                    }
                }
            }
        }
    }

    double weight(int argb, double nx, double ny) {
        double gx = nx * SIZE - .5, gy = ny * SIZE - .5;
        int ix = (int) Math.floor(gx), iy = (int) Math.floor(gy);
        int a = at(ix, iy), b = at(ix + 1, iy), c = at(ix, iy + 1), d = at(ix + 1, iy + 1);
        if (a == b && a == c && a == d) return a / 255.0;

        double tx = gx - ix, ty = gy - iy;
        double base = ((a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty) / 255;
        if (base <= 0 || base >= 1) return base;
        // Thin features and low-contrast boundaries keep a soft selection even without two guides.
        double feather = base * (1 - .35 * (1 - base));
        int cell = (iy + 1) * STRIDE + ix + 1, fg = skin[cell], bg = outside[cell];
        if (fg == 0 || bg == 0) return feather;
        int contrast = distanceSquared(fg, bg);
        if (contrast <= 3 * 12 * 12) return feather;
        int dSkin = distanceSquared(argb, fg), dOutside = distanceSquared(argb, bg);
        double strength = smooth((contrast - 3 * 12 * 12) / (3.0 * (24 * 24 - 12 * 12)))
                * (1 - smooth(Math.min(dSkin, dOutside) / (double) contrast));
        double position = dOutside / (double) (dSkin + dOutside);
        double guided = smooth((position - .15) / .70) * Math.min(1, base / .25);
        return feather + strength * (guided - feather);
    }

    private int at(int x, int y) {
        return coverage[clamp(y) * SIZE + clamp(x)] & 255;
    }

    private static byte side(int weight) {
        return weight >= 192 ? (byte) 1 : weight <= 32 ? (byte) -1 : 0;
    }

    private static int clamp(int coordinate) {
        return Math.max(0, Math.min(SIZE - 1, coordinate));
    }

    private static double smooth(double t) {
        double x = Math.max(0, Math.min(1, t));
        return x * x * (3 - 2 * x);
    }

    private static int distanceSquared(int pixel, int sample) {
        int dr = ((pixel >>> 16) & 255) - ((sample >>> 16) & 255);
        int dg = ((pixel >>> 8) & 255) - ((sample >>> 8) & 255);
        int db = (pixel & 255) - (sample & 255);
        return dr * dr + dg * dg + db * db;
    }
}
