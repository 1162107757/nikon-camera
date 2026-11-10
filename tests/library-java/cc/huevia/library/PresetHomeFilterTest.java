package cc.huevia.library;

import java.math.BigDecimal;
import java.util.*;

public final class PresetHomeFilterTest {
    private static int checks;
    public static void main(String[] args) throws Exception {
        List<OnlinePreset> catalog = new ArrayList<>();
        for (int i = 0; i < 390; i++) {
            Map<String,Object> map = new LinkedHashMap<>(); map.put("id", "row-" + i);
            map.put("name", i == 389 ? "NCP 名字的 NP3 天空" : "NP3 名字的预设 " + i);
            map.put("fileUrl", "https://example.invalid/misleading.ncp");
            map.put("sha256", String.format("%064x", i + 1)); map.put("byteLength", BigDecimal.valueOf(52));
            map.put("fileFormat", i % 2 == 0 ? "NCP" : "NP3"); map.put("category", i == 389 ? "风景" : "胶片");
            catalog.add(OnlinePreset.fromMap(map));
        }
        for (String category : List.of(PresetCategories.ALL, "胶片", "风景", ""))
            for (String type : List.of("", "NCP", "NP3"))
                for (String download : List.of("all", "saved", "missing")) {
                    PresetHomeFilter filter = new PresetHomeFilter(category, type, download);
                    int count = 0;
                    for (int i = 0; i < catalog.size(); i++) {
                        OnlinePreset row = catalog.get(i); boolean saved = i == 389;
                        if (filter.matches(row.category, row.fileFormat, saved, false)) count++;
                    }
                    int expected = 0;
                    for (int i = 0; i < 390; i++) if ((category.equals(PresetCategories.ALL) || category.equals(i == 389 ? "风景" : "胶片"))
                            && (type.isEmpty() || type.equals(i % 2 == 0 ? "NCP" : "NP3"))
                            && (download.equals("all") || download.equals("saved") == (i == 389))) expected++;
                    eq(expected, count, "full390 combination " + category + "/" + type + "/" + download);
                }
        PresetHomeFilter exact = new PresetHomeFilter("风景", "NP3", "saved");
        yes(exact.matches(catalog.get(389).category, catalog.get(389).fileFormat, true, false), "deep downloaded NP3 retained despite NCP display name and URL");
        yes(exact.matches("风景", "NP3", false, true), "local source ignores download condition");
        no(exact.matches("风景", "unknown", true, false), "unknown type excluded by explicit NP3");
        yes(PresetHomeFilter.empty().matches("", "unknown", false, false), "all includes unknown without inventing type");
        for (int version : new int[]{-1, 0, 2, 103, 171}) eq("", PresetHomeFilter.restoredType(version, "NP3"), "retired or foreign state cannot hide NCP " + version);
        eq("NP3", PresetHomeFilter.restoredType(1, "NP3"), "explicit versioned type restores");
        eq("", PresetHomeFilter.restoredType(1, "unknown"), "unknown state widens to all");
        PresetHomeFilter draft = exact.withCategory("胶片").withType("NCP").withDownload("missing");
        eq("风景", exact.category, "draft category does not mutate committed state");
        eq("NP3", exact.type, "draft type does not mutate committed state");
        eq("saved", exact.download, "draft download does not mutate committed state");
        yes(draft.active(false), "combined draft active");
        no(new PresetHomeFilter(PresetCategories.ALL, "", "saved").active(true), "hidden local download does not activate indicator");
        Map<String,Object> legacy = new LinkedHashMap<>(catalog.get(0).toMap()); legacy.remove("fileFormat");
        legacy.put("byteLength", BigDecimal.valueOf(52));
        eq("NCP", OnlinePreset.fromMap(legacy).fileFormat, "documented legacy NCP-only schema");
        legacy.put("fileFormat", "OTHER");
        try { OnlinePreset.fromMap(legacy); throw new AssertionError("unsupported metadata accepted"); }
        catch (java.io.IOException expected) { checks++; }
        System.out.println("PASS PresetHomeFilterTest " + checks + " checks; 36 full-catalog combinations, deep downloaded type, migration and independent drafts.");
    }
    private static void yes(boolean value, String label) { checks++; if (!value) throw new AssertionError(label); }
    private static void no(boolean value, String label) { yes(!value, label); }
    private static void eq(Object expected, Object actual, String label) { yes(Objects.equals(expected, actual), label + ": " + actual); }
}
