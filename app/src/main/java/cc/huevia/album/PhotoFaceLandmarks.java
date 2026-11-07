package cc.huevia.album;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.PorterDuff;
import cc.huevia.ncp.PhotoPortrait;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.function.BooleanSupplier;
import org.tensorflow.lite.DataType;
import org.tensorflow.lite.Interpreter;
import org.tensorflow.lite.InterpreterApi;
import org.tensorflow.lite.Tensor;

/** Bundled CPU-only face mesh refinement. No identity recognition, services or image upload. */
public final class PhotoFaceLandmarks {
    private static final String MODEL_ASSET = "portrait/face_landmarks_detector.tflite";
    private static final int INPUT_SIZE = 256;
    private static final double MIN_PRESENCE = .5;
    private PhotoFaceLandmarks() {}

    /**
     * Refine the proposed faces without changing their settings or eye-distance coordinate frame.
     * A proposal rejected by the model is omitted; invalid model output fails the whole operation.
     * No ellipse is substituted for a failed mesh, so callers can retain their previous edits.
     */
    public static List<PhotoPortrait.Face> refine(Context context, Bitmap orientedAnalysis,
            List<PhotoPortrait.Face> proposals, BooleanSupplier cancel) throws IOException {
        if (context == null || orientedAnalysis == null || orientedAnalysis.isRecycled()
                || proposals == null || cancel == null || proposals.size() > PhotoPortrait.MAX_FACES)
            throw new IllegalArgumentException("面部关键点参数无效。");
        for (PhotoPortrait.Face face : proposals) if (face == null)
            throw new IllegalArgumentException("人脸候选无效。");
        check(cancel);
        if (proposals.isEmpty()) return Collections.emptyList();
        Context application = context.getApplicationContext();
        if (application == null) application = context;
        ByteBuffer model = loadModel(application, cancel);
        Bitmap crop = null;
        try (Interpreter interpreter = new Interpreter(model, new Interpreter.Options()
                .setNumThreads(2).setUseNNAPI(false)
                .setRuntime(InterpreterApi.Options.TfLiteRuntime.FROM_APPLICATION_ONLY))) {
            check(cancel);
            validateModel(interpreter);
            ByteBuffer input = direct(INPUT_SIZE * INPUT_SIZE * 3 * Float.BYTES);
            ByteBuffer mesh = direct(interpreter.getOutputTensor(0).numBytes());
            ByteBuffer presence = direct(Float.BYTES);
            Map<Integer, Object> outputs = new HashMap<>();
            outputs.put(0, mesh); outputs.put(1, presence);
            crop = Bitmap.createBitmap(INPUT_SIZE, INPUT_SIZE, Bitmap.Config.ARGB_8888);
            Canvas canvas = new Canvas(crop);
            Paint paint = new Paint(Paint.FILTER_BITMAP_FLAG);
            int[] pixels = new int[INPUT_SIZE * INPUT_SIZE];
            ArrayList<PhotoPortrait.Face> result = new ArrayList<>();
            for (PhotoPortrait.Face face : proposals) {
                check(cancel);
                Crop geometry = new Crop(face, orientedAnalysis.getWidth(), orientedAnalysis.getHeight());
                canvas.drawColor(Color.BLACK, PorterDuff.Mode.SRC);
                canvas.drawBitmap(orientedAnalysis, geometry.matrix(), paint);
                check(cancel);
                crop.getPixels(pixels, 0, INPUT_SIZE, 0, 0, INPUT_SIZE, INPUT_SIZE);
                input.clear();
                for (int y = 0; y < INPUT_SIZE; y++) {
                    check(cancel);
                    for (int x = 0; x < INPUT_SIZE; x++) {
                        int argb = pixels[y * INPUT_SIZE + x];
                        // TFLITE_METADATA: RGB NormalizationOptions mean=0, std=255.
                        input.putFloat(((argb >>> 16) & 255) / 255f);
                        input.putFloat(((argb >>> 8) & 255) / 255f);
                        input.putFloat((argb & 255) / 255f);
                    }
                }
                input.rewind(); mesh.clear(); presence.clear(); check(cancel);
                interpreter.runForMultipleInputsOutputs(new Object[]{input}, outputs);
                check(cancel);
                float logit = presence.getFloat(0);
                if (!Float.isFinite(logit)) throw invalidOutput();
                // Identity_1 is a logit. The third head is not face presence and is unused.
                double probability = logit >= 0 ? 1 / (1 + Math.exp(-logit))
                        : Math.exp(logit) / (1 + Math.exp(logit));
                if (probability < MIN_PRESENCE) continue;
                double[] points = new double[PhotoPortrait.Landmarks.POINT_COUNT * 2];
                double minX = Double.POSITIVE_INFINITY, minY = Double.POSITIVE_INFINITY;
                double maxX = Double.NEGATIVE_INFINITY, maxY = Double.NEGATIVE_INFINITY;
                for (int i = 0; i < PhotoPortrait.Landmarks.POINT_COUNT; i++) {
                    if ((i & 31) == 0) check(cancel);
                    double x = geometry.localX(mesh.getFloat(i * 3 * Float.BYTES));
                    double y = geometry.localY(mesh.getFloat((i * 3 + 1) * Float.BYTES));
                    if (!Double.isFinite(x) || !Double.isFinite(y) || x < -8 || x > 8 || y < -8 || y > 8)
                        throw invalidOutput();
                    points[i * 2] = x; points[i * 2 + 1] = y;
                    minX = Math.min(minX, x); maxX = Math.max(maxX, x);
                    minY = Math.min(minY, y); maxY = Math.max(maxY, y);
                }
                if (maxX - minX < .1 || maxY - minY < .1) throw invalidOutput();
                result.add(face.withLandmarks(new PhotoPortrait.Landmarks(points)));
            }
            check(cancel);
            return Collections.unmodifiableList(result);
        } catch (RuntimeException | LinkageError | OutOfMemoryError failure) {
            throw new IOException("面部关键点识别暂不可用，请重试。", failure);
        } finally {
            if (crop != null) crop.recycle();
        }
    }

