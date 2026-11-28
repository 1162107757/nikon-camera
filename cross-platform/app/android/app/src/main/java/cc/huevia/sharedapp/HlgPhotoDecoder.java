package cc.huevia.sharedapp;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.BitmapRegionDecoder;
import android.graphics.ColorSpace;
import android.graphics.Rect;
import android.os.Build;
import android.util.Half;

import java.io.File;
import java.io.IOException;
import java.io.InterruptedIOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.function.BooleanSupplier;

/** Converts tagged HLG HEIF pixels to the editor's SDR working space. */
final class HlgPhotoDecoder {
    private static final int ROWS = 64;
    private static final int TABLE_SIZE = 4096;
    private static final float[] HLG_TO_SCENE = new float[TABLE_SIZE + 1];
    private static final float[] SCENE_TO_SDR = new float[TABLE_SIZE + 1];
    private static final int[] LINEAR_TO_SRGB = new int[TABLE_SIZE + 1];

    static {
        for (int i = 0; i <= TABLE_SIZE; i++) {
            double value = i / (double) TABLE_SIZE;
            // BT.2100 inverse HLG OETF and the 1000 nit reference display gamma.
            HLG_TO_SCENE[i] = (float) (value <= .5 ? value * value / 3
                    : (Math.exp((value - .55991073) / .17883277) + .28466892) / 12);
            double display = Math.pow(value, 1.2);
            // Roll off above diffuse white while keeping 75% HLG near 75% SDR.
            SCENE_TO_SDR[i] = (float) (1.3 * display / (.3 + display));
            LINEAR_TO_SRGB[i] = (int) Math.round(255 * (value <= .0031308 ? 12.92 * value
                    : 1.055 * Math.pow(value, 1 / 2.4) - .055));
        }
    }

    private HlgPhotoDecoder() {}

    static boolean matches(BitmapFactory.Options bounds) {
        return Build.VERSION.SDK_INT >= 34
                && ("image/heif".equals(bounds.outMimeType) || "image/heic".equals(bounds.outMimeType))
                && ColorSpace.get(ColorSpace.Named.BT2020_HLG).equals(bounds.outColorSpace);
    }

    static Bitmap decode(File source, BitmapFactory.Options bounds, int sample, BooleanSupplier cancel)
            throws IOException {
        checkCancelled(cancel);
        BitmapFactory.Options options = hlgOptions();
        options.inSampleSize = sample;
        if (sample > 1) {
            Bitmap pixels = BitmapFactory.decodeFile(source.getPath(), options);
            try {
                requireHlg(pixels);
                return convert(pixels, null, pixels.getWidth(), pixels.getHeight(), cancel);
            } finally {
                if (pixels != null) pixels.recycle();
            }
        }
        BitmapRegionDecoder decoder = BitmapRegionDecoder.newInstance(source.getPath(), false);
        if (decoder == null) throw unsupported();
        try {
            return convert(null, decoder, bounds.outWidth, bounds.outHeight, cancel);
        } finally {
            decoder.recycle();
        }
    }

    private static Bitmap convert(Bitmap sampled, BitmapRegionDecoder decoder, int width, int height,
                                  BooleanSupplier cancel) throws IOException {
        Bitmap output = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
        boolean complete = false;
        try {
            int rowsPerBlock = sampled == null ? ROWS : height;
            int[] row = new int[width];
            ByteBuffer buffer = null;
            for (int top = 0; top < height; top += rowsPerBlock) {
                checkCancelled(cancel);
                int bottom = Math.min(top + rowsPerBlock, height);
                Bitmap block = sampled == null ? decoder.decodeRegion(new Rect(0, top, width, bottom),
                        hlgOptions()) : sampled;
                try {
                    requireHlg(block);
                    if (block.getWidth() != width || block.getHeight() != bottom - top) throw unsupported();
                    if (buffer == null || buffer.capacity() < block.getByteCount()) {
                        buffer = ByteBuffer.allocate(block.getByteCount()).order(ByteOrder.nativeOrder());
                    }
                    buffer.clear();
                    block.copyPixelsToBuffer(buffer);
                    for (int y = 0; y < block.getHeight(); y++) {
                        checkCancelled(cancel);
                        buffer.position(y * block.getRowBytes());
                        for (int x = 0; x < width; x++) row[x] = toSdr(buffer);
                        output.setPixels(row, 0, width, 0, top + y, width, 1);
                    }
                } finally {
                    if (sampled == null && block != null) block.recycle();
                }
            }
            complete = true;
            return output;
        } finally {
            if (!complete) output.recycle();
        }
    }

    private static BitmapFactory.Options hlgOptions() {
        BitmapFactory.Options options = new BitmapFactory.Options();
        options.inPreferredConfig = Bitmap.Config.RGBA_F16;
        return options;
    }

    private static void requireHlg(Bitmap bitmap) throws IOException {
        if (bitmap == null || bitmap.getConfig() != Bitmap.Config.RGBA_F16
                || !ColorSpace.get(ColorSpace.Named.BT2020_HLG).equals(bitmap.getColorSpace())) throw unsupported();
    }

    private static IOException unsupported() {
        return new IOException("当前设备无法解码这张 HLG 照片。");
    }

    private static void checkCancelled(BooleanSupplier cancel) throws InterruptedIOException {
        if (cancel.getAsBoolean()) throw new InterruptedIOException("照片处理已取消。");
    }

    private static int toSdr(ByteBuffer buffer) {
        float r = Half.toFloat(buffer.getShort());
        float g = Half.toFloat(buffer.getShort());
        float b = Half.toFloat(buffer.getShort());
        float alpha = Half.toFloat(buffer.getShort());
        if (!(alpha > 0)) return 0;
        r = sample(HLG_TO_SCENE, r / alpha);
        g = sample(HLG_TO_SCENE, g / alpha);
        b = sample(HLG_TO_SCENE, b / alpha);
        float luminance = .2627f * r + .6780f * g + .0593f * b;
        if (luminance <= 0) return Math.round(255 * alpha) << 24;
        float target = sample(SCENE_TO_SDR, luminance);
        float scale = target / luminance;
        // Linear BT.2020 to linear sRGB/BT.709, using their common D65 white point.
        float red = scale * (1.6605f * r - .5876f * g - .0728f * b);
        float green = scale * (-.1246f * r + 1.1329f * g - .0083f * b);
        float blue = scale * (-.0182f * r - .1006f * g + 1.1187f * b);
        // Bring wide-gamut colours into sRGB without independently clipping RGB channels.
        float low = Math.min(red, Math.min(green, blue));
        float high = Math.max(red, Math.max(green, blue));
        float chroma = 1;
        if (low < 0) chroma = target / (target - low);
        if (high > 1) chroma = Math.min(chroma, (1 - target) / (high - target));
        return (Math.round(255 * alpha) << 24) | (encode(target + (red - target) * chroma) << 16)
                | (encode(target + (green - target) * chroma) << 8) | encode(target + (blue - target) * chroma);
    }

    private static float sample(float[] table, float value) {
        float position = Math.max(0, Math.min(1, value)) * TABLE_SIZE;
        int lower = Math.min((int) position, TABLE_SIZE - 1);
        return table[lower] + (position - lower) * (table[lower + 1] - table[lower]);
    }

    private static int encode(float value) {
        return LINEAR_TO_SRGB[Math.round(Math.max(0, Math.min(1, value)) * TABLE_SIZE)];
    }
}
