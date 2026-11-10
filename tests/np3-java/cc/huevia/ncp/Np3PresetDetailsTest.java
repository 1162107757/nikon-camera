package cc.huevia.ncp;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.List;

public final class Np3PresetDetailsTest {
    private static int checks;
    public static void main(String[] args) throws Exception {
        reportsStoredAmountsAndAllChannels();
        curveOverridesBasicToneAndKeepsUtf8Note();
        monochromeReportsItsOwnControls();
        unsupportedSemanticsKeepOnlyVerifiedEnvelope();
        malformedInputIsRejectedAndSnapshotsAreImmutable();
        System.out.println("PASS: " + checks + " NP3 parameter inspection checks");
    }

    private static void reportsStoredAmountsAndAllChannels() throws Exception {
        byte[] source = Np3PreviewProfileTest.identityNp3();
        field(source, 6, 0, 127); field(source, 7, 0, 133); field(source, 22, 0, 142);
        for (int i = 0; i < 6; i++) field(source, 25 + i, 0, 78 + i * 20);
        for (int i = 0; i < 24; i++) field(source, 31, i, 128 + i - 12);
        for (int i = 0; i < 3; i++) {
            int hue = 60 + i * 120;
            field(source, 32, i * 4, 128 | hue >>> 8); field(source, 32, i * 4 + 1, hue & 255);
            field(source, 32, i * 4 + 2, 128 + i * 7); field(source, 32, i * 4 + 3, 128 - i * 9);
        }
        field(source, 32, 16, 199); field(source, 32, 18, 91);
        byte[] before = source.clone(); Np3PresetDetails details = Np3PresetDetails.read(source);
        yes(details.previewSupported, "validated FC has inspectable controls");
        eq("HOST NP3", details.registrationName); eq("0310", details.version);
        eq(0x20, details.baseCode); eq("Flexible Color", details.baseLabel);
        eq("-0.25", row(details, "sharpening").values.get(0));
        eq("+1.25", row(details, "clarity").values.get(0));
        eq("+3.5", row(details, "mid-range").values.get(0));
        eq("-50", row(details, "contrast").values.get(0));
        eq("-30", row(details, "highlights").values.get(0));
        eq("-10", row(details, "shadows").values.get(0));
        eq("+10", row(details, "whites").values.get(0));
        eq("+30", row(details, "blacks").values.get(0));
        eq("+50", row(details, "saturation").values.get(0));
        eq(Arrays.asList("-12", "-11", "-10"), row(details, "color-0").values);
        eq(Arrays.asList("+9", "+10", "+11"), row(details, "color-7").values);
        eq(Arrays.asList("60°", "0", "0"), row(details, "zone-0").values);
        eq(Arrays.asList("300°", "+14", "-18"), row(details, "zone-2").values);
        eq("71", row(details, "blending").values.get(0)); eq("-37", row(details, "balance").values.get(0));
        yes(Arrays.equals(before, source), "inspection never rewrites the preset");
        eq("", details.previewReason);
    }

    private static void curveOverridesBasicToneAndKeepsUtf8Note() throws Exception {
        byte[] source = Np3PreviewProfileTest.identityNp3();
        for (int i = 25; i <= 29; i++) field(source, i, 0, 1);
        byte[] note = new byte[32], text = "作者 📷 合成样本".getBytes(StandardCharsets.UTF_8);
        System.arraycopy(text, 0, note, 0, text.length);
        source = append(append(source, 0x10100, note), 2, curve());
        Np3PresetDetails details = Np3PresetDetails.read(source);
        yes(details.previewSupported && details.hasCustomCurve, "custom curve accepted by existing strict reader");
        eq("作者 📷 合成样本", details.note); eq("自定义 · 257 点", row(details, "curve").values.get(0));
        yes(details.groups.stream().flatMap(g -> g.rows.stream()).noneMatch(r -> r.id.equals("contrast")),
                "curve sentinels must not be shown as actual -127 contrast");
        eq("0", row(details, "saturation").values.get(0));
    }

    private static void monochromeReportsItsOwnControls() throws Exception {
        for (int base : new int[] {0x064d, 0x0655}) {
            byte[] source = Np3PreviewProfileTest.identityNp3();
            field(source, 3, 0, base >>> 8); field(source, 3, 1, base & 255);
            field(source, 8, 0, 1); field(source, 9, 0, 1);
            field(source, 12, 0, base == 0x064d ? 128 : 131); field(source, 12, 1, 0);
            field(source, 13, 0, 128); field(source, 13, 1, 0); field(source, 20, 0, 255);
            for (int i = 25; i <= 29; i++) field(source, i, 0, 1);
            Np3PresetDetails details = Np3PresetDetails.read(append(source, 2, curve()));
            yes(details.previewSupported, "researched monochrome fixture stays supported");
            eq(base, details.baseCode); eq(base == 0x064d ? "单色" : "深色调单色", details.baseLabel);
            eq(base == 0x064d ? "关闭" : "红色", row(details, "filter-effect").values.get(0));
            yes(details.groups.stream().noneMatch(g -> g.id.equals("blender") || g.id.equals("grading")),
                    "monochrome cannot imply active Flexible Color adjustments");
        }
    }

