package cc.huevia.album;

import android.graphics.Bitmap;
import android.graphics.Rect;
import java.io.File;
import java.io.IOException;
import java.io.InterruptedIOException;
import java.io.RandomAccessFile;
import java.nio.file.Files;
import java.util.Arrays;
import java.util.concurrent.atomic.AtomicInteger;

public final class PhotoDetailRasterTest {
    private static int checks;
    public static void main(String[] args) throws Exception {
        File directory = Files.createTempDirectory("photo-detail-raster-").toFile();
        try {
            exactRegions(directory);
            boundedBlocksAndCancellation(directory);
            invalidFilesAndLifecycle(directory);
            System.out.println("PhotoDetailRaster: " + checks + " checks passed.");
        } finally {
            File[] files = directory.listFiles();
            if (files != null) for (File file : files) Files.deleteIfExists(file.toPath());
            Files.deleteIfExists(directory.toPath());
        }
    }
    private static void exactRegions(File directory) throws Exception {
        Bitmap source = bitmap(7, 5);
        File target = new File(directory, "exact.argb");
        PhotoDetailRaster.write(target, source, () -> false);
        check(target.length() == 16 + 7 * 5 * 4, "exact packed size");
        try (RandomAccessFile header = new RandomAccessFile(target, "r")) {
            check(header.readInt() == 0x50445241 && header.readInt() == 1 && header.readInt() == 7 && header.readInt() == 5, "versioned big-endian header");
        }
        try (PhotoDetailRaster raster = new PhotoDetailRaster(target)) {
            check(raster.width() == 7 && raster.height() == 5, "dimensions");
            assertRegion(source, raster.decodeRegion(new Rect(0, 0, 7, 5), 1), new Rect(0, 0, 7, 5), 1);
            assertRegion(source, raster.decodeRegion(new Rect(1, 1, 6, 4), 1), new Rect(1, 1, 6, 4), 1);
            assertRegion(source, raster.decodeRegion(new Rect(1, 1, 6, 4), 2), new Rect(1, 1, 6, 4), 2);
            assertRegion(source, raster.decodeRegion(new Rect(6, 4, 7, 5), 8), new Rect(6, 4, 7, 5), 8);
            assertRegion(source, raster.decodeRegion(new Rect(0, 0, 7, 5), Integer.MAX_VALUE), new Rect(0, 0, 7, 5), Integer.MAX_VALUE);
            expectIOException(() -> raster.decodeRegion(new Rect(-1, 0, 1, 1), 1));
            expectIOException(() -> raster.decodeRegion(new Rect(0, 0, 8, 1), 1));
            expectIOException(() -> raster.decodeRegion(new Rect(0, 0, 0, 1), 1));
            expectIOException(() -> raster.decodeRegion(new Rect(0, 0, 1, 1), 0));
        }
        byte[] original = Files.readAllBytes(target.toPath());
        expectIOException(() -> PhotoDetailRaster.write(target, source, () -> false));
        check(Arrays.equals(original, Files.readAllBytes(target.toPath())), "existing target is never overwritten");
    }
    private static void boundedBlocksAndCancellation(File directory) throws Exception {
        Bitmap source = bitmap(257, 300);
        File target = new File(directory, "blocks.argb");
        AtomicInteger maxRows = new AtomicInteger();
        source.beforeRead = maxRows::incrementAndGet;
        PhotoDetailRaster.write(target, source, () -> false);
        check(maxRows.get() > 1, "large input written in bounded blocks");
        source.beforeRead = null;
        try (PhotoDetailRaster raster = new PhotoDetailRaster(target)) {
            assertRegion(source, raster.decodeRegion(new Rect(250, 253, 257, 300), 1), new Rect(250, 253, 257, 300), 1);
        }
        File cancelled = new File(directory, "cancelled.argb");
        expectIOException(() -> PhotoDetailRaster.write(cancelled, source, () -> true));
        check(!cancelled.exists(), "initial cancellation creates no file");
        AtomicInteger polls = new AtomicInteger();
        expectIOException(() -> PhotoDetailRaster.write(cancelled, source, () -> polls.incrementAndGet() >= 5));
        check(!cancelled.exists(), "mid-write cancellation deletes partial file");
        source.beforeRead = () -> { throw new IllegalStateException("synthetic bitmap read failure"); };
        try { PhotoDetailRaster.write(cancelled, source, () -> false); throw new AssertionError("expected bitmap read failure"); }
        catch (IllegalStateException expected) { checks++; }
        check(!cancelled.exists(), "runtime write failure deletes partial file");
        source.beforeRead = null;
        Thread.currentThread().interrupt();
        try {
            try { PhotoDetailRaster.write(cancelled, source, () -> false); throw new AssertionError("expected interruption"); }
            catch (InterruptedIOException expected) { check(Thread.currentThread().isInterrupted(), "write preserves interruption"); }
        } finally { Thread.interrupted(); }
        check(!cancelled.exists(), "interrupted write leaves no file");
    }
    private static void invalidFilesAndLifecycle(File directory) throws Exception {
        File target = new File(directory, "invalid.argb");
        Files.write(target.toPath(), new byte[15]);
        expectIOException(() -> new PhotoDetailRaster(target));
        writeHeader(target, 0, 1, 1, 1, 20);
        expectIOException(() -> new PhotoDetailRaster(target));
        writeHeader(target, 0x50445241, 2, 1, 1, 20);
        expectIOException(() -> new PhotoDetailRaster(target));
        for (int dimension : new int[]{0, -1, 65536, Integer.MAX_VALUE}) {
            writeHeader(target, 0x50445241, 1, dimension, 1, 20);
            expectIOException(() -> new PhotoDetailRaster(target));
        }
        writeHeader(target, 0x50445241, 1, 2, 2, 31);
        expectIOException(() -> new PhotoDetailRaster(target));
        writeHeader(target, 0x50445241, 1, 2, 2, 33);
        expectIOException(() -> new PhotoDetailRaster(target));
        writeHeader(target, 0x50445241, 1, 2, 2, 32);
        PhotoDetailRaster closed = new PhotoDetailRaster(target);
        closed.close(); closed.close();
        expectIOException(() -> closed.decodeRegion(new Rect(0, 0, 1, 1), 1));
        try (PhotoDetailRaster truncated = new PhotoDetailRaster(target)) {
            try (RandomAccessFile file = new RandomAccessFile(target, "rw")) { file.setLength(17); }
            expectIOException(() -> truncated.decodeRegion(new Rect(0, 0, 2, 2), 1));
            check(Bitmap.lastCreated.isRecycled(), "failed region read recycles incomplete bitmap");
        }
        writeHeader(target, 0x50445241, 1, 2, 2, 32);
        try (PhotoDetailRaster interrupted = new PhotoDetailRaster(target)) {
            Thread.currentThread().interrupt();
            try {
                expectIOException(() -> interrupted.decodeRegion(new Rect(0, 0, 2, 2), 1));
                check(Thread.currentThread().isInterrupted(), "region read preserves interruption");
                check(Bitmap.lastCreated.isRecycled(), "interrupted read recycles incomplete bitmap");
            } finally { Thread.interrupted(); }
        }
    }
    private static void writeHeader(File target, int magic, int version, int width, int height, long length) throws IOException {
        try (RandomAccessFile file = new RandomAccessFile(target, "rw")) {
            file.setLength(0); file.writeInt(magic); file.writeInt(version); file.writeInt(width); file.writeInt(height); file.setLength(length);
        }
    }
    private static Bitmap bitmap(int width, int height) {
        Bitmap bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
        int[] pixels = new int[width * height];
        for (int i = 0; i < pixels.length; i++) pixels[i] = i * 0x1f123bb5 ^ 0xa5f0c381;
        bitmap.setPixels(pixels, 0, width, 0, 0, width, height);
        return bitmap;
    }
    private static void assertRegion(Bitmap source, Bitmap actual, Rect region, int sample) {
        int w = (region.width() - 1) / sample + 1, h = (region.height() - 1) / sample + 1;
        check(actual.getWidth() == w && actual.getHeight() == h, "sampled ceil dimensions");
        int[] all = new int[source.getWidth() * source.getHeight()], result = new int[w * h];
        source.getPixels(all, 0, source.getWidth(), 0, 0, source.getWidth(), source.getHeight());
        actual.getPixels(result, 0, w, 0, 0, w, h);
        for (int y = 0; y < h; y++) for (int x = 0; x < w; x++)
            check(result[y * w + x] == all[(region.top + y * sample) * source.getWidth() + region.left + x * sample], "exact ARGB source pixel");
        actual.recycle();
    }
    private interface IoAction { void run() throws IOException; }
    private static void expectIOException(IoAction action) throws Exception {
        try { action.run(); throw new AssertionError("expected IOException"); }
        catch (IOException expected) { checks++; }
    }
    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
        checks++;
    }
}
