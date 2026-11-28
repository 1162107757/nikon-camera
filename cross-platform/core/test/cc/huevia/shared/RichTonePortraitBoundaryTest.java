package cc.huevia.shared;

import cc.huevia.library.SharedJson;
import cc.huevia.ncp.Np3PresetDetails;
import cc.huevia.ncp.PhotoAdjustments;
import cc.huevia.ncp.PhotoCleanup;
import cc.huevia.ncp.PhotoColorPalette;
import cc.huevia.ncp.PhotoCurves;
import cc.huevia.ncp.PhotoHsl;
import cc.huevia.ncp.PhotoLocalEdits;
import cc.huevia.ncp.SpatialPreviewFilter;

import java.io.ByteArrayInputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.Base64;
import java.util.Map;

/** Exercises the NX Studio export from file intake through the shared preview and render paths. */
final class RichTonePortraitBoundaryTest {
    private RichTonePortraitBoundaryTest() {}

    // NX Studio 1.11.0, Rich Tone Portrait at its default settings.
    // SHA-256 af5a6dcd21676e13047d28f457ea529255a7daeca26bcb2c7eb794c9a6b6d01f
    static byte[] exportedPreset() {
        return Base64.getDecoder().decode(
                "TkNQAAAAAQAAAAAEMDMxMAAAAgAAAAAUUklDSFRPTkVQT1JUUkFJVC0wMgAAAAMAAAAAAgSTAAAEAAAAAAIAAAAABQ" +
                "AAAAAC/wEAAAYAAAAAAogEAAAHAAAAAAKEBAAACAAAAAACgAQAAAkAAAAAAoAEAAAKAAAAAAKABAAACwAAAAACgAQA" +
                "AAwAAAAAAv8AAAANAAAAAAL/AAAADgAAAAAC/wQAAA8AAAAAAv8BAAAQAAAAAAL/AQAAEQAAAAAC/wEAABIAAAAAAv" +
                "8BAAATAAAAAAL/AQAAFAAAAAACgAEAABUAAAAAAv8KAAAWAAAAAAKEBAAAFwAAAAAC/wQAABgAAAAAAv8EAAAZAAAA" +
                "AAKAAQAAGgAAAAACgAEAABsAAAAAAoABAAAcAAAAAAKAAQAAHQAAAAACgAEAAB4AAAAAAoABAAAfAAAAAByAgICAgI" +
                "CAgICAgICAgICAgICAgICAgIABAQEAAAAgAAAAABSAAICAgACAgIAAgIABAQEAsgGAAQABAQAAAACs5o2V5o2J5ouN" +
                "5pGE5a+56LGh6IKk6Imy55qE57uG6IqC77yM5ZCM5pe25YeP5bCR5Lqu6YOo57uG6IqC5o2f5aSx5LiU5Lqn55Sf5q" +
                "+UW+S6uuWDj13miYDojrflvpfmm7TpspzoibPnmoTmlYjmnpzjgILkuZ/pgILlkIjlsIbmnaXpnIDopoHov5vooYzl" +
                "pITnkIbmiJbmtqbppbDnmoTnhafniYfjgIIAAAAAAAA=");
    }

    static void run(SharedRuntime runtime, Path root) throws Exception {
        byte[] exported = exportedPreset();
        String name = "RICHTONEPORTRAIT-02.NP3";
        Map<String, Object> staged = SharedJson.object(SharedImport.copy(
                new ByteArrayInputStream(exported), name, true, root.toString(), () -> false));
        Map<String, Object> added = SharedJson.object(runtime.request("library.import",
                SharedJson.encode(SharedRuntime.map("owner", "", "name", name, "path", staged.get("path")))));
        Map<String, Object> record = SharedRuntime.object(added.get("record"));
        check("NP3".equals(record.get("fileFormat")), "library import format");

        String id = (String) record.get("id");
        Map<String, Object> inspection = SharedJson.object(runtime.request("library.inspect",
                SharedJson.encode(SharedRuntime.map("id", id))));
        check(Boolean.TRUE.equals(inspection.get("previewSupported")), "library preview capability");
        byte[] stored = Files.readAllBytes(runtime.privateFile((String) staged.get("path")).toPath());
        check(Arrays.equals(exported, stored), "import keeps the original Nikon bytes");
        Np3PresetDetails details = Np3PresetDetails.read(stored);
        check("丰富色调人像".equals(details.baseLabel) && details.previewSupported, "details in the library");
        check(details.groups.stream().noneMatch(group -> "单色".equals(group.title)), "colour detail rows");

        int[] original = {0xff14151b, 0x7fae7359, 0xffe0a883, 0xffbfdbed, 0xff000000, 0xffffffff};
        int[] values = PhotoAdjustments.NONE.values();
        int[] preview = CoreEngine.colourPreview(original, 3, 2, stored, 100, values);
        check(preview[1] != original[1] && preview[2] != original[2], "nonidentity portrait colour");
        check((preview[1] >>> 24) == 0x7f && preview[4] == original[4] && preview[5] == original[5],
                "alpha and black/white endpoints");
        check(Arrays.equals(original, CoreEngine.colourPreview(original, 3, 2, stored, 0, values)), "zero strength");

        int[] full = original.clone();
        CoreEngine.fullColour(new SpatialPreviewFilter.Pixels() {
            public int width() { return 3; }
            public int height() { return 2; }
            public void read(int[] output, int row, int rows) { System.arraycopy(full, row * 3, output, 0, rows * 3); }
            public void write(int[] input, int row, int rows) { System.arraycopy(input, 0, full, row * 3, rows * 3); }
        }, stored, 100, values, PhotoCurves.NONE, PhotoHsl.NONE, PhotoColorPalette.NONE, PhotoCleanup.NONE,
                PhotoLocalEdits.NONE, () -> false, ignored -> {});
        check(Arrays.equals(preview, full), "applied full-size colour agrees with preview");

        byte[] modified = exported.clone();
        modified[fieldOffset(modified, 10)] = (byte) 132;
        check(!Arrays.equals(preview, CoreEngine.colourPreview(original, 3, 2, modified, 100, values)),
                "manual saturation survives the portrait base");
        modified[fieldOffset(modified, 31)] = (byte) 132;
        Map<String, Object> unsupported = SharedJson.object(CoreEngine.inspectPreset(modified));
        check(Boolean.FALSE.equals(unsupported.get("previewSupported")), "unknown active controls stay gated");
        System.out.println("PASS NX Studio Rich Tone Portrait NP3 import, inspection, preview and full render");
    }

    private static int fieldOffset(byte[] bytes, int index) {
        java.nio.ByteBuffer data = java.nio.ByteBuffer.wrap(bytes);
        for (int offset = 4; offset < bytes.length - 8; offset += 8 + data.getInt(offset + 4)) {
            if (data.getInt(offset) == index * 256) return offset + 8;
        }
        throw new AssertionError("Missing NP3 control " + index);
    }

    private static void check(boolean ok, String operation) {
        if (!ok) throw new AssertionError("Rich Tone Portrait: " + operation);
    }
}
