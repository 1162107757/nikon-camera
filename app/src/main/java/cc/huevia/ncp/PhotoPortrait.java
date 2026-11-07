package cc.huevia.ncp;

import java.io.ByteArrayOutputStream;
import java.io.DataInput;
import java.io.DataOutput;
import java.io.DataOutputStream;
import java.io.IOException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Objects;

/** Immutable portrait adjustments in the oriented source frame, before crop or perspective. */
public final class PhotoPortrait {
    private static final int MAGIC = 0x50525431, VERSION = 7;
    public static final int MAX_FACES = 12, MAX_HEALS = 64, MAX_STROKES = 32, MAX_STROKE_POINTS = 512;
    public static final int MAX_TOTAL_STROKES = 64, MAX_TOTAL_POINTS = 8192;
    public static final PhotoPortrait NONE = new PhotoPortrait(Collections.emptyList(), Collections.emptyList());
    private final List<Face> faces;
    private final List<Heal> heals;
    public final Tone globalTone;
    public final BodySkinMask globalSkinMask;
    public final PhotoBodyShape bodyShape;
    /** Whole exposed-skin retouch, independent of selected faces and skin colour. */
    public final int skinSmoothing;
    public final PortraitRetouch retouch;
    private volatile String identity;

    public PhotoPortrait(List<Face> faces, List<Heal> heals) {
        this(faces, heals, Tone.NONE, null, PhotoBodyShape.NONE, 0, PortraitRetouch.NONE);
    }
    private PhotoPortrait(List<Face> faces, List<Heal> heals, Tone globalTone, BodySkinMask globalSkinMask, PhotoBodyShape bodyShape, int skinSmoothing, PortraitRetouch retouch) {
        this.retouch = Objects.requireNonNull(retouch);
        if (skinSmoothing < 0 || skinSmoothing > 100) throw new IllegalArgumentException("磨皮强度无效。");
        this.skinSmoothing = skinSmoothing;
        this.bodyShape = Objects.requireNonNull(bodyShape, "bodyShape");
        this.faces = list(faces, MAX_FACES, "faces");
        this.heals = list(heals, MAX_HEALS, "heals");
        this.globalTone = Objects.requireNonNull(globalTone, "globalTone"); this.globalSkinMask = globalSkinMask;
        if (!globalTone.isNeutral()) for (Face face : this.faces) if (!face.tone.isNeutral()) throw new IllegalArgumentException("全局肤色与人物肤色不可叠加。");
        int strokes = 0, points = 0;
        for (Face face : this.faces) for (Stroke stroke : face.strokes) {
            strokes++; points += stroke.points.length / 2;
            if (strokes > MAX_TOTAL_STROKES || points > MAX_TOTAL_POINTS) throw new IllegalArgumentException("人像笔触总量超限。");
        }
    }
    public List<Face> faces() { return faces; }
    public List<Heal> heals() { return heals; }
    public PhotoPortrait withFaces(List<Face> values) { Objects.requireNonNull(values, "faces"); Tone mode = globalTone; for (Face face : values) if (!Objects.requireNonNull(face).tone.isNeutral()) mode = Tone.NONE; return new PhotoPortrait(values, heals, mode, globalSkinMask, bodyShape, skinSmoothing, retouch); }
    public PhotoPortrait withFace(int index, Face face) { ArrayList<Face> values = new ArrayList<>(faces); values.set(index, Objects.requireNonNull(face)); return withFaces(values); }
    public PhotoPortrait addFace(Face face) { ArrayList<Face> values = new ArrayList<>(faces); values.add(Objects.requireNonNull(face)); return withFaces(values); }
    public PhotoPortrait removeFace(int index) { ArrayList<Face> values = new ArrayList<>(faces); values.remove(index); return new PhotoPortrait(values, heals, globalTone, globalSkinMask, bodyShape, skinSmoothing, retouch); }
    public PhotoPortrait addHeal(Heal heal) { ArrayList<Heal> values = new ArrayList<>(heals); values.add(Objects.requireNonNull(heal)); return new PhotoPortrait(faces, values, globalTone, globalSkinMask, bodyShape, skinSmoothing, retouch); }
    public PhotoPortrait removeHeal(int index) { ArrayList<Heal> values = new ArrayList<>(heals); values.remove(index); return new PhotoPortrait(faces, values, globalTone, globalSkinMask, bodyShape, skinSmoothing, retouch); }
    /** Choosing the whole-image tool replaces prior per-person target colours, including at zero strength. */
    public PhotoPortrait withGlobalTone(Tone value) { Objects.requireNonNull(value, "globalTone"); ArrayList<Face> cleared = new ArrayList<>(faces.size()); for (Face face : faces) cleared.add(face.tone.equals(Tone.NONE) ? face : face.withTone(Tone.NONE)); return new PhotoPortrait(cleared, heals, value, globalSkinMask, bodyShape, skinSmoothing, retouch); }
    public PhotoPortrait withGlobalSkinMask(BodySkinMask value) { return new PhotoPortrait(faces, heals, globalTone, value, bodyShape, skinSmoothing, retouch); }
    public PhotoPortrait withBodyShape(PhotoBodyShape value) { return new PhotoPortrait(faces, heals, globalTone, globalSkinMask, value, skinSmoothing, retouch); }
    public PhotoPortrait withSkinSmoothing(int value) { return new PhotoPortrait(faces, heals, globalTone, globalSkinMask, bodyShape, value, retouch); }
    public PhotoPortrait withRetouch(PortraitRetouch value) { return new PhotoPortrait(faces,heals,globalTone,globalSkinMask,bodyShape,skinSmoothing,value); }
    public boolean hasRetouchState(){if(bodyShape.hasProtectionState()||retouch.hasStoredState())return true;for(Face f:faces)if(f.retouch.hasStoredState())return true;return false;}
    public boolean isEmpty() { return !retouch.hasStoredState() && skinSmoothing == 0 && !bodyShape.hasStoredState() && faces.isEmpty() && heals.isEmpty() && globalTone.equals(Tone.NONE) && globalSkinMask == null; }
    public boolean isNeutral() {
        if (!bodyShape.isNeutral()) return false;
        if ((skinSmoothing > 0 || retouch.hasSkinEffect() || !globalTone.isNeutral()) && globalSkinMask != null) return false;
        for (Face face : faces) if (face.enabled && (!face.settings.isNeutral() || !face.tone.isNeutral() || face.retouch.hasFaceEffect())) return false;
        for (Heal heal : heals) if (heal.enabled && (heal.sx != heal.tx || heal.sy != heal.ty)) return false;
        return true;
    }
    public String identity() {
        String ready = identity;
        if (ready != null) return ready;
        try {
            ByteArrayOutputStream bytes = new ByteArrayOutputStream();
            write(new DataOutputStream(bytes));
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(bytes.toByteArray());
            StringBuilder key = new StringBuilder(hasRetouchState()?"portrait-v7:":skinSmoothing>0?"portrait-v6:":bodyShape.hasStoredState()?"portrait-v5:":"portrait-v4:");
            for (byte value : digest) key.append(Character.forDigit((value >>> 4) & 15, 16)).append(Character.forDigit(value & 15, 16));
            return identity = key.toString();
        } catch (IOException impossible) { throw new AssertionError(impossible); }
        catch (NoSuchAlgorithmException impossible) { throw new AssertionError(impossible); }
    }
    public void write(DataOutput output) throws IOException {
        int version = hasRetouchState() ? 7 : skinSmoothing > 0 ? 6 : bodyShape.hasStoredState() ? 5 : 4;
        output.writeInt(MAGIC); output.writeInt(version); output.writeInt(faces.size());
        for (Face face : faces) {
            output.writeDouble(face.cx); output.writeDouble(face.cy); output.writeDouble(face.rx); output.writeDouble(face.ry); output.writeDouble(face.roll);
            output.writeInt(face.skinR); output.writeInt(face.skinG); output.writeInt(face.skinB); output.writeBoolean(face.enabled);
            Settings s = face.settings;
            output.writeInt(s.brightness); output.writeInt(s.warmth); output.writeInt(s.redness); output.writeInt(s.smoothing); output.writeInt(s.texture); output.writeInt(s.light); output.writeInt(s.shadows);
            output.writeInt(face.strokes.size());
            for (Stroke stroke : face.strokes) {
                output.writeDouble(stroke.radius); output.writeDouble(stroke.feather); output.writeBoolean(stroke.erase); output.writeInt(stroke.points.length);
                for (double point : stroke.points) output.writeDouble(point);
            }
            output.writeBoolean(face.landmarks != null);
            if (face.landmarks != null) for (double point : face.landmarks.points) output.writeDouble(point);
            output.writeBoolean(face.skinMask != null);
            if (face.skinMask != null) {
                output.writeDouble(face.skinMask.left); output.writeDouble(face.skinMask.top); output.writeDouble(face.skinMask.right); output.writeDouble(face.skinMask.bottom);
                output.write(face.skinMask.coverage);
            }
            output.writeInt(face.tone.presetId); output.writeInt(face.tone.colorRGB);
            output.writeDouble(face.tone.amount); output.writeBoolean(face.tone.body);
            output.writeBoolean(face.bodySkinMask != null);
            if (face.bodySkinMask != null) output.write(face.bodySkinMask.coverage);
        }
        output.writeInt(heals.size());
        for (Heal heal : heals) {
            output.writeDouble(heal.sx); output.writeDouble(heal.sy); output.writeDouble(heal.tx); output.writeDouble(heal.ty);
            output.writeDouble(heal.radius); output.writeDouble(heal.feather); output.writeBoolean(heal.enabled);
        }
        output.writeInt(globalTone.presetId); output.writeInt(globalTone.colorRGB); output.writeDouble(globalTone.amount); output.writeBoolean(globalTone.body);
        output.writeBoolean(globalSkinMask != null); if (globalSkinMask != null) output.write(globalSkinMask.coverage);
        if (version >= 5) bodyShape.write(output);
        if (version >= 6) output.writeInt(skinSmoothing);
        if (version >= 7) {retouch.write(output);for(Face face:faces)face.retouch.write(output);output.writeBoolean(bodyShape.backgroundMask!=null);if(bodyShape.backgroundMask!=null)output.write(bodyShape.backgroundMask.copyCoverage());output.writeInt(bodyShape.backgroundProtection);}
    }
    public static PhotoPortrait read(DataInput input) throws IOException {
        try {
            if (input.readInt() != MAGIC) throw new IOException("人像编辑版本无效。");
            int version = input.readInt();
            if (version < 1 || version > VERSION) throw new IOException("人像编辑版本无效。");
            int count = count(input.readInt(), MAX_FACES);
            ArrayList<Face> faces = new ArrayList<>(count);
            int totalStrokes = 0, totalPoints = 0;
            for (int i = 0; i < count; i++) {
                double cx = input.readDouble(), cy = input.readDouble(), rx = input.readDouble(), ry = input.readDouble(), roll = input.readDouble();
                int r = input.readInt(), g = input.readInt(), b = input.readInt(); boolean enabled = readBoolean(input);
                Settings settings = new Settings(input.readInt(), input.readInt(), input.readInt(), input.readInt(), input.readInt(), input.readInt(), input.readInt());
                int strokesCount = count(input.readInt(), MAX_STROKES);
                totalStrokes += strokesCount;
                if (totalStrokes > MAX_TOTAL_STROKES) throw new IOException("人像笔触总量超限。");
                ArrayList<Stroke> strokes = new ArrayList<>(strokesCount);
                for (int j = 0; j < strokesCount; j++) {
                    double radius = input.readDouble(), feather = input.readDouble(); boolean erase = readBoolean(input);
                    int pointsCount = count(input.readInt(), MAX_STROKE_POINTS * 2);
                    if (pointsCount < 2 || (pointsCount & 1) != 0) throw new IOException("人像笔触点无效。");
                    totalPoints += pointsCount / 2;
                    if (totalPoints > MAX_TOTAL_POINTS) throw new IOException("人像笔触点总量超限。");
                    double[] points = new double[pointsCount]; for (int k = 0; k < points.length; k++) points[k] = input.readDouble();
                    strokes.add(new Stroke(points, radius, feather, erase));
                }
                Landmarks landmarks = null;
                if (version >= 2 && readBoolean(input)) {
                    double[] points = new double[Landmarks.POINT_COUNT * 2];
                    for (int j = 0; j < points.length; j++) points[j] = input.readDouble();
                    landmarks = new Landmarks(points);
                }
                SkinMask skinMask = null;
                if (version >= 2 && readBoolean(input)) {
                    double left = input.readDouble(), top = input.readDouble(), right = input.readDouble(), bottom = input.readDouble();
                    byte[] coverage = new byte[SkinMask.SIZE * SkinMask.SIZE]; input.readFully(coverage);
                    skinMask = new SkinMask(left, top, right, bottom, coverage);
                }
                Tone tone = version >= 3 ? new Tone(input.readInt(), input.readInt(), input.readDouble(), readBoolean(input)) : Tone.NONE;
                BodySkinMask bodySkinMask = null;
                if (version >= 3 && readBoolean(input)) {
                    byte[] coverage = new byte[BodySkinMask.SIZE * BodySkinMask.SIZE]; input.readFully(coverage);
                    bodySkinMask = new BodySkinMask(coverage);
                }
                faces.add(new Face(cx, cy, rx, ry, roll, r, g, b, enabled, settings, strokes, landmarks, skinMask, tone, bodySkinMask));
            }
            int healsCount = count(input.readInt(), MAX_HEALS);
            ArrayList<Heal> heals = new ArrayList<>(healsCount);
            for (int i = 0; i < healsCount; i++) heals.add(new Heal(input.readDouble(), input.readDouble(), input.readDouble(), input.readDouble(), input.readDouble(), input.readDouble(), readBoolean(input)));
            Tone globalTone = version >= 4 ? new Tone(input.readInt(), input.readInt(), input.readDouble(), readBoolean(input)) : Tone.NONE;
            BodySkinMask globalSkinMask = null;
            if (version >= 4 && readBoolean(input)) { byte[] coverage = new byte[BodySkinMask.SIZE * BodySkinMask.SIZE]; input.readFully(coverage); globalSkinMask = new BodySkinMask(coverage); }
            PhotoBodyShape shape = version >= 5 ? PhotoBodyShape.read(input) : PhotoBodyShape.NONE;
            int smoothing=version>=6?input.readInt():0;PortraitRetouch retouch=version>=7?PortraitRetouch.read(input):PortraitRetouch.NONE;
            if(version>=7)for(int i=0;i<faces.size();i++)faces.set(i,faces.get(i).withRetouch(PortraitRetouch.read(input)));
            if(version>=7){BodySkinMask protection=null;if(readBoolean(input)){byte[] coverage=new byte[BodySkinMask.SIZE*BodySkinMask.SIZE];input.readFully(coverage);protection=new BodySkinMask(coverage);}shape=shape.withBackgroundProtection(protection,input.readInt());}
            return new PhotoPortrait(faces, heals, globalTone, globalSkinMask, shape, smoothing, retouch);
        } catch (IllegalArgumentException | NullPointerException invalid) { throw new IOException("人像编辑数据无效。", invalid); }
    }
    private static boolean readBoolean(DataInput input) throws IOException { int value = input.readUnsignedByte(); if (value > 1) throw new IOException("人像编辑开关无效。"); return value == 1; }
    private static int count(int value, int max) throws IOException { if (value < 0 || value > max) throw new IOException("人像编辑数量超限。"); return value; }
    @Override public boolean equals(Object other) { return other instanceof PhotoPortrait && faces.equals(((PhotoPortrait) other).faces) && heals.equals(((PhotoPortrait) other).heals) && globalTone.equals(((PhotoPortrait) other).globalTone) && Objects.equals(globalSkinMask, ((PhotoPortrait) other).globalSkinMask) && bodyShape.equals(((PhotoPortrait) other).bodyShape) && skinSmoothing == ((PhotoPortrait) other).skinSmoothing && retouch.equals(((PhotoPortrait) other).retouch); }
    @Override public int hashCode() { return hasRetouchState()?Objects.hash(faces,heals,globalTone,globalSkinMask,bodyShape,skinSmoothing,retouch):skinSmoothing>0?Objects.hash(faces, heals, globalTone, globalSkinMask, bodyShape, skinSmoothing):bodyShape.hasStoredState()?Objects.hash(faces, heals, globalTone, globalSkinMask, bodyShape):Objects.hash(faces, heals, globalTone, globalSkinMask); }

