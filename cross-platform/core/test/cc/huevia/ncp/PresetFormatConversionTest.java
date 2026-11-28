package cc.huevia.ncp;

import cc.huevia.library.PresetFile;
import cc.huevia.library.PresetLibrary;
import cc.huevia.picturecontrol.PictureControlData;
import java.io.IOException;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.List;

public final class PresetFormatConversionTest {
    private static int checks;

    private static void check(boolean condition, String detail) {
        if (!condition) throw new AssertionError(detail);
        checks++;
    }

    private static boolean row(PresetFormatConversion.Plan plan, String label, String status) {
        return plan.rows.stream().anyMatch(row -> row.label.equals(label) && row.status.equals(status));
    }

    public static int run(Path temporary) throws Exception {
        checks = 0;
        byte[] ncp = CameraPresetProjection.ncp("CONVERT TEST", 5, 3, 2, -1,
                CameraPresetProjection.identityCurve());
        byte[] np2 = Np2SupportTest.scalar(Np2Fixtures.std(), 8, 5);
        byte[] np3 = CameraPresetProjectionTest.np3(0x20, 7, true, true);
        PresetLibrary library = new PresetLibrary(temporary.resolve("preset-format-copy").toFile());
        for (byte[] source : List.of(ncp, np2, np3)) {
            PresetFile header = PresetFile.validate(source);
            byte[] snapshot = source.clone();
            String name = header.registrationName;
            String filename = name + "." + header.fileFormat;
            PresetLibrary.AddResult original = library.importFile(filename, source);
            for (String target : List.of("NCP", "NP2", "NP3")) {
                if (header.fileFormat.equals(target)) continue;
                PresetFormatConversion.Plan converted = PresetFormatConversion.plan(source, target);
                check(target.equals(PresetFile.validate(converted.bytes()).fileFormat), "Wrong output container");
                check(name.equals(converted.cameraName), "Camera name changed");
                check(Arrays.equals(source, snapshot), "Conversion modified source bytes");
                String copyName = name + "." + target;
                PresetLibrary.AddResult copy = library.importFile(copyName, converted.bytes());
                check(copy.added && !copy.record.id.equals(original.record.id), "No separate library copy");
                check(!library.importFile(copyName, converted.bytes()).added, "Duplicate added on retry");
                check(Arrays.equals(snapshot, library.readPreset(original.record.id)), "Original preset was replaced");
            }
        }
        Np3Container richer = Np3Container.read(PresetFormatConversion.plan(ncp, "NP3").bytes());
        check(richer.canonical0310 && Arrays.equals(richer.record(2), CameraPresetProjection.identityCurve()), "NP3 curve was lost");
        check((richer.field(10)[0] & 255) == 136 && (richer.field(11)[0] & 255) == 124, "Legacy integer-to-quarter conversion changed colour");
        check(PresetPreviewProfiles.fromPreset(PresetFormatConversion.plan(ncp, "NP3").bytes()).registrationName().equals("CONVERT TEST"), "Generated classic NP3 is not usable in shared previews");

        PresetFormatConversion.Plan legacy = PresetFormatConversion.plan(np2, "NCP");
        check(legacy.bytes().length == 52 && (legacy.bytes()[41] & 255) == 129, "NCP manual contrast was not quantized");
        check(row(legacy, "对比度", "approximate") && row(legacy, "清晰度", "omitted"), "NCP report does not match output capabilities");
        PictureControlData dataset = PictureControlData.parse(CameraPresetProjection.plan(legacy.bytes(), null, null).conversion.dataBytes());
        check(dataset.contrast() == 4 && dataset.brightness() == 0 && !dataset.customCurveEnabled(), "Generated manual NCP is not usable in its normal camera import path");
        check(PresetPreviewProfiles.fromPreset(legacy.bytes()).registrationName().equals("HV240_NP2_STD"), "Manual NCP is not usable in previews");

        PresetFormatConversion.Plan compatible = PresetFormatConversion.plan(np3, "NP2");
        check(row(compatible, "色彩混合器", "omitted") && row(compatible, "分区调色", "omitted")
                && row(compatible, "中范围锐化", "omitted"), "Unsupported controls were not listed");
        check(Np3Container.read(compatible.bytes()).field(6)[0] == (byte) 135, "NP2 should retain quarter-step sharpening");
        try {
            PresetFormatConversion.plan(Arrays.copyOf(np3, np3.length - 1), "NP2");
            throw new AssertionError("Malformed source accepted");
        } catch (IOException expected) { checks++; }
        System.out.println("PASS " + checks + " format conversion checks, all six directions, reports, reload and unchanged originals");
        return checks;
    }
}
