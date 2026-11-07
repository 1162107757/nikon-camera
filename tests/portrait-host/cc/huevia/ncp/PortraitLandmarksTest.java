package cc.huevia.ncp;

import cc.huevia.album.PhotoEditStore;
import java.io.*;
import java.nio.ByteBuffer;
import java.nio.file.*;
import java.util.*;

/** Mesh storage and old-wire compatibility; all coordinates are synthetic local face points. */
public final class PortraitLandmarksTest {
    private static int checks;
    public static void main(String[] args) throws Exception {
        PhotoPortrait.Face plain = face();
        check(plain.landmarks == null, "old constructor keeps optional mesh absent");
        double[] supplied = synthetic();
        double first = supplied[0], last = supplied[supplied.length - 1];
        PhotoPortrait.Landmarks mesh = new PhotoPortrait.Landmarks(supplied);
        supplied[0] = 7.9;
        check(mesh.x(0) == first && mesh.y(467) == last, "mesh copies constructor points and exposes indexed pairs");
        double[] returned = mesh.copyPoints();returned[1] = 7.9;
        check(mesh.y(0) != 7.9 && Arrays.equals(mesh.copyPoints(), synthetic()), "mesh returns a defensive complete copy");
        PhotoPortrait.Landmarks same = new PhotoPortrait.Landmarks(synthetic());
        check(mesh.equals(same) && same.equals(mesh) && mesh.hashCode() == same.hashCode(), "mesh value equality and hash");
        double[] changed = synthetic();changed[219] += .01;
        check(!mesh.equals(new PhotoPortrait.Landmarks(changed)) && !mesh.equals(null), "point changes affect equality");
        double[] zeros = new double[936], signedZeros = new double[936];signedZeros[5] = -0.0;
        check(new PhotoPortrait.Landmarks(zeros).equals(new PhotoPortrait.Landmarks(signedZeros)), "mesh signed zero is canonical");
        double[] extremes = synthetic();extremes[0] = -8;extremes[935] = 8;
        PhotoPortrait.Landmarks bounded = new PhotoPortrait.Landmarks(extremes);
        check(bounded.x(0) == -8 && bounded.y(467) == 8, "inclusive local coordinate bounds");
        expectInvalid(() -> new PhotoPortrait.Landmarks(null), "null mesh rejected");
        expectInvalid(() -> new PhotoPortrait.Landmarks(new double[934]), "short mesh rejected");
        expectInvalid(() -> new PhotoPortrait.Landmarks(new double[938]), "long mesh rejected");
        for (double bad : new double[]{Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY, -8.00001, 8.00001}) {
            double[] invalid = synthetic();invalid[437] = bad;
            expectInvalid(() -> new PhotoPortrait.Landmarks(invalid), "nonfinite or out-of-range point rejected");
        }
        for (int bad : new int[]{-1,468,Integer.MIN_VALUE,Integer.MAX_VALUE}) {
            expectIndex(() -> mesh.x(bad), "x index bounded");expectIndex(() -> mesh.y(bad), "y index bounded");
        }

        PhotoPortrait.Face marked = plain.withLandmarks(mesh);
        check(marked.landmarks == mesh && marked.withLandmarks(null).equals(plain), "attach and detach optional mesh without altering face");
        check(marked.equals(new PhotoPortrait.Face(plain.cx,plain.cy,plain.rx,plain.ry,plain.roll,plain.skinR,plain.skinG,plain.skinB,plain.enabled,plain.settings,plain.strokes,same)), "new constructor retains mesh value");
        check(marked.withSettings(PhotoPortrait.Settings.NONE).landmarks == mesh, "withSettings retains mesh");
        check(marked.withEnabled(false).landmarks == mesh, "withEnabled retains mesh");
        check(marked.withSkin(201,151,119).landmarks == mesh, "withSkin retains mesh");
        check(marked.withBounds(.6,.4,.12,.22,-19).landmarks == mesh, "withBounds retains local mesh coordinates");
        PhotoPortrait.Stroke stroke = new PhotoPortrait.Stroke(new double[]{.4,.45,.42,.48},.022,.6,true);
        check(marked.withStrokes(List.of(stroke)).landmarks == mesh, "withStrokes retains mesh");
        check(marked.addStroke(stroke).landmarks == mesh && marked.clearStrokes().landmarks == mesh, "stroke helpers retain mesh");
        check(!marked.equals(plain), "mesh participates in face value state");

        PhotoPortrait.Heal heal = new PhotoPortrait.Heal(.1,.2,.3,.4,.03,.7,true);
        PhotoPortrait withMesh = new PhotoPortrait(List.of(marked,plain.withBounds(.7,.51,.14,.24,9)),List.of(heal));
        byte[] encoded = bytes(withMesh);
        check(ByteBuffer.wrap(encoded).getInt(4) == 4, "writer emits portrait wire version4");
        PhotoPortrait restored = read(encoded);
        check(restored.equals(withMesh) && restored.hashCode() == withMesh.hashCode(), "mixed optional meshes roundtrip with every face field");
        check(restored.faces().get(0).landmarks.equals(mesh) && restored.faces().get(1).landmarks == null, "per-face optional mesh is unambiguous");
        check(Arrays.equals(encoded,bytes(restored)) && restored.identity().equals(withMesh.identity()), "version4 bytes and identity are canonical");
        check(withMesh.identity().startsWith("portrait-v4:") && !withMesh.identity().equals(new PhotoPortrait(List.of(plain,withMesh.faces().get(1)),List.of(heal)).identity()), "mesh participates in version4 identity");
        check(read(bytes(new PhotoPortrait(Collections.nCopies(PhotoPortrait.MAX_FACES,marked),List.of()))).faces().size() == PhotoPortrait.MAX_FACES, "maximum face count with meshes remains bounded and readable");

        PhotoPortrait legacy = new PhotoPortrait(List.of(plain.withStrokes(List.of(stroke)),plain.withBounds(.73,.41,.12,.2,21).withEnabled(false)),List.of(heal));
        byte[] version1 = legacyBytes(legacy);
        PhotoPortrait migrated = read(version1);
        check(migrated.equals(legacy), "independent version1 wire preserves all original geometry, skin, settings, strokes and heals");
        check(migrated.faces().stream().allMatch(f -> f.landmarks == null), "legacy faces gain no invented mesh");
        check(read(bytes(migrated)).equals(legacy), "version1 data can be saved in version4 without losing authored state");
        check(read(legacyBytes(PhotoPortrait.NONE)).equals(PhotoPortrait.NONE), "empty version1 remains empty");
        byte[] unknown = encoded.clone();ByteBuffer.wrap(unknown).putInt(4,5);expectIo(() -> read(unknown), "future portrait versions rejected");
        byte[] zeroVersion = encoded.clone();ByteBuffer.wrap(zeroVersion).putInt(4,0);expectIo(() -> read(zeroVersion), "unsupported old version rejected");

        PhotoPortrait one = new PhotoPortrait(List.of(marked),List.of());
        byte[] oneBytes = bytes(one);
        int meshFlag = legacyBytes(new PhotoPortrait(List.of(plain),List.of())).length - 4;
        byte[] badFlag = oneBytes.clone();badFlag[meshFlag] = 2;expectIo(() -> read(badFlag), "noncanonical mesh presence flag rejected");
        for (double bad : new double[]{Double.NaN,Double.POSITIVE_INFINITY,-8.01,8.01}) {
            byte[] invalid = oneBytes.clone();ByteBuffer.wrap(invalid).putDouble(meshFlag + 1,bad);
            expectIo(() -> read(invalid), "invalid serialized mesh coordinate rejected");
        }
        for (int length : new int[]{meshFlag,meshFlag+1,meshFlag+8,meshFlag+1+468*8,meshFlag+1+936*8-1,oneBytes.length-1}) {
            byte[] truncated = Arrays.copyOf(oneBytes,length);expectIo(() -> read(truncated), "truncated mesh payload rejected");
        }
        PhotoLocalEdits local = new PhotoLocalEdits(List.of(PhotoLocalEdits.Mask.radial(.3,.4).parameters(7,-4,8)),List.of(new PhotoLocalEdits.Clone(.1,.2,.6,.7,.03,.5,true)),withMesh);
        ByteArrayOutputStream localBytes = new ByteArrayOutputStream();local.write(new DataOutputStream(localBytes));
        PhotoLocalEdits localRead = PhotoLocalEdits.read(new DataInputStream(new ByteArrayInputStream(localBytes.toByteArray())));
        check(localRead.equals(local) && localRead.identity().equals(local.identity()), "mesh stays intact inside PhotoLocalEdits");
        ByteArrayOutputStream legacyLocal = new ByteArrayOutputStream();DataOutputStream old = new DataOutputStream(legacyLocal);old.writeInt(2);old.writeInt(0);old.writeInt(0);old.write(version1);
        check(PhotoLocalEdits.read(new DataInputStream(new ByteArrayInputStream(legacyLocal.toByteArray()))).portrait.equals(legacy), "legacy portrait version1 still reads inside local version2");
        draftRoundtrip(local,marked);
        System.out.println("PASS PortraitLandmarksTest "+checks+" checks");
    }
    private static void draftRoundtrip(PhotoLocalEdits local, PhotoPortrait.Face marked) throws Exception {
        Path temp = Files.createTempDirectory("portrait-landmarks-model-");
        try {
            PhotoEditStore store = new PhotoEditStore(temp.toFile(),"mesh-owner");String sha = "e".repeat(64);
            PhotoEditStore.Draft draft = new PhotoEditStore.Draft(sha,null,"合成关键点",0,PhotoAdjustments.NONE,PhotoGeometry.NONE,PhotoBorder.NONE,local,false);
            store.save(draft);PhotoEditStore.Draft restored = store.read(sha);
            check(restored != null && restored.localEdits.equals(local) && restored.identity().equals(draft.identity()), "persistent draft restores mesh and complete local state");
            check(restored.localEdits.portrait.faces().get(0).landmarks.equals(marked.landmarks), "persistent mesh points restore exactly");
            check(new PhotoEditStore(temp.toFile(),"another-owner").read(sha) == null, "mesh draft remains owner scoped");
            double[] changed = marked.landmarks.copyPoints();changed[0] += .01;
            PhotoLocalEdits altered = local.withPortrait(local.portrait.withFace(0,marked.withLandmarks(new PhotoPortrait.Landmarks(changed))));
            PhotoEditStore.Draft next = new PhotoEditStore.Draft(sha,null,"合成关键点",0,PhotoAdjustments.NONE,PhotoGeometry.NONE,PhotoBorder.NONE,altered,false);
            store.save(next);store.markExported(draft);
            check(!store.read(sha).exported && !store.replace(sha,draft,draft), "changed mesh prevents stale export and compare-and-replace");
            store.markExported(next);check(store.read(sha).exported && store.read(sha).localEdits.equals(altered), "matching mesh export retains new complete state");
        } finally { try (var files = Files.walk(temp)) { for (Path file : files.sorted(Comparator.reverseOrder()).toList()) Files.delete(file); } }
    }
    private static double[] synthetic() { double[] p = new double[PhotoPortrait.Landmarks.POINT_COUNT*2];for(int i=0;i<PhotoPortrait.Landmarks.POINT_COUNT;i++){p[i*2]=(i%26-12)/10.0;p[i*2+1]=(i/26-9)/10.0;}return p; }
    private static PhotoPortrait.Face face() { return new PhotoPortrait.Face(.35,.52,.18,.29,-7,196,142,116,true,new PhotoPortrait.Settings(18,-4,9,21,67,3,8),List.of(new PhotoPortrait.Stroke(new double[]{.25,.42,.3,.47},.025,.4,false))); }
    private static byte[] bytes(PhotoPortrait value) throws IOException { ByteArrayOutputStream b = new ByteArrayOutputStream();value.write(new DataOutputStream(b));return b.toByteArray(); }
    private static PhotoPortrait read(byte[] bytes) throws IOException { return PhotoPortrait.read(new DataInputStream(new ByteArrayInputStream(bytes))); }
    /** Frozen protocol1 encoder, independent of the current version4 writer. */
    private static byte[] legacyBytes(PhotoPortrait value) throws IOException {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();DataOutputStream out = new DataOutputStream(bytes);out.writeInt(0x50525431);out.writeInt(1);out.writeInt(value.faces().size());
        for (PhotoPortrait.Face f : value.faces()) {
            for (double d : new double[]{f.cx,f.cy,f.rx,f.ry,f.roll}) out.writeDouble(d);
            out.writeInt(f.skinR);out.writeInt(f.skinG);out.writeInt(f.skinB);out.writeBoolean(f.enabled);
            PhotoPortrait.Settings s = f.settings;for (int n : new int[]{s.brightness,s.warmth,s.redness,s.smoothing,s.texture,s.light,s.shadows}) out.writeInt(n);
            out.writeInt(f.strokes.size());for (PhotoPortrait.Stroke stroke : f.strokes) {out.writeDouble(stroke.radius);out.writeDouble(stroke.feather);out.writeBoolean(stroke.erase);double[] points=stroke.points();out.writeInt(points.length);for(double p:points)out.writeDouble(p);}
        }
        out.writeInt(value.heals().size());for (PhotoPortrait.Heal h : value.heals()) {for (double d : new double[]{h.sx,h.sy,h.tx,h.ty,h.radius,h.feather}) out.writeDouble(d);out.writeBoolean(h.enabled);}return bytes.toByteArray();
    }
    private interface Action { void run() throws Exception; }
    private static void expectIo(Action action,String message) throws Exception {try{action.run();throw new AssertionError(message);}catch(IOException expected){checks++;}}
    private static void expectInvalid(Action action,String message) throws Exception {try{action.run();throw new AssertionError(message);}catch(IllegalArgumentException expected){checks++;}}
    private static void expectIndex(Action action,String message) throws Exception {try{action.run();throw new AssertionError(message);}catch(IndexOutOfBoundsException expected){checks++;}}
    private static void check(boolean value,String message) { checks++;if(!value)throw new AssertionError(message); }
}
