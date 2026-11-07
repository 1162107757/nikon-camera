package cc.huevia.album;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.ColorMatrix;
import android.graphics.ColorMatrixColorFilter;
import android.graphics.Paint;
import android.graphics.PointF;
import android.media.FaceDetector;
import cc.huevia.ncp.PhotoPortrait;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.function.BooleanSupplier;

/** Offline face proposals and sampled patch references; no identity recognition or network. */
public final class PhotoPortraitDetection {
    private PhotoPortraitDetection() {}

    /** Input is EXIF-oriented, before composition. Detection uses at most 1280 px per side. */
    public static List<PhotoPortrait.Face> detect(Bitmap image, BooleanSupplier cancel) throws IOException {
        if (image == null || cancel == null || image.isRecycled()) throw new IllegalArgumentException("人像图片无效。");
        check(cancel);
        double scale = Math.min(1, 1280.0 / Math.max(image.getWidth(), image.getHeight()));
        int width = (int) Math.floor(image.getWidth() * scale);
        width -= width & 1;
        if (width < 2) return Collections.emptyList();
        int height = Math.max(2, Math.min(1280, (int) Math.round(image.getHeight() * width / (double) image.getWidth())));
        Bitmap grayscale = null, input = null;
        try {
            // Localize faces using luminance, before RGB565 quantization; retain original
            // colour for the independently sampled skin mask and all image processing.
            grayscale = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
            ColorMatrix luminance = new ColorMatrix(); luminance.setSaturation(0);
            Paint detectorPaint = new Paint(Paint.FILTER_BITMAP_FLAG);
            detectorPaint.setColorFilter(new ColorMatrixColorFilter(luminance));
            new Canvas(grayscale).drawBitmap(image, null, new android.graphics.Rect(0, 0, width, height), detectorPaint);
            check(cancel);
            input = Bitmap.createBitmap(width, height, Bitmap.Config.RGB_565);
            new Canvas(input).drawBitmap(grayscale, 0, 0, new Paint(Paint.FILTER_BITMAP_FLAG));
            check(cancel);
            FaceDetector.Face[] found = new FaceDetector.Face[10];
            int count = new FaceDetector(width, height, found.length).findFaces(input, found);
            check(cancel);
            ArrayList<PhotoPortrait.Face> proposals = new ArrayList<>();
            ArrayList<double[]> primaryEyes = new ArrayList<>();
            for (int i = 0; i < count; i++) {
                check(cancel);
                FaceDetector.Face face = found[i];
                if (face == null) continue;
                float confidence = face.confidence();
                if (!Float.isFinite(confidence) || confidence < .35f) continue;
                float distance = face.eyesDistance();
                if (!Float.isFinite(distance) || distance < 5) continue;
                PointF eyes = new PointF(); face.getMidPoint(eyes);
                if (!Float.isFinite(eyes.x) || !Float.isFinite(eyes.y)) continue;
                double rawRoll = face.pose(FaceDetector.Face.EULER_Z);
                if (!Double.isFinite(rawRoll)) continue;
                double roll = rawRoll;
                roll = Math.max(-60, Math.min(60, roll));
                double angle = Math.toRadians(roll);
                double cx = (eyes.x - Math.sin(angle) * distance * .55) / width;
                double cy = (eyes.y + Math.cos(angle) * distance * .55) / height;
                if (cx < 0 || cx > 1 || cy < 0 || cy > 1) continue;
                double rx = Math.max(.005, Math.min(.5, .95 * distance / width));
                double ry = Math.max(.005, Math.min(.5, 1.35 * distance / height));
                // Weak proposals occasionally place both eyes on bright background objects.
                // Reject only a gross eye/cheek structural contradiction, not a skin colour.
                if (confidence < .65f && contradictoryEyeStructure(image, cx, cy, rx, ry, roll)) continue;
                int colour = skinSample(image, cx, cy, rx, ry, roll);
                proposals.add(new PhotoPortrait.Face(cx, cy, rx, ry, roll, (colour >>> 16) & 255,
                        (colour >>> 8) & 255, colour & 255, true, PhotoPortrait.Settings.NONE, Collections.emptyList()));
                primaryEyes.add(new double[]{eyes.x, eyes.y, distance, rawRoll, confidence});
            }
            if (proposals.isEmpty()) return Collections.emptyList();
            check(cancel);
            // A background texture can survive two similar resizes. Require it to also
            // localize after reflection, with the eye position and raw roll mapped back.
            // All views originate in ARGB luminance, not an already quantized RGB565.
            boolean[] mirrored = consensusMatches(primaryEyes, eyeAnchors(grayscale, width, true, cancel), cancel);
            boolean[] resized = consensusMatches(primaryEyes, eyeAnchors(grayscale, (int) Math.floor(width * .85), false, cancel), cancel);
            boolean needsAlternative = false;
            for (int i = 0; i < proposals.size(); i++) if (mirrored[i] && !resized[i]) needsAlternative = true;
            boolean[] alternative = needsAlternative
                    ? consensusMatches(primaryEyes, eyeAnchors(grayscale, (int) Math.floor(width * .70), false, cancel), cancel)
                    : new boolean[proposals.size()];
            ArrayList<Integer> accepted = new ArrayList<>();
            for (int i = 0; i < proposals.size(); i++) if (mirrored[i] && (resized[i] || alternative[i])) accepted.add(i);
            accepted.sort((a, b) -> Double.compare(primaryEyes.get(b)[4], primaryEyes.get(a)[4]));
            ArrayList<Integer> retained = new ArrayList<>();
            for (int candidate : accepted) {
                check(cancel);boolean repeated = false;
                for (int previous : retained) if (duplicate(primaryEyes.get(candidate), primaryEyes.get(previous))) { repeated = true; break; }
                if (!repeated) retained.add(candidate);
            }
            ArrayList<PhotoPortrait.Face> output = new ArrayList<>();
            for (int i : retained) output.add(proposals.get(i));
            output.sort(Comparator.comparingDouble(f -> f.cx));
            return Collections.unmodifiableList(output);
        } catch (RuntimeException | LinkageError | OutOfMemoryError failure) {
            throw new IOException("自动选脸暂不可用，请手动添加人脸。", failure);
        } finally { if (input != null) input.recycle(); if (grayscale != null) grayscale.recycle(); }
    }

