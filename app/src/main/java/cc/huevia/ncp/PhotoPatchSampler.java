package cc.huevia.ncp;

import java.io.*;
import java.util.*;
import java.util.function.BooleanSupplier;

/** Deterministic local texture search; freezes a real donor translation in the existing recipe. */
public final class PhotoPatchSampler {
    private PhotoPatchSampler() {}

    /** Keep the painted core opaque; blend in a soft exterior instead of leaving blemish halos. */
    public static PhotoPortrait.Stroke automaticStroke(double[] points,double coreRadius){
        if(!Double.isFinite(coreRadius)||coreRadius<.001||coreRadius>.1)throw new IllegalArgumentException("修补画笔范围无效。");
        return new PhotoPortrait.Stroke(points,coreRadius/.65,.35,false);
    }

    /** The caller supplies an immutable, EXIF-oriented preview, at most 384 pixels per side. */
    public static PhotoPatch choose(int[] pixels, int width, int height, AdjustmentRegion region,
                                    BooleanSupplier cancelled) throws IOException {
        if (pixels == null || width < 2 || height < 2 || width > 384 || height > 384
                || pixels.length != width * height || region == null || !region.hasSelection())
            throw new IllegalArgumentException("消除照片或涂抹区域无效。");
        check(cancelled);
        AdjustmentRegion.Brush brush = region.compileBrush(width, height);
        boolean[] selected = new boolean[pixels.length], forbidden = new boolean[pixels.length];
        ArrayList<Integer> target = new ArrayList<>(), context = new ArrayList<>();
        int left = width, top = height, right = -1, bottom = -1;
        for (int y = 0; y < height; y++) {
            check(cancelled);
            for (int x = 0; x < width; x++) {
                int at = y * width + x;
                if (brush.weight((x + .5) / width, (y + .5) / height) <= .001) continue;
                selected[at] = true; target.add(at);
                left = Math.min(left, x); right = Math.max(right, x);
                top = Math.min(top, y); bottom = Math.max(bottom, y);
            }
        }
        if (target.isEmpty() || target.size() > pixels.length * .4)
            throw new IOException("涂抹范围较大，请分小块消除。");
        // Keep donor pixels away from the entire marked region, including a one-pixel safety rim.
        for (int at : target) {
            int x = at % width, y = at / width;
            for (int yy = Math.max(0, y - 1); yy <= Math.min(height - 1, y + 1); yy++)
                for (int xx = Math.max(0, x - 1); xx <= Math.min(width - 1, x + 1); xx++)
                    forbidden[yy * width + xx] = true;
        }
        for (int y = Math.max(0, top - 4); y <= Math.min(height - 1, bottom + 4); y++) {
            check(cancelled);
            for (int x = Math.max(0, left - 4); x <= Math.min(width - 1, right + 4); x++) {
                int at = y * width + x;
                if (forbidden[at] || (pixels[at] >>> 24) < 128) continue;
                boolean near = false;
                for (int yy = Math.max(0, y - 3); yy <= Math.min(height - 1, y + 3) && !near; yy++)
                    for (int xx = Math.max(0, x - 3); xx <= Math.min(width - 1, x + 3); xx++)
                        if (selected[yy * width + xx]) { near = true; break; }
                if (near) context.add(at);
            }
        }
        if (context.size() < 4) throw new IOException("附近没有足够的干净背景，请缩小涂抹范围。");
        int[] ring = new int[Math.min(192, context.size())];
        for (int i = 0; i < ring.length; i++) ring[i] = context.get(i * context.size() / ring.length);
        Search search = new Search(pixels, width, height, target, forbidden, ring, cancelled);
        int minX = (int)Math.ceil(-brush.left * width), maxX = (int)Math.floor((1 - brush.right) * width);
        int minY = (int)Math.ceil(-brush.top * height), maxY = (int)Math.floor((1 - brush.bottom) * height);
        int step = Math.max(1, Math.min(width, height) / 40);
        for (int dy = minY; dy <= maxY; dy += step) {
            check(cancelled);
            for (int dx = minX; dx <= maxX; dx += step) search.consider(dx, dy);
        }
        // Include both axes and the exact image boundaries, which the coarse lattice may skip.
        for (int dx = minX; dx <= maxX; dx += step) {
            search.consider(dx, 0); search.consider(dx, minY); search.consider(dx, maxY);
        }
        for (int dy = minY; dy <= maxY; dy += step) {
            search.consider(0, dy); search.consider(minX, dy); search.consider(maxX, dy);
        }
        if (Double.isFinite(search.best)) {
            int bx = search.dx, by = search.dy;
            for (int dy = Math.max(minY, by - step); dy <= Math.min(maxY, by + step); dy++)
                for (int dx = Math.max(minX, bx - step); dx <= Math.min(maxX, bx + step); dx++) search.consider(dx, dy);
        }
        check(cancelled);
        if (!Double.isFinite(search.best)) throw new IOException("没有找到合适的干净背景，请缩小范围后重试。");
        return PhotoPatch.create(region).sample(search.dx / (double) width, search.dy / (double) height);
    }

    private static final class Search {
        final int[] pixels, ring;
        final int w, h;
        final List<Integer> target;
        final boolean[] forbidden;
        final BooleanSupplier cancel;
        double best = Double.POSITIVE_INFINITY;
        int dx, dy, attempts;
        Search(int[] p, int w, int h, List<Integer> t, boolean[] f, int[] r, BooleanSupplier c) {
            pixels = p; this.w = w; this.h = h; target = t; forbidden = f; ring = r; cancel = c;
        }
        void consider(int x, int y) throws IOException {
            if ((attempts++ & 31) == 0) check(cancel);
            if (x == 0 && y == 0) return;
            double error = 0; int count = 0;
            // Match unselected surroundings, never the blemish being removed.
            for (int at : ring) {
                int xx = at % w + x, yy = at / w + y;
                if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
                int other = yy * w + xx;
                if (forbidden[other] || (pixels[other] >>> 24) < 128) return;
                int a = pixels[at], b = pixels[other];
                for (int shift = 0; shift <= 16; shift += 8) {
                    int delta = ((a >>> shift) & 255) - ((b >>> shift) & 255);
                    error += delta * delta;
                }
                count++;
            }
            if (count < Math.max(4, ring.length * 3 / 5)) return;
            double score = error / (3 * count) + .035 * (x * x + y * y) / (w * w + h * h);
            if (score >= best) return;
            // Validate every covered donor, not just context samples or the bounding rectangle.
            for (int i = 0; i < target.size(); i++) {
                if ((i & 511) == 0) check(cancel);
                int at = target.get(i), xx = at % w + x, yy = at / w + y;
                if (xx < 0 || yy < 0 || xx >= w || yy >= h) return;
                int other = yy * w + xx;
                if (forbidden[other] || (pixels[other] >>> 24) < (pixels[at] >>> 24)) return;
            }
            best = score; dx = x; dy = y;
        }
    }
    private static void check(BooleanSupplier cancelled) throws InterruptedIOException {
        if (Thread.currentThread().isInterrupted() || cancelled != null && cancelled.getAsBoolean())
            throw new InterruptedIOException("消除已取消。");
    }
}
