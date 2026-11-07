package android.graphics;

/** Exact integer pixels for testing the disk format; native Android codecs are not emulated. */
public final class Bitmap {
    public static final int DENSITY_NONE = 0;
    public enum Config { ARGB_8888 }
    public static Bitmap lastCreated;
    private final int width, height;
    private final int[] pixels;
    private boolean recycled;
    public Runnable beforeRead;
    private Bitmap(int width, int height) { this.width = width; this.height = height; pixels = new int[width * height]; }
    public static Bitmap createBitmap(int width, int height, Config config) { return lastCreated = new Bitmap(width, height); }
    public int getWidth() { return width; }
    public int getHeight() { return height; }
    public void setDensity(int density) { }
    public void getPixels(int[] target, int offset, int stride, int x, int y, int width, int height) {
        if (beforeRead != null) beforeRead.run();
        if (recycled) throw new IllegalStateException("recycled");
        for (int row = 0; row < height; row++) System.arraycopy(pixels, (y + row) * this.width + x, target, offset + row * stride, width);
    }
    public void setPixels(int[] source, int offset, int stride, int x, int y, int width, int height) {
        if (recycled) throw new IllegalStateException("recycled");
        for (int row = 0; row < height; row++) System.arraycopy(source, offset + row * stride, pixels, (y + row) * this.width + x, width);
    }
    public void recycle() { recycled = true; }
    public boolean isRecycled() { return recycled; }
}