    public static final class Settings {
        public static final Settings NONE = new Settings(0, 0, 0, 0, 70, 0, 0);
        public final int brightness, warmth, redness, smoothing, texture, light, shadows;
        public Settings(int brightness, int warmth, int redness, int smoothing, int texture, int light, int shadows) {
            this.brightness = amount(brightness, -100); this.warmth = amount(warmth, -100); this.redness = amount(redness, -100);
            this.smoothing = amount(smoothing, 0); this.texture = amount(texture, 0); this.light = amount(light, -100); this.shadows = amount(shadows, 0);
        }
        public boolean isNeutral() { return brightness == 0 && warmth == 0 && redness == 0 && smoothing == 0 && light == 0 && shadows == 0; }
        @Override public boolean equals(Object other) { if (!(other instanceof Settings)) return false; Settings s = (Settings) other; return brightness == s.brightness && warmth == s.warmth && redness == s.redness && smoothing == s.smoothing && texture == s.texture && light == s.light && shadows == s.shadows; }
        @Override public int hashCode() { return Objects.hash(brightness, warmth, redness, smoothing, texture, light, shadows); }
        private static int amount(int value, int min) { if (value < min || value > 100) throw new IllegalArgumentException("人像调节超出范围。"); return value; }
    }
    public static final class Face {
        public final double cx, cy, rx, ry, roll;
        public final int skinR, skinG, skinB;
        public final boolean enabled;
        public final Settings settings;
        public final List<Stroke> strokes;
        public final Landmarks landmarks;
        public final SkinMask skinMask;
        public final Tone tone;
        public final BodySkinMask bodySkinMask;
        public final PortraitRetouch retouch;
        public Face(double cx, double cy, double rx, double ry, double roll, int skinR, int skinG, int skinB, boolean enabled, Settings settings, List<Stroke> strokes) {
            this(cx, cy, rx, ry, roll, skinR, skinG, skinB, enabled, settings, strokes, null, null);
        }
        public Face(double cx, double cy, double rx, double ry, double roll, int skinR, int skinG, int skinB, boolean enabled, Settings settings, List<Stroke> strokes, Landmarks landmarks) {
            this(cx, cy, rx, ry, roll, skinR, skinG, skinB, enabled, settings, strokes, landmarks, null);
        }
        public Face(double cx, double cy, double rx, double ry, double roll, int skinR, int skinG, int skinB, boolean enabled, Settings settings, List<Stroke> strokes, Landmarks landmarks, SkinMask skinMask) {
            this(cx, cy, rx, ry, roll, skinR, skinG, skinB, enabled, settings, strokes, landmarks, skinMask, Tone.NONE, null);
        }
        public Face(double cx, double cy, double rx, double ry, double roll, int skinR, int skinG, int skinB, boolean enabled, Settings settings, List<Stroke> strokes, Landmarks landmarks, SkinMask skinMask, Tone tone, BodySkinMask bodySkinMask) {
            this(cx,cy,rx,ry,roll,skinR,skinG,skinB,enabled,settings,strokes,landmarks,skinMask,tone,bodySkinMask,PortraitRetouch.NONE);
        }
        public Face(double cx, double cy, double rx, double ry, double roll, int skinR, int skinG, int skinB, boolean enabled, Settings settings, List<Stroke> strokes, Landmarks landmarks, SkinMask skinMask, Tone tone, BodySkinMask bodySkinMask, PortraitRetouch retouch) {
            this.cx = unit(cx); this.cy = unit(cy); this.rx = radius(rx); this.ry = radius(ry);
            if (!Double.isFinite(roll) || roll < -180 || roll > 180) throw new IllegalArgumentException("人脸角度无效。");
            this.roll = zero(roll); this.skinR = channel(skinR); this.skinG = channel(skinG); this.skinB = channel(skinB);
            this.enabled = enabled; this.settings = Objects.requireNonNull(settings, "settings"); this.strokes = list(strokes, MAX_STROKES, "strokes");
            this.landmarks = landmarks;
            this.skinMask = skinMask;
            this.tone = Objects.requireNonNull(tone, "tone");
            this.bodySkinMask = bodySkinMask; this.retouch = Objects.requireNonNull(retouch);
            int points = 0; for (Stroke stroke : this.strokes) points += stroke.points.length / 2;
            if (points > MAX_TOTAL_POINTS) throw new IllegalArgumentException("人脸笔触点总量超限。");
        }
        public Face withSettings(Settings value) { return new Face(cx, cy, rx, ry, roll, skinR, skinG, skinB, enabled, value, strokes, landmarks, skinMask, tone, bodySkinMask, retouch); }
        public Face withEnabled(boolean value) { return new Face(cx, cy, rx, ry, roll, skinR, skinG, skinB, value, settings, strokes, landmarks, skinMask, tone, bodySkinMask, retouch); }
        public Face withSkin(int r, int g, int b) { return new Face(cx, cy, rx, ry, roll, r, g, b, enabled, settings, strokes, landmarks, skinMask, tone, bodySkinMask, retouch); }
        public Face withBounds(double x, double y, double xr, double yr, double angle) { return new Face(x, y, xr, yr, angle, skinR, skinG, skinB, enabled, settings, strokes, landmarks, skinMask, tone, bodySkinMask, retouch); }
        public Face withStrokes(List<Stroke> value) { return new Face(cx, cy, rx, ry, roll, skinR, skinG, skinB, enabled, settings, value, landmarks, skinMask, tone, bodySkinMask, retouch); }
        public Face withLandmarks(Landmarks value) { return new Face(cx, cy, rx, ry, roll, skinR, skinG, skinB, enabled, settings, strokes, value, skinMask, tone, bodySkinMask, retouch); }
        public Face withSkinMask(SkinMask value) { return new Face(cx, cy, rx, ry, roll, skinR, skinG, skinB, enabled, settings, strokes, landmarks, value, tone, bodySkinMask, retouch); }
        public Face withTone(Tone value) { return new Face(cx, cy, rx, ry, roll, skinR, skinG, skinB, enabled, settings, strokes, landmarks, skinMask, value, bodySkinMask, retouch); }
        public Face withBodySkinMask(BodySkinMask value) { return new Face(cx, cy, rx, ry, roll, skinR, skinG, skinB, enabled, settings, strokes, landmarks, skinMask, tone, value, retouch); }
        public Face withRetouch(PortraitRetouch value){return new Face(cx,cy,rx,ry,roll,skinR,skinG,skinB,enabled,settings,strokes,landmarks,skinMask,tone,bodySkinMask,value);}
        public Face addStroke(Stroke value) { ArrayList<Stroke> values = new ArrayList<>(strokes); values.add(Objects.requireNonNull(value)); return withStrokes(values); }
        public Face clearStrokes() { return withStrokes(Collections.emptyList()); }
        @Override public boolean equals(Object other) { if (!(other instanceof Face)) return false; Face f = (Face) other; return cx == f.cx && cy == f.cy && rx == f.rx && ry == f.ry && roll == f.roll && skinR == f.skinR && skinG == f.skinG && skinB == f.skinB && enabled == f.enabled && settings.equals(f.settings) && strokes.equals(f.strokes) && Objects.equals(landmarks, f.landmarks) && Objects.equals(skinMask, f.skinMask) && tone.equals(f.tone) && Objects.equals(bodySkinMask, f.bodySkinMask) && retouch.equals(f.retouch); }
        @Override public int hashCode() { return retouch.hasStoredState()?Objects.hash(cx,cy,rx,ry,roll,skinR,skinG,skinB,enabled,settings,strokes,landmarks,skinMask,tone,bodySkinMask,retouch):Objects.hash(cx, cy, rx, ry, roll, skinR, skinG, skinB, enabled, settings, strokes, landmarks, skinMask, tone, bodySkinMask); }
    }
    /** A target colour and its independent, reversible strength for one person. */
    public static final class Tone {
        public static final Tone NONE = new Tone(0, 0, 0, false);
        public final int presetId, colorRGB;
        public final double amount;
        public final boolean body;
        public Tone(int presetId, int colorRGB, double amount, boolean body) {
            if (presetId < 0 || presetId > 10 || colorRGB < 0 || colorRGB > 0xffffff || !Double.isFinite(amount) || amount < 0 || amount > 1)
                throw new IllegalArgumentException("肤色设置无效。");
            // Avoid initializing PhotoPortrait while Tone.NONE itself is still being created.
            this.presetId = presetId; this.colorRGB = colorRGB; this.amount = amount == 0 ? 0 : amount; this.body = body;
        }
        public boolean isNeutral() { return presetId == 0 || amount == 0; }
        @Override public boolean equals(Object other) { if (!(other instanceof Tone)) return false; Tone t = (Tone) other; return presetId == t.presetId && colorRGB == t.colorRGB && amount == t.amount && body == t.body; }
        @Override public int hashCode() { return Objects.hash(presetId, colorRGB, amount, body); }
    }
    /** Person-owned body-skin confidence, in the full oriented image (not the face frame). */
    public static final class BodySkinMask {
        public static final int SIZE = 128;
        private final byte[] coverage;
        public BodySkinMask(byte[] coverage) {
            if (coverage == null || coverage.length != SIZE * SIZE) throw new IllegalArgumentException("身体皮肤蒙版尺寸无效。");
            this.coverage = coverage.clone();
        }
        public byte[] copyCoverage() { return coverage.clone(); }
        public double weight(double nx, double ny) {
            if (!Double.isFinite(nx) || !Double.isFinite(ny) || nx < 0 || nx > 1 || ny < 0 || ny > 1) return 0;
            double gx = nx * SIZE - .5, gy = ny * SIZE - .5;
            int ix = (int) Math.floor(gx), iy = (int) Math.floor(gy);
            double tx = gx - ix, ty = gy - iy;
            int x0 = Math.max(0, Math.min(SIZE - 1, ix)), x1 = Math.max(0, Math.min(SIZE - 1, ix + 1));
            int y0 = Math.max(0, Math.min(SIZE - 1, iy)), y1 = Math.max(0, Math.min(SIZE - 1, iy + 1));
            double a = coverage[y0 * SIZE + x0] & 255, b = coverage[y0 * SIZE + x1] & 255;
            double c = coverage[y1 * SIZE + x0] & 255, d = coverage[y1 * SIZE + x1] & 255;
            return ((a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty) / 255;
        }
        @Override public boolean equals(Object other) { return other instanceof BodySkinMask && Arrays.equals(coverage, ((BodySkinMask) other).coverage); }
        @Override public int hashCode() { return Arrays.hashCode(coverage); }
    }
    /** Immutable face-mesh points in the face's local, eye-distance-aligned u/v frame. */
    public static final class Landmarks {
        public static final int POINT_COUNT = 468;
        private final double[] points;
        public Landmarks(double[] points) {
            if (points == null || points.length != POINT_COUNT * 2) throw new IllegalArgumentException("人脸关键点数量无效。");
            this.points = points.clone();
            for (int i = 0; i < this.points.length; i++) {
                double value = this.points[i];
                if (!Double.isFinite(value) || value < -8 || value > 8) throw new IllegalArgumentException("人脸关键点坐标无效。");
                this.points[i] = zero(value);
            }
        }
        public double x(int index) { return points[coordinate(index)]; }
        public double y(int index) { return points[coordinate(index) + 1]; }
        public double[] copyPoints() { return points.clone(); }
        private static int coordinate(int index) { if (index < 0 || index >= POINT_COUNT) throw new IndexOutOfBoundsException("人脸关键点索引无效。"); return index * 2; }
        @Override public boolean equals(Object other) { return other instanceof Landmarks && Arrays.equals(points, ((Landmarks) other).points); }
        @Override public int hashCode() { return Arrays.hashCode(points); }
    }
    /** Immutable semantic face-skin confidence raster, in the same local frame as landmarks. */
    public static final class SkinMask {
        public static final int SIZE = 128;
        public final double left, top, right, bottom;
        private final byte[] coverage;
        public SkinMask(double left, double top, double right, double bottom, byte[] coverage) {
            this.left = bound(left); this.top = bound(top); this.right = bound(right); this.bottom = bound(bottom);
            if (this.left >= this.right || this.top >= this.bottom) throw new IllegalArgumentException("皮肤蒙版范围无效。");
            if (coverage == null || coverage.length != SIZE * SIZE) throw new IllegalArgumentException("皮肤蒙版尺寸无效。");
            this.coverage = coverage.clone();
        }
        public byte[] copyCoverage() { return coverage.clone(); }
        public double weight(double u, double v) {
            if (!Double.isFinite(u) || !Double.isFinite(v) || u < left || u > right || v < top || v > bottom) return 0;
            double gx = (u - left) / (right - left) * SIZE - .5, gy = (v - top) / (bottom - top) * SIZE - .5;
            int ix = (int) Math.floor(gx), iy = (int) Math.floor(gy);
            double tx = gx - ix, ty = gy - iy;
            int x0 = clampIndex(ix), x1 = clampIndex(ix + 1), y0 = clampIndex(iy), y1 = clampIndex(iy + 1);
            double a = coverage[y0 * SIZE + x0] & 255, b = coverage[y0 * SIZE + x1] & 255;
            double c = coverage[y1 * SIZE + x0] & 255, d = coverage[y1 * SIZE + x1] & 255;
            return ((a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty) / 255;
        }
        private static double bound(double value) { if (!Double.isFinite(value) || value < -8 || value > 8) throw new IllegalArgumentException("皮肤蒙版坐标无效。"); return zero(value); }
        private static int clampIndex(int value) { return Math.max(0, Math.min(SIZE - 1, value)); }
        @Override public boolean equals(Object other) { if (!(other instanceof SkinMask)) return false; SkinMask s = (SkinMask) other; return left == s.left && top == s.top && right == s.right && bottom == s.bottom && Arrays.equals(coverage, s.coverage); }
        @Override public int hashCode() { return Objects.hash(left, top, right, bottom, Arrays.hashCode(coverage)); }
    }
    public static final class Stroke {
        private final double[] points;
        public final double radius, feather;
        public final boolean erase;
        public Stroke(double[] points, double radius, double feather, boolean erase) {
            if (points == null || points.length < 2 || points.length > MAX_STROKE_POINTS * 2 || (points.length & 1) != 0) throw new IllegalArgumentException("人像笔触点无效。");
            this.points = points.clone(); for (int i = 0; i < this.points.length; i++) this.points[i] = unit(this.points[i]);
            this.radius = radius(radius); this.feather = unit(feather); this.erase = erase;
        }
        public double[] points() { return points.clone(); }
        @Override public boolean equals(Object other) { if (!(other instanceof Stroke)) return false; Stroke s = (Stroke) other; return radius == s.radius && feather == s.feather && erase == s.erase && Arrays.equals(points, s.points); }
        @Override public int hashCode() { return Objects.hash(radius, feather, erase, Arrays.hashCode(points)); }
    }
    public static final class Heal {
        public final double sx, sy, tx, ty, radius, feather;
        public final boolean enabled;
        public Heal(double sx, double sy, double tx, double ty, double radius, double feather, boolean enabled) {
            this.sx = unit(sx); this.sy = unit(sy); this.tx = unit(tx); this.ty = unit(ty); this.radius = radius(radius); this.feather = unit(feather); this.enabled = enabled;
        }
        @Override public boolean equals(Object other) { if (!(other instanceof Heal)) return false; Heal h = (Heal) other; return sx == h.sx && sy == h.sy && tx == h.tx && ty == h.ty && radius == h.radius && feather == h.feather && enabled == h.enabled; }
        @Override public int hashCode() { return Objects.hash(sx, sy, tx, ty, radius, feather, enabled); }
    }
    private static double unit(double value) { if (!Double.isFinite(value) || value < 0 || value > 1) throw new IllegalArgumentException("人像编辑坐标无效。"); return zero(value); }
    private static double radius(double value) { if (!Double.isFinite(value) || value <= 0 || value > 1) throw new IllegalArgumentException("人像编辑半径无效。"); return value; }
    private static double zero(double value) { return value == 0 ? 0 : value; }
    private static int channel(int value) { if (value < 0 || value > 255) throw new IllegalArgumentException("肤色采样无效。"); return value; }
    private static <T> List<T> list(List<T> values, int maximum, String name) {
        Objects.requireNonNull(values, name); if (values.size() > maximum) throw new IllegalArgumentException("人像编辑数量超限。");
        ArrayList<T> copy = new ArrayList<>(values); for (T value : copy) Objects.requireNonNull(value, name);
        return Collections.unmodifiableList(copy);
    }
}
