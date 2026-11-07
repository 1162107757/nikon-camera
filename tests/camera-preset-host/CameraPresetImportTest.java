package cc.huevia.usb;

import cc.huevia.ncp.*;
import cc.huevia.picturecontrol.CameraParameterWriteGuard;
import cc.huevia.ptp.PtpResponseException;
import java.io.*;
import java.util.*;

/** Synthetic choices and camera responses only. This suite never connects to a camera. */
public final class CameraPresetImportTest {
    private static int checks;
    private interface Action { void run() throws Exception; }
    public static void main(String[] args) throws Exception {
        adapter(); descriptors(); authorization(); parameters();
        if (args.length == 1) java.nio.file.Files.write(java.nio.file.Path.of(args[0]), Np3PreviewProfileTest.identityNp3());
        System.out.println("PASS: " + checks + " unified preset / optional camera parameter checks");
    }
    private static void adapter() throws Exception {
        byte[] legacy = NcpCompatibilityFixtures.ncp(), original = legacy.clone();
        CameraPresetAdapter.Plan full = CameraPresetAdapter.plan(legacy, 4, 0);
        check(!full.approximate, "legacy subset stays compatible");
        equal(full.approved(false).dataBytes(), NcpCompatibilityFixtures.expectedData(4, 0));
        equal(legacy, original);
        byte[] modern = Np3PreviewProfileTest.identityNp3(), source = modern.clone();
        CameraPresetAdapter.Plan partial = CameraPresetAdapter.initialPlan(modern);
        check(partial.approximate && partial.summary().contains("色彩混合器"), "lost controls explicit");
        denied(() -> partial.approved(false));
        byte[] wire = partial.approved(true).dataBytes();
        PictureControlImportSession.validateConvertedData(wire);
        check(wire[0] == 2 && wire[26] == 4 && wire[27] == 2, "native spatial amounts kept by default");
        check(wire[30] == 0 && wire[31] == 0, "dropped colour controls not invented");
        for (int i = 0; i <= 256; i++) {
            int v = (wire[100 + i * 2] & 255) * 256 + (wire[101 + i * 2] & 255);
            check(v == Math.round(i / 256.0 * 32767), "identity curve " + i);
        }
        equal(modern, source);
        byte[] changed = wire.clone(); changed[0] = 4;
        check(partial.conversion.dataBytes()[0] == 2, "wire ownership");
        PresetImportOptions approve = new PresetImportOptions(true, partial.conversion.dataSha256(), CameraParameterRequest.NONE, null);
        equal(approve.convert(modern, 4, 2).dataBytes(), wire);
        denied(() -> approve.convert(modern, 5, 2));
        denied(() -> new PresetImportOptions(false, partial.conversion.dataSha256(), null, null).convert(modern, 4, 2));
        byte[] curved = appendCurve(modern, NcpCompatibilityFixtures.curve());
        CameraPresetAdapter.Plan withCurve = CameraPresetAdapter.initialPlan(curved);
        equal(Arrays.copyOfRange(withCurve.conversion.dataBytes(), 36, 614), NcpCompatibilityFixtures.curve());
        for (int length : new int[] {0, 4, 20, 100, 400}) {
            final byte[] truncated = Arrays.copyOf(modern, length); denied(() -> CameraPresetAdapter.plan(truncated, 4, 0));
        }
        byte[] unknown = modern.clone(); unknown[19] = '9'; denied(() -> CameraPresetAdapter.initialPlan(unknown));
        byte[] mono = legacy.clone(); mono[36] = 6; mono[37] = 0x4d;
        mono[43] = mono[44] = (byte) 255; mono[45] = mono[46] = (byte) 128; mono[47] = (byte) 255;
        CameraPresetAdapter.Plan bw = CameraPresetAdapter.initialPlan(mono);
        check(bw.approximate && bw.conversion.dataBytes()[0] == 4, "monochrome explicit partial projection");
        equal(Arrays.copyOfRange(bw.conversion.dataBytes(), 36, 614), NcpCompatibilityFixtures.curve());
    }
    private static byte[] appendCurve(byte[] base, byte[] curve) throws IOException {
        base = base.clone(); int offset = 4;
        for (int i = 1; i <= 32; i++) {
            int length = base[offset + 7] & 255;
            if (i >= 25 && i <= 29) base[offset + 8] = 1;
            offset += 8 + length;
        }
        ByteArrayOutputStream output = new ByteArrayOutputStream(); output.write(base, 0, base.length - 4);
        output.write(new byte[] {0,0,0,2,0,0,2,0x42}); output.write(curve); output.write(new byte[4]); return output.toByteArray();
    }
    private static void descriptors() throws Exception {
        CameraParameterDescriptor ev = CameraParameterDescriptor.parse(0x5010, descriptor(0x5010, 3, true, -333, -1000, -333, 0, 333, 1000));
        check(ev.current == -333 && ev.accepts(1000) && !ev.accepts(500), "signed enum");
        equal(ev.encode(-333), new byte[] {(byte) 0xb3, (byte) 0xfe});
        check(ev.read(ev.encode(-1000)) == -1000, "signed readback");
        byte[] range = range(0xd01e, 4, true, 5000, 2500, 10000, 100);
        CameraParameterDescriptor kelvin = CameraParameterDescriptor.parse(0xd01e, range);
        check(kelvin.accepts(5500) && !kelvin.accepts(5550) && !kelvin.accepts(11000), "stepped range");
        byte[] readOnly = range.clone(); readOnly[4] = 0;
        check(!CameraParameterDescriptor.parse(0xd01e, readOnly).accepts(5500), "read-only");
        denied(() -> CameraParameterDescriptor.parse(0x5005, range));
        denied(() -> CameraParameterDescriptor.parse(0xd01e, Arrays.copyOf(range, range.length - 1)));
        byte[] wrongType = range.clone(); wrongType[2] = 3; denied(() -> CameraParameterDescriptor.parse(0xd01e, wrongType));
        denied(() -> new CameraParameterRequest(0x1234L, null, null));
        denied(() -> new CameraParameterRequest(null, 5000L, null));
        denied(() -> new CameraParameterRequest(0x8012L, null, null));
    }
    private static void authorization() throws Exception {
        CameraParameterWriteGuard guard = new CameraParameterWriteGuard();
        denied(() -> guard.consume(new byte[2], new long[] {0x5010}));
        byte[] approved = {0,0}; Map<Integer, byte[]> values = new LinkedHashMap<>(); values.put(0x5010, approved);
        guard.authorize(values); approved[0] = 1;
        denied(() -> guard.consume(approved, new long[] {0x5010}));
        guard.consume(new byte[2], new long[] {0x5010}); checks++;
        denied(() -> guard.consume(new byte[2], new long[] {0x5010}));
        denied(() -> guard.authorize(values));
        denied(() -> new CameraParameterWriteGuard().authorize(Collections.singletonMap(0x5007, new byte[2])));
        check(!CameraParameterWriteGuard.propertyRead(0x1014, new long[] {0x5007}), "unrelated property blocked");
    }
    private static void parameters() throws Exception {
        Fake fake = new Fake();
        CameraParameterController.Result noChoice = CameraParameterController.prepare(CameraParameterRequest.NONE);
        CameraParameterController.apply(noChoice, true, fake, null);
        check(fake.calls == 0, "default off means no property reads or writes");
        CameraParameterRequest choice = new CameraParameterRequest(4L, null, 1000L);
        CameraParameterController.Result ok = CameraParameterController.prepare(choice);
        CameraParameterController.apply(ok, true, fake, snapshot -> { check(fake.writes.isEmpty(), "backup precedes writes"); fake.audited = true; });
        check(fake.writes.equals(Arrays.asList(0x5005, 0x5010)), "only explicitly selected values, ordered writes");
        for (var item : ok.changes()) check("已调整并核对".equals(item.status) && item.before != null && item.observed == item.desired, "per-property evidence");
        Fake unsupported = new Fake(); CameraParameterController.Result absent = CameraParameterController.prepare(choice);
        CameraParameterController.apply(absent, false, unsupported, null);
        check(unsupported.calls == 0 && absent.text().contains("已跳过"), "unsupported operations don't mutate");
        Fake unavailableKelvin = new Fake(); unavailableKelvin.readOnlyKelvin = true;
        CameraParameterController.Result pair = CameraParameterController.prepare(new CameraParameterRequest(0x8012L, 5500L, 1000L));
        CameraParameterController.apply(pair, true, unavailableKelvin, snapshot -> unavailableKelvin.audited = true);
        check(unavailableKelvin.writes.equals(Collections.singletonList(0x5010)), "unavailable Kelvin pair leaves WB unchanged");
        Fake existingMode = new Fake(); existingMode.current.put(0x5005, 0x8012L); existingMode.readOnlyWhiteBalance = true;
        CameraParameterController.Result kelvinOnly = CameraParameterController.prepare(new CameraParameterRequest(0x8012L, 5500L, null));
        CameraParameterController.apply(kelvinOnly, true, existingMode, snapshot -> existingMode.audited = true);
        check(existingMode.writes.equals(Collections.singletonList(0xd01e)), "already matching read-only WB mode does not block writable Kelvin");
        Fake changedMode = new Fake(); changedMode.current.put(0x5005, 0x8012L); changedMode.staleWhiteBalance = true;
        CameraParameterController.Result changedKelvin = CameraParameterController.prepare(new CameraParameterRequest(0x8012L, 5500L, null));
        CameraParameterController.apply(changedKelvin, true, changedMode, snapshot -> changedMode.audited = true);
        check(changedMode.writes.isEmpty(), "intervening WB mode change prevents Kelvin write");
        Fake stale = new Fake(); stale.stale = true;
        CameraParameterController.Result changed = CameraParameterController.prepare(new CameraParameterRequest(4L, null, null));
        CameraParameterController.apply(changed, true, stale, snapshot -> stale.audited = true);
        check(stale.writes.isEmpty() && changed.text().contains("已变化"), "intervening camera change not overwritten");
        Fake failed = new Fake(); failed.timeout = true;
        CameraParameterController.Result interrupted = CameraParameterController.prepare(choice);
        denied(() -> CameraParameterController.apply(interrupted, true, failed, snapshot -> failed.audited = true));
        check(failed.writes.size() == 1 && interrupted.uncertain, "uncertain write never retried or followed by another write");
        Fake rejected = new Fake(); rejected.rejected = true;
        CameraParameterController.Result rejectResult = CameraParameterController.prepare(choice);
        CameraParameterController.apply(rejectResult, true, rejected, snapshot -> rejected.audited = true);
        check(rejected.writes.size() == 1 && !rejectResult.uncertain, "confirmed rejection does not retry");
        Fake mismatch = new Fake(); mismatch.mismatch = true;
        CameraParameterController.Result mismatchResult = CameraParameterController.prepare(choice);
        CameraParameterController.apply(mismatchResult, true, mismatch, snapshot -> mismatch.audited = true);
        check(mismatch.writes.size() == 1 && mismatchResult.text().contains("读回不一致"), "readback mismatch stops subsequent writes");
        Fake readbackRefused = new Fake(); readbackRefused.rejectReadback = true;
        CameraParameterController.Result readbackResult = CameraParameterController.prepare(choice);
        CameraParameterController.apply(readbackResult, true, readbackRefused, snapshot -> readbackRefused.audited = true);
        check(readbackRefused.writes.size() == 1 && readbackResult.uncertain && readbackResult.text().contains("已写入，读回未确认"), "readback refusal is not mislabeled as rejected write");
        Fake missingAudit = new Fake(); denied(() -> CameraParameterController.apply(CameraParameterController.prepare(choice), true, missingAudit, null));
        check(missingAudit.writes.isEmpty(), "no backup means no parameter mutation");
        Fake same = new Fake(); CameraParameterController.Result unchanged = CameraParameterController.prepare(new CameraParameterRequest(2L, null, -333L));
        CameraParameterController.apply(unchanged, true, same, null);
        check(same.writes.isEmpty(), "already matching settings are not written");
    }
    private static final class Fake implements CameraParameterController.Access {
        final Map<Integer, Long> current = new HashMap<>();
        final Map<Integer, Integer> reads = new HashMap<>();
        final List<Integer> writes = new ArrayList<>();
        final CameraParameterWriteGuard guard = new CameraParameterWriteGuard();
        boolean audited, timeout, rejected, mismatch, stale, readOnlyKelvin, rejectReadback, readOnlyWhiteBalance, staleWhiteBalance; int calls;
        Fake() { current.put(0x5005, 2L); current.put(0xd01e, 5000L); current.put(0x5010, -333L); }
        public byte[] get(int op, int code) throws IOException {
            calls++;
            if (op == 0x1015 && rejectReadback && !writes.isEmpty()) throw new PtpResponseException(0x200f, 1);
            long value = current.get(code);
            if (op == 0x1014) {
                if (code == 0xd01e) return range(code, 4, !readOnlyKelvin, value, 2500, 10000, 100);
                return code == 0x5005 ? descriptor(code, 4, !readOnlyWhiteBalance, value, 2,4,0x8012) : descriptor(code, 3, true, value, -333,0,333,1000);
            }
            int count = reads.merge(code, 1, Integer::sum);
            if (stale && count > 1) value = 7;
            if (staleWhiteBalance && code == 0x5005 && count > 1) value = 4;
            return scalar(value);
        }
        public void authorize(Map<Integer, byte[]> values) throws IOException { check(audited, "durable audit required"); guard.authorize(values); }
        public void set(int code, byte[] value) throws IOException {
            guard.consume(value, new long[] {code}); writes.add(code);
            if (timeout) throw new IOException("synthetic timeout");
            if (rejected) throw new PtpResponseException(0x2019, 1);
            long scalar = (value[0] & 255) | (value[1] & 255) << 8;
            if (code == 0x5010) scalar = (short) scalar;
            if (!mismatch) current.put(code, scalar);
        }
    }
    private static byte[] descriptor(int code, int type, boolean writable, long current, long... options) {
        ByteArrayOutputStream out = header(code, type, writable, current); out.write(2); out.write(options.length); out.write(0);
        for (long value : options) write(out, scalar(value)); return out.toByteArray();
    }
    private static byte[] range(int code, int type, boolean writable, long current, long min, long max, long step) {
        ByteArrayOutputStream out = header(code, type, writable, current); out.write(1);
        write(out, scalar(min)); write(out, scalar(max)); write(out, scalar(step)); return out.toByteArray();
    }
    private static ByteArrayOutputStream header(int code, int type, boolean writable, long current) {
        ByteArrayOutputStream out = new ByteArrayOutputStream(); write(out, scalar(code)); write(out, scalar(type)); out.write(writable ? 1 : 0);
        write(out, scalar(current)); write(out, scalar(current)); return out;
    }
    private static byte[] scalar(long value) { return new byte[] {(byte) value, (byte) (value >> 8)}; }
    private static void write(ByteArrayOutputStream out, byte[] bytes) { out.write(bytes, 0, bytes.length); }
    private static void check(boolean condition, String label) { checks++; if (!condition) throw new AssertionError(label); }
    private static void equal(byte[] a, byte[] b) { check(Arrays.equals(a, b), "byte equality"); }
    private static void denied(Action action) throws Exception { try { action.run(); } catch (IOException | IllegalArgumentException expected) { checks++; return; } throw new AssertionError("Expected refusal"); }
}