    /** Return eye anchors in primary pixel coordinates; mirror roll before comparison. */
    private static List<double[]> eyeAnchors(Bitmap grayscale, int width, boolean mirror, BooleanSupplier cancel) throws IOException {
        width -= width & 1;if (width < 2) return Collections.emptyList();
        int height = Math.max(2, (int) Math.round(grayscale.getHeight() * width / (double) grayscale.getWidth()));
        Bitmap input = Bitmap.createBitmap(width, height, Bitmap.Config.RGB_565);
        try {
            Canvas canvas = new Canvas(input);
            if (mirror) { canvas.translate(width, 0);canvas.scale(-1, 1); }
            canvas.drawBitmap(grayscale, null, new android.graphics.Rect(0, 0, width, height), new Paint(Paint.FILTER_BITMAP_FLAG));
            check(cancel);FaceDetector.Face[] faces = new FaceDetector.Face[10];
            int count = new FaceDetector(width, height, faces.length).findFaces(input, faces);check(cancel);
            double scaleX = grayscale.getWidth() / (double) width, scaleY = grayscale.getHeight() / (double) height;
            ArrayList<double[]> result = new ArrayList<>();
            for (int i = 0; i < count; i++) {
                check(cancel);FaceDetector.Face face = faces[i];
                if (face == null || !Float.isFinite(face.confidence()) || face.confidence() < .35f) continue;
                float distance = face.eyesDistance();double roll = face.pose(FaceDetector.Face.EULER_Z);
                if (!Float.isFinite(distance) || distance < 5 / scaleX || !Double.isFinite(roll)) continue;
                PointF eyes = new PointF();face.getMidPoint(eyes);
                if (!Float.isFinite(eyes.x) || !Float.isFinite(eyes.y)) continue;
                double angle = Math.toRadians(roll), mappedDistance = distance * Math.hypot(Math.cos(angle) * scaleX, Math.sin(angle) * scaleY);
                result.add(new double[]{(mirror ? width - 1 - eyes.x : eyes.x) * scaleX, eyes.y * scaleY, mappedDistance, mirror ? -roll : roll, face.confidence()});
            }
            return result;
        } finally { input.recycle(); }
    }

