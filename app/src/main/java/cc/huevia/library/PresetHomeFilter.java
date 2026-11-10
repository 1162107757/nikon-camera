package cc.huevia.library;

/** Applied home conditions. Drafts are independent values; only Apply commits them. */
public final class PresetHomeFilter {
    public static final String ALL_DOWNLOADS = "all", NOT_DOWNLOADED = "missing", DOWNLOADED = "saved";
    public static final int STATE_VERSION = 1;
    public final String category, type, download;

    public PresetHomeFilter(String category, String type, String download) {
        this.category = category == null ? PresetCategories.ALL : category;
        this.type = normalizeType(type);
        this.download = normalizeDownload(download);
    }
    public static String normalizeType(String value) {
        return PresetFile.NCP.equals(value) || PresetFile.NP3.equals(value) ? value : "";
    }
    public static String normalizeDownload(String value) {
        return NOT_DOWNLOADED.equals(value) || DOWNLOADED.equals(value) ? value : ALL_DOWNLOADS;
    }
    /** Old retired format keys have no authority. Only this feature's versioned state can restore a type. */
    public static String restoredType(int version, String value) {
        return version == STATE_VERSION ? normalizeType(value) : "";
    }
    public boolean active(boolean local) {
        return !PresetCategories.ALL.equals(category) || !type.isEmpty() || !local && !ALL_DOWNLOADS.equals(download);
    }
    public boolean matches(String category, String actualType, boolean saved, boolean local) {
        // Unknown types remain visible in All, and never match an explicit NCP/NP3 choice.
        return (PresetCategories.ALL.equals(this.category) || this.category.equals(category))
                && (type.isEmpty() || type.equals(actualType))
                && (local || ALL_DOWNLOADS.equals(download) || (DOWNLOADED.equals(download) == saved));
    }
    public PresetHomeFilter withCategory(String value) { return new PresetHomeFilter(value, type, download); }
    public PresetHomeFilter withType(String value) { return new PresetHomeFilter(category, value, download); }
    public PresetHomeFilter withDownload(String value) { return new PresetHomeFilter(category, type, value); }
    public static PresetHomeFilter empty() { return new PresetHomeFilter(PresetCategories.ALL, "", ALL_DOWNLOADS); }
}
