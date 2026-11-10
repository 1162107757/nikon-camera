package cc.huevia.ui;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;

import cc.huevia.ncp.PresetPreviewProfile;
import cc.huevia.ncp.PresetPreviewProfiles;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;

/** Photography for the preset gallery only. Photo editors keep their own input/preview path. */
public final class PresetShowcaseRenderer {
    public static final String PACK_VERSION = "photography-v1";
    private static final int MAX_EDGE = 960;
    private static final int MAX_BYTES = 1024 * 1024;
    private static final int MAX_CACHED_SOURCES = 3;
    private static final Scene[] SCENES = {
        // Generated from the checked, licensed pack manifest. These are neutral source photos,
        // not photographs taken with the user's preset or the phone approximation already baked in.
        new Scene("portrait-smile", "自然光人像", "Andrea Piacquadio / Pexels", "https://www.pexels.com/photo/woman-in-collared-shirt-774909/", "b0757386f8ef131671e50da1014be2445311a191d0c2a7d20a4898ccf034be58"),
        new Scene("portrait-man", "近景人像", "Simon Robben / Pexels", "https://www.pexels.com/photo/man-in-brown-polo-shirt-614810/", "7d7a190adc3a4e443b1bdba3537b819fbad524585c2501ec656b64ed68822182"),
        new Scene("alpine-lake", "山湖倒影", "James Wheeler / Pexels", "https://www.pexels.com/photo/lake-and-mountain-417074/", "a680f72eca42e3b3481ac64509d85e816e1f06290381ab755819c6e9d22113e3"),
        new Scene("sunlit-forest", "林间晨光", "Kamil Szerlag / Pexels", "https://www.pexels.com/photo/bright-sunshine-illuminating-path-between-woods-at-sunrise-4413480/", "1b3b8a78055fe4925de02d73f6898c96bfa83b61ceb1183fbc0cee2410f8c473"),
        new Scene("city-skyline", "日间城市", "Lukas Kloeppel / Pexels", "https://www.pexels.com/photo/empire-state-building-new-york-466685/", "a7724ec1452aa172bb879f9e11436381306206e279a08fac2974f6c932497486"),
        new Scene("neon-street", "霓虹街道", "Piotr Wojnowski / Pexels", "https://www.pexels.com/photo/quiet-urban-street-at-night-with-neon-signs-40512875/", "b5a24f781e6cdb2932aa0508f741933bb9e3721b75eeb4f4ef8467bd82e3ebe2"),
        new Scene("coastal-water", "海岸浪花", "Pok Rie / Pexels", "https://www.pexels.com/photo/transparent-sea-water-on-bright-sandy-beach-in-daylight-4103594/", "4114d6f8085b6cc1e0cd0d89b3ea12bb2db306ef35373654f222d68d4b4f4d28"),
        new Scene("pink-tulips", "粉色郁金香", "Nika Benedictova / Pexels", "https://www.pexels.com/photo/close-up-of-tulip-flowers-15802403/", "73c34ee92c3b55d2b1b6fd8ffee6df1939bc592884b2316f51523898bef54580"),
        new Scene("breakfast", "早餐静物", "Ash Craig / Pexels", "https://www.pexels.com/photo/pancake-with-sliced-strawberry-376464/", "b42c9d2617242b3f3d1ee2af96719dfd032eac6b72162cb3dc35a7e260694648"),
        new Scene("rainy-tokyo", "雨夜街头", "Dương Nhân / Pexels", "https://www.pexels.com/photo/people-on-a-street-in-japan-at-night-20188510/", "bf722e60694c45439242dec425f1366fdb4d57ab644c66415923e3299933fabe")
    };
    private static final int[] ALL = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9};
    private static final int[] PORTRAIT = {0, 1};
    private static final int[] LANDSCAPE = {2, 3, 6};
    private static final int[] NIGHT = {5, 9};
    private static final int[] DAILY = {0, 4, 6, 7, 8};

    private final Context context;
    private final PresetPreviewRenderer templates;
    private final LinkedHashMap<String, Pixels> pixels = new LinkedHashMap<>(4, .75f, true);

    public PresetShowcaseRenderer(Context context, PresetPreviewRenderer templates) {
        if (context == null || templates == null) throw new IllegalArgumentException("Context and templates required.");
        Context application = context.getApplicationContext();
        this.context = application == null ? context : application;
        this.templates = templates;
    }

    /** Main-thread safe; the scene and template setting are frozen for one preview request. */
    public Source source(String presetSha256, String category) {
        if (presetSha256 == null || !presetSha256.matches("[0-9a-f]{64}"))
            throw new IllegalArgumentException("A validated preset SHA-256 is required.");
        String templateVersion = templates.versionKey();
        boolean custom = templates.hasCustomTemplate();
        int[] pool = pool(category);
        long seed = Long.parseLong(presetSha256.substring(0, 8), 16);
        Scene scene = custom ? null : SCENES[pool[(int) (seed % pool.length)]];
        return new Source(scene, custom, PACK_VERSION + ':' + templateVersion);
    }

    public String versionKey() { return PACK_VERSION + ':' + templates.versionKey(); }
    /** Current gallery inputs, also used by the settings source viewer. No decoding on the UI thread. */
    public Source[] sources() {
        String version = versionKey();
        if (templates.hasCustomTemplate()) return new Source[]{new Source(null, true, version)};
        Source[] result = new Source[SCENES.length];
        for (int i = 0; i < result.length; i++) result[i] = new Source(SCENES[i], false, version);
        return result;
    }
    public boolean isCurrent(Source source) {
        return source != null && source.version.equals(versionKey()) && source.custom == templates.hasCustomTemplate();
    }

    /** Worker only. Produces an approximation using exactly the gallery's frozen source. */
    public Bitmap render(byte[] preset, Source source, int maxEdge) throws IOException {
        check(source, maxEdge);
        Bitmap result;
        try {
            if (source.custom) result = templates.render(preset, maxEdge);
            else {
                PresetPreviewProfile profile = PresetPreviewProfiles.fromPreset(preset);
                Pixels input = snapshot(source.scene, maxEdge);
                result = Bitmap.createBitmap(profile.render(input.argb, input.width, input.height),
                        input.width, input.height, Bitmap.Config.ARGB_8888);
            }
        } catch (OutOfMemoryError unavailable) {
            throw new IOException("样片预览内存不足，请稍后重试。", unavailable);
        }
        return checkedResult(source, result);
    }

    /** Worker only; held comparison always uses the same photo as its coloured preview. */
    public Bitmap original(Source source) throws IOException { return original(source, MAX_EDGE); }
    public Bitmap original(Source source, int maxEdge) throws IOException {
        check(source, maxEdge);
        Bitmap result;
        try {
            if (source.custom) {
                result = templates.originalTemplate();
                if (Math.max(result.getWidth(), result.getHeight()) > maxEdge) {
                    Bitmap full = result;
                    try { result = scaled(full, maxEdge); }
                    catch (RuntimeException | OutOfMemoryError failure) { full.recycle(); throw failure; }
                    if (result != full) full.recycle();
                }
            } else {
                Pixels input = snapshot(source.scene, maxEdge);
                result = Bitmap.createBitmap(input.argb, input.width, input.height, Bitmap.Config.ARGB_8888);
            }
        } catch (OutOfMemoryError unavailable) {
            throw new IOException("样片预览内存不足，请稍后重试。", unavailable);
        }
        return checkedResult(source, result);
    }

    private void check(Source source, int edge) throws IOException {
        if (edge < 128 || edge > MAX_EDGE) throw new IllegalArgumentException("Preview edge must be 128..960.");
        if (!isCurrent(source)) throw new IOException("预览模板已更换，请重新打开预设。");
    }

    private Bitmap checkedResult(Source source, Bitmap result) throws IOException {
        if (!isCurrent(source)) {
            result.recycle();
            throw new IOException("预览模板已更换，请重新打开预设。");
        }
        return result;
    }

    /** Only bounded, unmodified source pixels are retained; rendered bitmaps belong to the caller. */
    private synchronized Pixels snapshot(Scene scene, int edge) throws IOException {
        String key = scene.id + ':' + edge;
        Pixels found = pixels.get(key);
        if (found != null) return found;
        byte[] bytes;
        try (InputStream input = context.getAssets().open("preset-showcase/" + scene.id + ".jpg");
             ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[8192];
            int size;
            while ((size = input.read(buffer)) != -1) {
                if (output.size() + size > MAX_BYTES) throw new IOException("样片文件过大。");
                output.write(buffer, 0, size);
            }
            bytes = output.toByteArray();
        }
        if (!scene.sha256.equals(sha256(bytes))) throw new IOException("样片文件校验失败。");
        BitmapFactory.Options options = new BitmapFactory.Options();
        options.inJustDecodeBounds = true;
        BitmapFactory.decodeByteArray(bytes, 0, bytes.length, options);
        if (options.outWidth <= 0 || options.outHeight <= 0 || options.outWidth > MAX_EDGE || options.outHeight > MAX_EDGE)
            throw new IOException("样片尺寸无效。");
        options.inJustDecodeBounds = false;
        options.inScaled = false;
        options.inPreferredConfig = Bitmap.Config.ARGB_8888;
        Bitmap bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.length, options);
        if (bitmap == null) throw new IOException("无法解码样片。");
        try {
            Bitmap reduced = scaled(bitmap, edge);
            if (reduced != bitmap) { bitmap.recycle(); bitmap = reduced; }
            int width = bitmap.getWidth(), height = bitmap.getHeight();
            int[] argb = new int[width * height];
            bitmap.getPixels(argb, 0, width, 0, 0, width, height);
            found = new Pixels(width, height, argb);
        } finally { bitmap.recycle(); }
        pixels.put(key, found);
        if (pixels.size() > MAX_CACHED_SOURCES) {
            Map.Entry<String, Pixels> eldest = pixels.entrySet().iterator().next();
            pixels.remove(eldest.getKey());
        }
        return found;
    }

    private static Bitmap scaled(Bitmap bitmap, int edge) {
        int longest = Math.max(bitmap.getWidth(), bitmap.getHeight());
        if (longest <= edge) return bitmap;
        float scale = edge / (float) longest;
        return Bitmap.createScaledBitmap(bitmap, Math.max(1, Math.round(bitmap.getWidth() * scale)),
                Math.max(1, Math.round(bitmap.getHeight() * scale)), true);
    }

    private static String sha256(byte[] bytes) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(bytes);
            StringBuilder hex = new StringBuilder(64);
            for (byte value : digest) hex.append(String.format(Locale.ROOT, "%02x", value & 255));
            return hex.toString();
        } catch (NoSuchAlgorithmException impossible) { throw new AssertionError(impossible); }
    }

    private static int[] pool(String category) {
        String value = category == null ? "" : category.trim().toLowerCase(Locale.ROOT);
        if (value.equals("人像") || value.equals("portrait")) return PORTRAIT;
        if (value.equals("风景") || value.equals("landscape")) return LANDSCAPE;
        if (value.equals("夜景") || value.equals("night")) return NIGHT;
        if (value.equals("日常") || value.equals("daily")) return DAILY;
        return ALL;
    }

    public static final class Source {
        public final String id, label, credit, pageUrl, version, cacheKey;
        public final boolean custom;
        private final Scene scene;
        private Source(Scene scene, boolean custom, String version) {
            this.scene = scene; this.custom = custom; this.version = version;
            id = custom ? "custom" : scene.id;
            label = custom ? "自选模板" : scene.label;
            credit = custom ? "" : scene.credit;
            pageUrl = custom ? "" : scene.pageUrl;
            cacheKey = version + ':' + id + (custom ? "" : ':' + scene.sha256);
        }
    }

    private static final class Scene {
        final String id, label, credit, pageUrl, sha256;
        Scene(String id, String label, String credit, String pageUrl, String sha256) {
            this.id = id; this.label = label; this.credit = credit; this.pageUrl = pageUrl; this.sha256 = sha256;
        }
    }
    private static final class Pixels {
        final int width, height;
        final int[] argb;
        Pixels(int width, int height, int[] argb) { this.width = width; this.height = height; this.argb = argb; }
    }
}
