package cc.huevia.ncp;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Random;

/** Compares indexed mask pixels with an independent exhaustive segment-distance oracle. */
public final class PortraitMaskIndexTest {
    private static final int WIDTH = 4000, HEIGHT = 3000, PIXEL = 0xffff0000;
    public static void main(String[] args) {
        double[] points = new double[1024];
        for (int i = 0; i < 512; i++) { points[i * 2] = .05 + .9 * i / 511; points[i * 2 + 1] = .5 + .3 * Math.sin(i * .047); }
        PhotoPortrait.Stroke add = new PhotoPortrait.Stroke(points, .016, .75, false);
        PhotoPortrait.Stroke erase = new PhotoPortrait.Stroke(new double[]{.28, .1, .28, .9, .7, .9}, .04, .6, true);
        PhotoPortrait.Stroke readd = new PhotoPortrait.Stroke(new double[]{.28, .5}, .015, 0, false);
        List<PhotoPortrait.Stroke> strokes = Arrays.asList(add, erase, readd);
        PhotoPortrait.Face face = face(strokes);
        PortraitPreviewFilter.Mask mask = PortraitPreviewFilter.mask(face, WIDTH, HEIGHT);
        Random random = new Random(81317);
        int checked = 0;
        for (int i = 0; i < 12000; i++) {
            double x = random.nextDouble(), y = random.nextDouble();
            same(mask.weight(PIXEL, x, y), exhaustive(strokes, x, y)); checked++;
        }
        for (int y = 0; y <= 16; y++) for (int x = 0; x <= 16; x++) { same(mask.weight(PIXEL, x / 16.0, y / 16.0), exhaustive(strokes, x / 16.0, y / 16.0)); checked++; }
        // A radius covering the entire image must keep every applicable segment in every cell.
        PhotoPortrait.Stroke wide = new PhotoPortrait.Stroke(points, 1, 1, false);
        PortraitPreviewFilter.Mask wideMask = PortraitPreviewFilter.mask(face(Collections.singletonList(wide)), WIDTH, HEIGHT);
        for (int i = 0; i < 200; i++) { double x = random.nextDouble(), y = random.nextDouble(); same(wideMask.weight(PIXEL, x, y), exhaustive(Collections.singletonList(wide), x, y)); checked++; }
        final int count = 150000;
        double[] xs = new double[count], ys = new double[count];
        for (int i = 0; i < count; i++) { xs[i] = random.nextDouble(); ys[i] = random.nextDouble(); }
        PortraitPreviewFilter.Mask single = PortraitPreviewFilter.mask(face(Collections.singletonList(add)), WIDTH, HEIGHT);
        double indexedSum = 0, referenceSum = 0;
        long start = System.nanoTime();
        for (int i = 0; i < count; i++) indexedSum += single.weight(PIXEL, xs[i], ys[i]);
        long indexed = System.nanoTime() - start;
        start = System.nanoTime();
        for (int i = 0; i < count; i++) referenceSum += exhaustiveSingle(points, add.radius, add.feather, xs[i], ys[i]);
        long reference = System.nanoTime() - start;
        if (Math.abs(indexedSum - referenceSum) > 1e-8) throw new AssertionError("benchmark mask pixels differ");
        System.out.printf("Portrait mask index: %d pixel comparisons passed; 512-point stroke %,d samples indexed %.1fms / exhaustive %.1fms (%.2fx).%n", checked, count, indexed / 1e6, reference / 1e6, reference / (double) indexed);
    }
    private static PhotoPortrait.Face face(List<PhotoPortrait.Stroke> strokes) {
        // The deliberately different green face sample makes automatic skin weight zero for PIXEL.
        return new PhotoPortrait.Face(.5, .5, .49, .49, 0, 0, 255, 0, true, PhotoPortrait.Settings.NONE, strokes);
    }
    private static double exhaustive(List<PhotoPortrait.Stroke> strokes, double nx, double ny) {
        double result = 0;
        for (PhotoPortrait.Stroke stroke : strokes) {
            double weight = exhaustiveSingle(stroke.points(), stroke.radius, stroke.feather, nx, ny);
            result = stroke.erase ? result * (1 - weight) : result + (1 - result) * weight;
        }
        return result;
    }
    private static double exhaustiveSingle(double[] points, double radius, double feather, double nx, double ny) {
            double distance = Double.POSITIVE_INFINITY, x = nx * WIDTH, y = ny * HEIGHT;
            for (int i = 0; i < points.length; i += 2) {
                int j = Math.min(i + 2, points.length - 2);
                double ax = points[i] * WIDTH, ay = points[i + 1] * HEIGHT, vx = points[j] * WIDTH - ax, vy = points[j + 1] * HEIGHT - ay;
                double length = vx * vx + vy * vy, t = length == 0 ? 0 : Math.max(0, Math.min(1, ((x - ax) * vx + (y - ay) * vy) / length));
                double dx = x - ax - t * vx, dy = y - ay - t * vy;
                distance = Math.min(distance, dx * dx + dy * dy);
            }
            double d = Math.sqrt(distance) / (radius * Math.min(WIDTH, HEIGHT)), weight;
            if (d >= 1) weight = 0;
            else if (d <= 1 - feather || feather == 0) weight = 1;
            else { double value = Math.max(0, Math.min(1, (d - (1 - feather)) / feather)); weight = 1 - value * value * (3 - 2 * value); }
            return weight;
    }
    private static void same(double actual, double expected) { if (Math.abs(actual - expected) > 1e-12) throw new AssertionError("index changed mask: " + actual + " != " + expected); }
}
