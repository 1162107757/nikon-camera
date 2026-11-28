package cc.huevia.ncp;

import cc.huevia.library.PresetFile;
import cc.huevia.picturecontrol.PictureControlWriteValidation;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.zip.ZipFile;

/** Conversion outcomes, source preservation, malformed containers and optional real recipe corpus. */
public final class CameraPresetProjectionTest {
    private static int checks;
    private static void yes(boolean condition) {
        checks++; if (!condition) throw new AssertionError("NP3 projection check " + checks);
    }
    public static byte[] np3(int base, int sharp, boolean curve, boolean unsupported) throws IOException {
        ByteArrayOutputStream b = new ByteArrayOutputStream(); b.write(new byte[]{'N','C','P',0});
        for (int i = 1; i <= 32; i++) {
            byte[] f = new byte[i == 1 ? 4 : i == 2 || i == 32 ? 20 : i == 31 ? 28 : 2];
            if (i == 1) f = "0310".getBytes(StandardCharsets.US_ASCII);
            else if (i == 2) System.arraycopy("NP3 TEST".getBytes(StandardCharsets.US_ASCII), 0, f, 0, 8);
            else if (i == 3) { f[0] = (byte) (base >>> 8); f[1] = (byte) base; }
            else if (i == 6 || i == 7 || i == 22) {
                f[0] = (byte) (128 + (i == 6 ? sharp : i == 7 ? -3 : 5)); f[1] = 4;
            } else if (i >= 25 && i <= 30) { f[0] = (byte) (curve && i < 30 ? 1 : i == 26 ? 148 : 128); f[1] = 1; }
            else if (i == 31 || i == 32) Arrays.fill(f, (byte) 128);
            else { f[0] = (byte) 255; f[1] = 4; }
            record(b, i * 0x100, f);
        }
        if (curve) record(b, 2, NcpCompatibilityFixtures.curve());
        if (unsupported) record(b, 0x123456, new byte[]{1, 2, 3});
        b.write(new byte[4]); return b.toByteArray();
    }
    private static void record(ByteArrayOutputStream b, int id, byte[] value) throws IOException {
        for (int n : new int[]{id, value.length}) b.write(new byte[]{(byte)(n>>>24),(byte)(n>>>16),(byte)(n>>>8),(byte)n});
        b.write(value);
    }
    private static CameraPresetProjection.Plan valid(byte[] source) throws Exception {
        byte[] before = source.clone();
        CameraPresetProjection.Plan plan = CameraPresetProjection.plan(source, null, null);
        yes(Arrays.equals(before, source));
        yes(PresetFile.validate(plan.ncpBytes()).fileFormat.equals("NCP"));
        yes(plan.ncpBytes().length == 638);
        PictureControlWriteValidation.validateConvertedData(plan.conversion.dataBytes());
        yes(plan.conversion.dataBytes().length == 614);
        yes(plan.conversion.toDisplayText().contains("可继续导入"));
        byte[] result = plan.ncpBytes(); result[0] = 0; yes(plan.ncpBytes()[0] == 'N');
        return plan;
    }
    private static void rejects(byte[] b) throws Exception {
        checks++;
        try { CameraPresetProjection.plan(b, null, null); }
        catch (IOException expected) { return; }
        throw new AssertionError("Damaged container accepted");
    }
    public static int run() throws Exception {
        checks = 0;
        byte[] b = np3(0x20, 7, true, true);
        yes(PresetFile.validate(b).fileFormat.equals("NP3"));
        yes(PresetFile.validate(b).registrationName.equals("NP3 TEST"));
        yes(PresetFile.validate(Np2Fixtures.std()).registrationName.equals("HV240_NP2_STD"));
        CameraPresetProjection.Plan p = valid(b);
        yes(PresetFile.validate(p.ncpBytes()).registrationName.equals("NP3 TEST"));
        byte[] wire = p.conversion.dataBytes();
        yes(wire[0] == 2 && wire[25] == 8 && wire[26] == 5 && wire[27] == -3);
        yes(Arrays.equals(Arrays.copyOfRange(wire, 36, 614), NcpCompatibilityFixtures.curve()));
        yes(p.omitted.toString().contains("分区调色") && p.omitted.toString().contains("扩展参数"));
        yes(p.approximated.toString().contains("锐化"));
        byte[] expected = NcpPictureControlConverter.convert(p.ncpBytes(), 5, -3).dataBytes();
        yes(Arrays.equals(wire, expected));
        p = valid(np3(0x1234, 8, true, false)); yes(p.conversion.dataBytes()[0] == 2);
        yes(!p.approximated.isEmpty());
        p = valid(np3(0x655, 8, true, false)); yes(p.conversion.dataBytes()[0] == 4);
        yes(PresetPreviewProfiles.fromPreset(p.ncpBytes()) instanceof NcpMonochromePreviewProfile);
        p = valid(np3(0x20, -128, false, true)); yes(p.conversion.dataBytes()[25] == 0);
        yes(p.omitted.toString().contains("锐化")); yes(p.approximated.toString().contains("近似明暗曲线"));
        b = np3(0x20, 8, true, false); b[14] = '2';
        p = valid(b); yes(p.omitted.toString().contains("布局"));
        yes(!Np3PresetDetails.read(b).previewSupported);
        b = np3(0x20, 8, true, false);
        for (int n : new int[]{4, 8, 15, 100, b.length - 1}) rejects(Arrays.copyOf(b, n));
        byte[] corrupt = b.clone(); corrupt[8] = 0x7f; rejects(corrupt);
        ByteArrayOutputStream duplicate = new ByteArrayOutputStream(); duplicate.write(b, 0, b.length - 4);
        record(duplicate, 0x100, "0310".getBytes(StandardCharsets.US_ASCII)); duplicate.write(new byte[4]); rejects(duplicate.toByteArray());
        corrupt = b.clone(); corrupt[b.length - 4 - 578] = 0; p = valid(corrupt);
        yes(p.omitted.toString().contains("自定义曲线"));
        System.out.println("PASS " + checks + " NP3 projection checks; valid NCP, retained curve, lossy fields, source safety and malformed bounds");
        return checks;
    }
    public static void main(String[] args) throws Exception {
        run();
        if (args.length == 1) {
            int total = 0, previewUnsupported = 0;
            try (ZipFile zip = new ZipFile(args[0])) {
                var entries = zip.entries();
                while (entries.hasMoreElements()) {
                    var entry = entries.nextElement();
                    if (!entry.getName().toLowerCase(java.util.Locale.ROOT).endsWith(".np3")) continue;
                    byte[] data; try (var input = zip.getInputStream(entry)) { data = input.readAllBytes(); }
                    try { PresetPreviewProfiles.fromPreset(data); } catch (IOException unsupported) { previewUnsupported++; }
                    valid(data); total++;
                }
            }
            System.out.println("PASS corpus " + total + " NP3 converted, including " + previewUnsupported + " unsupported phone previews");
        }
    }
}