    /** One-to-one nearest eye anchors, not top-score or top-one selection. */
    private static boolean[] consensusMatches(List<double[]> primary, List<double[]> secondary, BooleanSupplier cancel) throws IOException {
        boolean[] matched = new boolean[primary.size()], used = new boolean[secondary.size()];
        for (;;) {
            check(cancel);double best = Double.POSITIVE_INFINITY;int chosenPrimary = -1, chosenSecondary = -1;
            for (int i = 0; i < primary.size(); i++) if (!matched[i]) {
                double[] a = primary.get(i);if (!validAnchor(a)) continue;
                for (int j = 0; j < secondary.size(); j++) if (!used[j]) {
                    double[] b = secondary.get(j);if (!validAnchor(b) || !compatibleRoll(a, b)) continue;double ratio = b[2] / a[2];
                    if (ratio < .75 || ratio > 1.33) continue;
                    double dx = a[0] - b[0], dy = a[1] - b[1], distanceSquared = dx * dx + dy * dy;
                    double limit = .3 * (a[2] + b[2]) / 2;
                    if (distanceSquared <= limit * limit && distanceSquared < best) {
                        best = distanceSquared;chosenPrimary = i;chosenSecondary = j;
                    }
                }
            }
            if (chosenPrimary < 0) return matched;
            matched[chosenPrimary] = true;used[chosenSecondary] = true;
        }
    }

    private static boolean validAnchor(double[] value) {
        return value != null && value.length >= 3 && Double.isFinite(value[0]) && Double.isFinite(value[1])
                && Double.isFinite(value[2]) && value[2] > 0 && (value.length < 4 || Double.isFinite(value[3]));
    }
    private static boolean compatibleRoll(double[] a, double[] b) {
        return a.length < 4 || b.length < 4 || Math.abs(Math.IEEEremainder(a[3] - b[3], 360)) <= 20;
    }
    /** Merge only almost coincident eye pairs, preserving adjacent people and different scales. */
    private static boolean duplicate(double[] a, double[] b) {
        if (!validAnchor(a) || !validAnchor(b) || !compatibleRoll(a, b)) return false;
        double ratio = b[2] / a[2];if (ratio < .7 || ratio > 1 / .7) return false;
        return Math.hypot(a[0] - b[0], a[1] - b[1]) <= .35 * Math.min(a[2], b[2]);
    }

    /** A hand-drawn face uses exactly the same immutable mask/settings path as detection. */
    public static PhotoPortrait.Face manualFace(Bitmap image, double cx, double cy, double rx, double ry) {
        cx = clamp(cx, 0, 1); cy = clamp(cy, 0, 1);
        rx = clamp(rx, .005, .5); ry = clamp(ry, .005, .5);
        int colour = skinSample(image, cx, cy, rx, ry, 0);
        return new PhotoPortrait.Face(cx, cy, rx, ry, 0, (colour >>> 16) & 255, (colour >>> 8) & 255,
                colour & 255, true, PhotoPortrait.Settings.NONE, Collections.emptyList());
    }

    /** Choose nearby texture with a matching boundary; save the explicit source for full-size output. */
    public static PhotoPortrait.Heal heal(Bitmap image, double tx, double ty, double radius) {
        if (image == null || image.isRecycled()) throw new IllegalArgumentException("修复图片无效。");
        tx = clamp(tx, 0, 1); ty = clamp(ty, 0, 1); radius = clamp(radius, .002, .12);
        double shortSide = Math.min(image.getWidth(), image.getHeight());
        double rx = radius * shortSide / image.getWidth(), ry = radius * shortSide / image.getHeight();
        double best = Double.POSITIVE_INFINITY, sx = tx, sy = ty;
        for (int ring = 0; ring < 3; ring++) for (int angle = 0; angle < 16; angle++) {
            double a = 2 * Math.PI * angle / 16, distance = 2.6 + ring * 1.3;
            double x = tx + Math.cos(a) * rx * distance, y = ty + Math.sin(a) * ry * distance;
            if (x - rx < 0 || x + rx > 1 || y - ry < 0 || y + ry > 1) continue;
            double score = 0;
            for (int j = 0; j < 16; j++) {
                double b = 2 * Math.PI * j / 16, ox = Math.cos(b) * rx * .9, oy = Math.sin(b) * ry * .9;
                int source = pixel(image, x + ox, y + oy), target = pixel(image, tx + ox, ty + oy);
                double dr = ((source >>> 16) & 255) - ((target >>> 16) & 255);
                double dg = ((source >>> 8) & 255) - ((target >>> 8) & 255);
                double db = (source & 255) - (target & 255);
                score += dr * dr * .25 + dg * dg * .5 + db * db * .25;
            }
            // Prefer a close reference when boundaries are equally suitable.
            score += distance * distance * 2;
            if (score < best) { best = score; sx = x; sy = y; }
        }
        if (!Double.isFinite(best)) throw new IllegalArgumentException("瑕疵太靠近边缘，请缩小修复范围。");
        return new PhotoPortrait.Heal(sx, sy, tx, ty, radius, .7, true);
    }