    private static void unsupportedSemanticsKeepOnlyVerifiedEnvelope() throws Exception {
        for (int[] mutation : new int[][] {{3, 0, 8}, {6, 1, 3}, {25, 0, 255}, {20, 0, 130}}) {
            byte[] source = Np3PreviewProfileTest.identityNp3();
            field(source, mutation[0], mutation[1], mutation[2]);
            Np3PresetDetails details = Np3PresetDetails.read(source);
            yes(!details.previewSupported, "unverified active controls remain unsupported");
            yes(!details.previewReason.isEmpty(), "unsupported reason is visible");
            eq("HOST NP3", details.registrationName); eq(0, details.groups.size());
        }
        byte[] unknown = Np3PreviewProfileTest.identityNp3(); field(unknown, 3, 0, 8); field(unknown, 3, 1, 2);
        eq("未识别基底 · 0x0802", Np3PresetDetails.read(unknown).baseLabel);
    }

    private static void malformedInputIsRejectedAndSnapshotsAreImmutable() throws Exception {
        byte[] source = Np3PreviewProfileTest.identityNp3();
        for (int length : new int[] {0, 3, 7, 11, 31, 37, 128, 390, 391}) {
            byte[] shortFile = Arrays.copyOf(source, length); rejects(() -> Np3PresetDetails.read(shortFile));
        }
        rejects(() -> Np3PresetDetails.read(null)); rejects(() -> Np3PresetDetails.read(new byte[NcpFile.MAX_BYTES + 1]));
        byte[] version = source.clone(); field(version, 1, 3, '1'); rejects(() -> Np3PresetDetails.read(version));
        byte[] tail = Arrays.copyOf(source, source.length + 1); rejects(() -> Np3PresetDetails.read(tail));
        Np3PresetDetails details = Np3PresetDetails.read(source); source[0] = 0; field(source, 6, 0, 0);
        eq("+2", row(details, "sharpening").values.get(0));
        immutable(() -> details.groups.clear()); immutable(() -> details.groups.get(0).rows.clear());
        immutable(() -> row(details, "sharpening").values.set(0, "wrong"));
        immutable(() -> details.groups.stream().filter(g -> g.id.equals("blender")).findFirst().orElseThrow().columns.clear());
    }

    private static Np3PresetDetails.Row row(Np3PresetDetails details, String id) {
        return details.groups.stream().flatMap(g -> g.rows.stream()).filter(r -> r.id.equals(id)).findFirst().orElseThrow();
    }
    private static byte[] curve() {
        byte[] curve = new byte[578]; curve[0] = 0x49; curve[1] = 0x30;
        curve[3] = curve[5] = (byte) 255; curve[6] = 1; curve[8] = 2; curve[11] = curve[12] = (byte) 255;
        for (int i = 0; i <= 256; i++) {
            int sample = (int) Math.round(i * 32767.0 / 256);
            curve[64 + i * 2] = (byte) (sample >>> 8); curve[65 + i * 2] = (byte) sample;
        }
        return curve;
    }
    private static byte[] append(byte[] base, int id, byte[] payload) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream(); out.write(base, 0, base.length - 4);
        for (int value : new int[] {id, payload.length}) {
            out.write(value >>> 24); out.write(value >>> 16); out.write(value >>> 8); out.write(value);
        }
        out.write(payload); out.write(new byte[4]); return out.toByteArray();
    }
    private static void field(byte[] bytes, int index, int position, int value) {
        int offset = 4;
        for (int i = 1; i < index; i++) offset += 8 + (bytes[offset + 7] & 255);
        bytes[offset + 8 + position] = (byte) value;
    }
    private interface Checked { void run() throws Exception; }
    private static void rejects(Checked action) throws Exception {
        try { action.run(); } catch (IOException expected) { checks++; return; }
        throw new AssertionError("Malformed file accepted");
    }
    private static void immutable(Checked action) throws Exception {
        try { action.run(); } catch (UnsupportedOperationException expected) { checks++; return; }
        throw new AssertionError("Inspection snapshot mutable");
    }
    private static void yes(boolean value, String message) { checks++; if (!value) throw new AssertionError(message); }
    private static void eq(Object expected, Object actual) { yes(expected.equals(actual), "Expected " + expected + ", got " + actual); }
}
