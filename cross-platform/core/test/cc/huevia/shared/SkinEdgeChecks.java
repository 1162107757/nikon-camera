package cc.huevia.shared;

import cc.huevia.ncp.AdjustmentRegion;
import cc.huevia.ncp.AdjustmentRegionRenderer;
import cc.huevia.ncp.PhotoAdjustments;
import cc.huevia.ncp.PhotoPortrait;
import cc.huevia.ncp.PortraitPreviewFilter;
import cc.huevia.ncp.SelectionShape;
import cc.huevia.ncp.SkinTone;
import cc.huevia.ncp.SpatialPreviewFilter;
import java.io.IOException;
import java.util.Collections;

/** A coarse automatic mask must not transfer a strong skin adjustment to a contrasting background. */
final class SkinEdgeChecks {
    private SkinEdgeChecks() {}

    static int run() throws IOException {
        check(768, 448, 1, 0xffcc9277, 0xff465361);
        check(224, 384, 6, 0xff835741, 0xffb9ad98);
        return 8;
    }

    private static void check(int width, int height, int exif, int skin, int background) throws IOException {
        int size = PhotoPortrait.BodySkinMask.SIZE;
        byte[] coverage = new byte[size * size];
        for (int y = 0; y < size; y++) {
            for (int x = 0; x < size; x++) {
                if ((x + .5) / size < edge((y + .5) / size)) coverage[y * size + x] = (byte) 255;
            }
        }
        PhotoPortrait.BodySkinMask mask = new PhotoPortrait.BodySkinMask(coverage);
        PhotoPortrait portrait = PhotoPortrait.NONE.withGlobalSkinMask(mask);
        AdjustmentRegion region = new AdjustmentRegion("skin-edge", "Skin", true, 1, Collections.emptyList(),
                PhotoAdjustments.NONE, portrait, new PhotoPortrait.Settings(100, 0, 0, 0, 70, 0, 0),
                null, Collections.singletonList(new SelectionShape(
                        SelectionShape.Kind.RECTANGLE, 0, 0, 1, 1, 0, false, 0)), false);
        Scene regional = new Scene(width, height, exif, skin, background);
        AdjustmentRegionRenderer.apply(regional, Collections.singletonList(region), exif, () -> false, null);
        Scene global = new Scene(width, height, exif, skin, background);
        PortraitPreviewFilter.apply(global, portrait.withGlobalTone(SkinTone.preset(2, 1, false)),
                exif, () -> false, null);
        regional.assertSkinOnly("regional brightness");
        global.assertSkinOnly("whole-photo skin tone");
    }

    private static double edge(double y) {
        return .413 + .179 * y;
    }

    private static final class Scene implements SpatialPreviewFilter.Pixels {
        final int width, height, exif, skin, background;
        final int[] pixels;

        Scene(int width, int height, int exif, int skin, int background) {
            this.width = width;
            this.height = height;
            this.exif = exif;
            this.skin = skin;
            this.background = background;
            pixels = new int[width * height];
            for (int y = 0; y < height; y++) {
                for (int x = 0; x < width; x++) pixels[y * width + x] = distance(x, y) < 0 ? skin : background;
            }
        }

        private double distance(int x, int y) {
            double nx = (x + .5) / width, ny = (y + .5) / height;
            return exif == 6 ? 1 - ny - edge(nx) : nx - edge(ny);
        }

        void assertSkinOnly(String action) {
            int outside = 0, inside = 255;
            for (int y = 4; y < height - 4; y++) {
                for (int x = 4; x < width - 4; x++) {
                    double d = distance(x, y);
                    int blue = pixels[y * width + x] & 255;
                    if (d >= 0) outside = Math.max(outside, Math.abs(blue - (background & 255)));
                    if (d < -.03 && d > -.1) inside = Math.min(inside, blue - (skin & 255));
                }
            }
            System.out.println("Skin edge " + action + " EXIF " + exif + ": outside=" + outside + ", inside=" + inside);
            if (outside > 2 || inside < 12) throw new AssertionError(action + " skin edge: outside=" + outside + ", inside=" + inside);
        }

        @Override public int width() { return width; }
        @Override public int height() { return height; }
        @Override public void read(int[] out, int first, int rows) {
            System.arraycopy(pixels, first * width, out, 0, rows * width);
        }
        @Override public void write(int[] in, int first, int rows) {
            System.arraycopy(in, 0, pixels, first * width, rows * width);
        }
    }
}