    private static int skinSample(Bitmap image, double cx, double cy, double rx, double ry, double roll) {
        // The forehead and two cheeks avoid eyes, nose highlights and the mouth.
        double[][] centers = {{-.43, .03}, {.43, .03}, {0, -.69}};
        int[] red = new int[75], green = new int[75], blue = new int[75]; int count = 0;
        double a = Math.toRadians(roll), cosine = Math.cos(a), sine = Math.sin(a);
        double aspect = image.getWidth() / (double) image.getHeight();
        for (double[] center : centers) for (int y = -2; y <= 2; y++) for (int x = -2; x <= 2; x++) {
            double px = (center[0] + x * .035) * rx, py = (center[1] + y * .035) * ry;
            double nx = cx + cosine * px - sine * py / aspect, ny = cy + sine * px * aspect + cosine * py;
            int value = pixel(image, nx, ny), r = (value >>> 16) & 255, g = (value >>> 8) & 255, b = value & 255;
            int luminance = (r * 54 + g * 183 + b * 19) / 256;
            if (luminance < 12 || luminance > 248) continue;
            red[count] = r; green[count] = g; blue[count] = b; count++;
        }
        if (count == 0) return pixel(image, cx, cy);
        java.util.Arrays.sort(red, 0, count); java.util.Arrays.sort(green, 0, count); java.util.Arrays.sort(blue, 0, count);
        return 0xff000000 | (red[count / 2] << 16) | (green[count / 2] << 8) | blue[count / 2];
    }
    /** Same 5x5 cheek/eye patches as the recorded candidate diagnostics, rotated in pixel space. */
    private static boolean contradictoryEyeStructure(Bitmap image, double cx, double cy, double rx, double ry, double roll) {
        int leftCheek = patchLuminance(image, cx, cy, rx, ry, roll, -.43, .03);
        int rightCheek = patchLuminance(image, cx, cy, rx, ry, roll, .43, .03);
        int leftEye = patchLuminance(image, cx, cy, rx, ry, roll, -.526, -.407);
        int rightEye = patchLuminance(image, cx, cy, rx, ry, roll, .526, -.407);
        // Missing usable samples are not evidence against a proposal.
        if (leftCheek < 0 || rightCheek < 0 || leftEye < 0 || rightEye < 0) return false;
        int eye = Math.min(leftEye, rightEye), cheek = Math.max(leftCheek, rightCheek);
        return eye - cheek > 12 && eye / (cheek + 1.0) > 1.15;
    }
    private static int patchLuminance(Bitmap image, double cx, double cy, double rx, double ry, double roll,
            double centerX, double centerY) {
        int[] red = new int[25], green = new int[25], blue = new int[25]; int count = 0;
        double radians = Math.toRadians(roll), cosine = Math.cos(radians), sine = Math.sin(radians);
        double aspect = image.getWidth() / (double) image.getHeight();
        for (int y = -2; y <= 2; y++) for (int x = -2; x <= 2; x++) {
            double px = (centerX + x * .035) * rx, py = (centerY + y * .035) * ry;
            double nx = cx + cosine * px - sine * py / aspect, ny = cy + sine * px * aspect + cosine * py;
            int value = pixel(image, nx, ny), r = (value >>> 16) & 255, g = (value >>> 8) & 255, b = value & 255;
            int luminance = (r * 54 + g * 183 + b * 19) / 256;
            if (luminance < 12 || luminance > 248) continue;
            red[count] = r; green[count] = g; blue[count] = b; count++;
        }
        if (count == 0) return -1;
        java.util.Arrays.sort(red, 0, count); java.util.Arrays.sort(green, 0, count); java.util.Arrays.sort(blue, 0, count);
        return (red[count / 2] * 54 + green[count / 2] * 183 + blue[count / 2] * 19) / 256;
    }
    private static int pixel(Bitmap image, double x, double y) {
        return image.getPixel((int) Math.round(clamp(x, 0, 1) * (image.getWidth() - 1)),
                (int) Math.round(clamp(y, 0, 1) * (image.getHeight() - 1)));
    }
    private static double clamp(double value, double min, double max) { return Math.max(min, Math.min(max, value)); }
    private static void check(BooleanSupplier cancel) throws IOException {
        if (cancel.getAsBoolean() || Thread.currentThread().isInterrupted()) throw new IOException("人脸识别已取消。");
    }
}
