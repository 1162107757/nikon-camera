package cc.huevia.ncp;

import cc.huevia.library.PresetFile;
import cc.huevia.picturecontrol.PictureControlWriteValidation;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.Arrays;

/** Real Nikon baselines plus explicitly synthetic non-default and malformed cases. */
public final class Np2SupportTest {
    private static int checks;
    private static void yes(boolean value) { checks++; if (!value) throw new AssertionError("NP2 check " + checks); }
    private interface Action { void run() throws Exception; }
    private static void rejects(Action action) throws Exception {
        checks++; try { action.run(); } catch (IOException expected) { return; }
        throw new AssertionError("Unsupported NP2 accepted");
    }

    public static byte[] replace(byte[] source, long id, byte[] value) throws IOException {
        Np3Container file = Np3Container.read(source);
        ByteArrayOutputStream out = new ByteArrayOutputStream(); out.write(new byte[]{'N','C','P',0});
        boolean written = false;
        for (long tag : file.recordIds()) {
            if (tag == id) { record(out, tag, value); written = true; }
            else record(out, tag, file.record(tag));
        }
        if (!written) record(out, id, value);
        out.write(new byte[4]); return out.toByteArray();
    }
    private static void record(ByteArrayOutputStream out, long id, byte[] value) throws IOException {
        for (long v : new long[]{id, value.length})
            out.write(new byte[]{(byte)(v>>>24),(byte)(v>>>16),(byte)(v>>>8),(byte)v});
        out.write(value);
    }
    public static byte[] scalar(byte[] source, int index, int number) throws IOException {
        return replace(source, index * 0x100L, new byte[]{(byte)(128 + number),4});
    }
    private static CameraPresetProjection.Plan valid(byte[] source) throws Exception {
        byte[] saved = source.clone();
        CameraPresetProjection.Plan plan = CameraPresetProjection.plan(source, null, null);
        PictureControlWriteValidation.validateConvertedData(plan.conversion.dataBytes());
        yes(Arrays.equals(saved, source));
        yes(PresetFile.validate(plan.ncpBytes()).fileFormat.equals("NCP"));
        yes(plan.conversion.sourceSha256().equals(hash(source)));
        return plan;
    }
    public static int run() throws Exception {
        checks = 0;
        byte[] standard = Np2Fixtures.std();
        yes(hash(standard).equals("f1a74bf6e6fbda132fed3f66d7f84b1b36656f70d4591af5c7ac37d69118df39"));
        yes(hash(Np2Fixtures.flat()).equals("38ef2adbfda40255bdde815cf474a77ab03c487c1b24ce0fb20c0f4d78eff4ab"));
        yes(hash(Np2Fixtures.mono()).equals("2f069e91e69e5d6f7b2ac9d4d28faf00c0b71680a22dc9b9c2df146b64dcb44e"));
        PresetFile info = PresetFile.validate(standard);
        yes(info.fileFormat.equals("NP2") && info.version.equals("0210") && info.registrationName.equals("HV240_NP2_STD"));
        CameraPresetProjection.Plan plan = valid(standard);
        byte[] wire = plan.conversion.dataBytes();
        yes(wire.length == 36 && wire[0] == 1 && wire[25] == 12 && wire[27] == 4 && wire[35] == 0);
        yes(plan.omitted.isEmpty() && plan.approximated.isEmpty());
        plan = valid(Np2Fixtures.flat()); yes(plan.conversion.dataBytes()[0] == 2 && plan.approximated.toString().contains("平面"));
        plan = valid(Np2Fixtures.mono()); wire = plan.conversion.dataBytes();
        yes(wire[0] == 4 && wire[30] == 0 && wire[31] == 0 && wire[32] == 0 && wire[33] == 0);
        yes(plan.omitted.isEmpty());
        byte[] quarter = scalar(scalar(scalar(scalar(scalar(scalar(standard, 6, 13), 7, -3), 8, 5), 9, 6), 10, 3), 11, -5);
        plan = valid(quarter); wire = plan.conversion.dataBytes();
        yes(wire[25] == 13 && wire[27] == -3 && wire[28] == 5 && wire[29] == 6 && wire[30] == 3 && wire[31] == -5);
        yes(wire.length == 36);
        byte[] curve = NcpCompatibilityFixtures.curve();
        byte[] curved = replace(quarter, 2, curve);
        plan = valid(curved); wire = plan.conversion.dataBytes();
        yes(wire.length == 614 && wire[35] == 1 && wire[28] == 0 && wire[29] == 0);
        yes(Arrays.equals(curve, Arrays.copyOfRange(wire, 36, wire.length)));
        yes(plan.omitted.toString().contains("不重复叠加"));
        byte[] badCurve = curve.clone(); badCurve[0] = 0;
        plan = valid(replace(quarter, 2, badCurve));
        yes(plan.conversion.dataBytes().length == 36 && plan.conversion.dataBytes()[28] == 5);
        yes(plan.omitted.toString().contains("自定义曲线"));
        byte[] future = replace(quarter, 0x100, new byte[]{'0','2','9','9'});
        yes(PresetFile.validate(future).fileFormat.equals("NP2"));
        plan = valid(future); yes(plan.conversion.dataBytes()[0] == 2 && plan.conversion.dataBytes()[25] == 0);
        yes(plan.omitted.toString().contains("布局"));
        byte[] unknown = replace(quarter, 0xdead, new byte[]{4,5,6});
        plan = valid(unknown); yes(plan.conversion.dataBytes()[30] == 3 && plan.omitted.toString().contains("扩展"));
        byte[] auto = replace(standard, 0x600, new byte[]{0,4});
        plan = valid(auto); yes(plan.conversion.dataBytes()[25] == 0 && plan.omitted.toString().contains("锐化"));
        CameraPresetProjection.Plan adjusted = CameraPresetProjection.plan(quarter, 8, 12);
        yes(adjusted.conversion.dataBytes()[26] == 8 && adjusted.conversion.dataBytes()[27] == 12 && adjusted.conversion.dataBytes()[25] == 13);
        rejects(() -> CameraPresetProjection.plan(quarter, 21, 0));
        for (int length : new int[]{4,8,15,100,standard.length-1}) {
            byte[] truncated = Arrays.copyOf(standard, length);
            rejects(() -> PresetFile.validate(truncated));
            rejects(() -> CameraPresetProjection.plan(truncated, null, null));
        }
        byte[] corrupt = standard.clone(); corrupt[8] = 0x7f;
        rejects(() -> PresetFile.validate(corrupt));
        PresetPreviewProfile preview = PresetPreviewProfiles.fromPreset(standard);
        yes(preview instanceof Np2PreviewProfile && preview.modelVersion().equals(Np2PreviewProfile.MODEL_VERSION));
        yes(preview.applyArgb(0x7f9643c8) == 0x7f9643c8);
        yes(preview.spatialSettings().sharpening == 1.0/3 && preview.spatialSettings().clarity == .2);
        yes(PresetPreviewProfiles.fromPreset(quarter).applyArgb(0x7f9643c8) != preview.applyArgb(0x7f9643c8));
        yes(PresetPreviewProfiles.fromPreset(scalar(standard, 10, 1)).applyArgb(0xff966143)
                != PresetPreviewProfiles.fromPreset(standard).applyArgb(0xff966143));
        int mono = PresetPreviewProfiles.fromPreset(Np2Fixtures.mono()).applyArgb(0x7f9643c8);
        yes((mono >>> 24) == 0x7f && ((mono >>> 16) & 255) == (mono & 255) && ((mono >>> 8) & 255) == (mono & 255));
        rejects(() -> PresetPreviewProfiles.fromPreset(Np2Fixtures.flat()));
        rejects(() -> PresetPreviewProfiles.fromPreset(unknown));
        rejects(() -> PresetPreviewProfiles.fromPreset(auto));
        rejects(() -> PresetPreviewProfiles.fromPreset(future));
        System.out.println("PASS " + checks + " NP2 checks: authentic NX baselines, quarter units, partial conversion, source integrity and preview gates");
        return checks;
    }
    private static String hash(byte[] data) throws Exception {
        byte[] b = java.security.MessageDigest.getInstance("SHA-256").digest(data);
        StringBuilder text = new StringBuilder(); for (byte v : b) text.append(String.format(java.util.Locale.ROOT, "%02x", v & 255)); return text.toString();
    }
    public static void main(String[] args) throws Exception { run(); }
}
