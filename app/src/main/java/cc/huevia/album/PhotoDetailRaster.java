package cc.huevia.album;

import android.graphics.Bitmap;
import android.graphics.Rect;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InterruptedIOException;
import java.io.RandomAccessFile;
import java.nio.Buffer;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.channels.FileChannel;
import java.util.function.BooleanSupplier;

/** Private, lossless detail pixels. Rows stay on disk rather than retaining a full bitmap. */
final class PhotoDetailRaster implements AutoCloseable {
    private static final int MAGIC = 0x50445241; // PDRA
    private static final int VERSION = 1;
    private static final int HEADER_BYTES = 16;
    private static final int BUFFER_BYTES = 256 * 1024;
    private static final long MAX_TILE_PIXELS = 8_388_608L;
    private final RandomAccessFile input;
    private final int width, height;
    private boolean closed;

    /** A new target only: an incomplete write is never a readable detail surface. */
    static void write(File target, Bitmap bitmap, BooleanSupplier cancel) throws IOException {
        if (target == null || bitmap == null || cancel == null) throw new IllegalArgumentException("target/bitmap/cancel");
        int width = bitmap.getWidth(), height = bitmap.getHeight();
        long expected = fileBytes(width, height);
        checkCancelled(cancel);
        if (!target.createNewFile()) throw new IOException("细节暂存目标已存在。");
        boolean complete = false;
        try {
            int blockRows = Math.max(1, Math.min(height, BUFFER_BYTES / (width * 4)));
            int[] pixels = new int[width * blockRows];
            ByteBuffer bytes = ByteBuffer.allocate(pixels.length * 4).order(ByteOrder.BIG_ENDIAN);
            try (FileOutputStream output = new FileOutputStream(target)) {
                FileChannel channel = output.getChannel();
                ByteBuffer header = ByteBuffer.allocate(HEADER_BYTES).order(ByteOrder.BIG_ENDIAN);
                header.putInt(MAGIC).putInt(VERSION).putInt(width).putInt(height);
                ((Buffer) header).flip();
                writeFully(channel, header, cancel);
                for (int y = 0; y < height; y += blockRows) {
                    checkCancelled(cancel);
                    int rows = Math.min(blockRows, height - y), count = width * rows;
                    bitmap.getPixels(pixels, 0, width, 0, y, width, rows);
                    ((Buffer) bytes).clear();
                    bytes.asIntBuffer().put(pixels, 0, count);
                    ((Buffer) bytes).limit(count * 4);
                    writeFully(channel, bytes, cancel);
                }
                checkCancelled(cancel);
                if (channel.position() != expected || channel.size() != expected) throw new IOException("细节暂存大小不符。");
            }
            checkCancelled(cancel);
            complete = true;
        } finally {
            if (!complete) target.delete();
        }
    }

    PhotoDetailRaster(File file) throws IOException {
        RandomAccessFile opened = new RandomAccessFile(file, "r");
        boolean valid = false;
        try {
            if (opened.length() < HEADER_BYTES || opened.readInt() != MAGIC || opened.readInt() != VERSION)
                throw new IOException("细节暂存格式无效。");
            int w = opened.readInt(), h = opened.readInt();
            if (opened.length() != fileBytes(w, h)) throw new IOException("细节暂存不完整。");
            width = w;
            height = h;
            input = opened;
            valid = true;
        } finally {
            if (!valid) opened.close();
        }
    }

    int width() { return width; }
    int height() { return height; }

    /** Point samples preserve exact 1:1 pixels and retain partial sampled edge tiles. */
    synchronized Bitmap decodeRegion(Rect region, int sample) throws IOException {
        if (closed) throw new IOException("细节暂存已关闭。");
        if (sample < 1 || region == null || region.left < 0 || region.top < 0
                || region.right > width || region.bottom > height || region.width() < 1 || region.height() < 1)
            throw new IOException("细节区域无效。");
        int outputWidth = (region.width() - 1) / sample + 1;
        int outputHeight = (region.height() - 1) / sample + 1;
        if ((long) outputWidth * outputHeight > MAX_TILE_PIXELS) throw new IOException("细节区域所需内存过多。");
        byte[] encoded = new byte[region.width() * 4];
        ByteBuffer bytes = ByteBuffer.wrap(encoded).order(ByteOrder.BIG_ENDIAN);
        int[] row = new int[outputWidth];
        Bitmap bitmap = Bitmap.createBitmap(outputWidth, outputHeight, Bitmap.Config.ARGB_8888);
        boolean complete = false;
        try {
            bitmap.setDensity(Bitmap.DENSITY_NONE);
            for (int y = 0; y < outputHeight; y++) {
                checkInterrupted();
                long sourceY = region.top + (long) y * sample;
                input.seek(HEADER_BYTES + (sourceY * width + region.left) * 4L);
                input.readFully(encoded);
                for (int x = 0; x < outputWidth; x++) row[x] = bytes.getInt((int) ((long) x * sample * 4));
                bitmap.setPixels(row, 0, outputWidth, 0, y, outputWidth, 1);
            }
            checkInterrupted();
            complete = true;
            return bitmap;
        } finally {
            if (!complete) bitmap.recycle();
        }
    }

    @Override public synchronized void close() throws IOException {
        if (closed) return;
        closed = true;
        input.close();
    }

    private static long fileBytes(int width, int height) throws IOException {
        if (width < 1 || height < 1 || width > 65535 || height > 65535) throw new IOException("细节照片尺寸无效。");
        return HEADER_BYTES + (long) width * height * 4L;
    }

    private static void writeFully(FileChannel channel, ByteBuffer bytes, BooleanSupplier cancel) throws IOException {
        while (bytes.hasRemaining()) {
            checkCancelled(cancel);
            channel.write(bytes);
        }
    }

    private static void checkCancelled(BooleanSupplier cancel) throws InterruptedIOException {
        checkInterrupted();
        if (cancel.getAsBoolean()) throw new InterruptedIOException("细节暂存已取消。");
    }

    private static void checkInterrupted() throws InterruptedIOException {
        if (Thread.currentThread().isInterrupted()) throw new InterruptedIOException("细节读取已中断。");
    }
}