    private static void validateModel(Interpreter interpreter) throws IOException {
        if (interpreter.getInputTensorCount() != 1 || interpreter.getOutputTensorCount() < 2)
            throw invalidModel();
        Tensor input = interpreter.getInputTensor(0), mesh = interpreter.getOutputTensor(0), presence = interpreter.getOutputTensor(1);
        if (input.dataType() != DataType.FLOAT32 || !Arrays.equals(input.shape(), new int[]{1, INPUT_SIZE, INPUT_SIZE, 3})
                || mesh.dataType() != DataType.FLOAT32 || mesh.numElements() < PhotoPortrait.Landmarks.POINT_COUNT * 3
                || presence.dataType() != DataType.FLOAT32 || presence.numElements() != 1)
            throw invalidModel();
    }

    private static ByteBuffer loadModel(Context context, BooleanSupplier cancel) throws IOException {
        try (InputStream stream = context.getAssets().open(MODEL_ASSET);
                ByteArrayOutputStream bytes = new ByteArrayOutputStream(3 * 1024 * 1024)) {
            byte[] block = new byte[16 * 1024]; int count;
            while ((count = stream.read(block)) != -1) {
                check(cancel);
                if (bytes.size() + count > 8 * 1024 * 1024) throw invalidModel();
                bytes.write(block, 0, count);
            }
            check(cancel);
            if (bytes.size() < 16) throw invalidModel();
            ByteBuffer buffer = direct(bytes.size()); buffer.put(bytes.toByteArray()); buffer.rewind();
            return buffer;
        }
    }
    private static ByteBuffer direct(int bytes) { return ByteBuffer.allocateDirect(bytes).order(ByteOrder.nativeOrder()); }
    private static IOException invalidModel() { return new IOException("面部关键点模型无效，请重新安装应用。"); }
    private static IOException invalidOutput() { return new IOException("面部关键点未能可靠定位，请重新识别。"); }
    private static void check(BooleanSupplier cancel) throws IOException {
        if (cancel.getAsBoolean() || Thread.currentThread().isInterrupted()) throw new IOException("面部关键点识别已取消。");
    }

    /** Eye-aligned context crop; enlarging this view does not enlarge the resulting mesh mask. */
    static final class Crop {
        final double rx, ry, side, shiftY, centerX, centerY, cos, sin;
        Crop(PhotoPortrait.Face face, int width, int height) throws IOException {
            rx = face.rx * width; ry = face.ry * height;
            double distance = rx / .95, angle = Math.toRadians(face.roll);
            side = 3.5 * Math.max(rx, ry); shiftY = -.30 * distance;
            cos = Math.cos(angle); sin = Math.sin(angle);
            centerX = face.cx * width - sin * shiftY;
            centerY = face.cy * height + cos * shiftY;
            if (!Double.isFinite(side) || side <= 0 || !Double.isFinite(centerX) || !Double.isFinite(centerY))
                throw new IOException("人脸观察范围无效。");
        }
        Matrix matrix() {
            double scale = INPUT_SIZE / side;
            Matrix matrix = new Matrix();
            matrix.setValues(new float[]{(float)(cos * scale), (float)(sin * scale), (float)(INPUT_SIZE * .5 - scale * (cos * centerX + sin * centerY)),
                    (float)(-sin * scale), (float)(cos * scale), (float)(INPUT_SIZE * .5 + scale * (sin * centerX - cos * centerY)), 0, 0, 1});
            return matrix;
        }
        double localX(double modelX) { return (modelX / INPUT_SIZE - .5) * side / rx; }
        double localY(double modelY) { return ((modelY / INPUT_SIZE - .5) * side + shiftY) / ry; }
    }
}
