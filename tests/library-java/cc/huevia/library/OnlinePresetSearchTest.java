package cc.huevia.library;

import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.cert.Certificate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicLong;
import javax.net.ssl.HttpsURLConnection;

public final class OnlinePresetSearchTest {
    private static int checks;
    public static void main(String[] args) throws Exception {
        List<OnlinePreset> rows = new ArrayList<>();
        for (int i = 0; i < 389; i++) rows.add(item("preset-" + i, "预设 " + i, "胶片"));
        rows.add(item("b798456f-e181-4944-95c0-f91a6cd0763c", "蔚蓝天空", "风景"));
        Fake source = new Fake(rows); AtomicLong clock = new AtomicLong(1000);
        OnlinePresetSearch search = new OnlinePresetSearch(source, clock::get);
        OnlinePresetSearch.Snapshot snapshot = search.load(false);
        yes(snapshot.available && !snapshot.fromCache, "complete online index");
        eq(390, snapshot.presets.size(), "index includes all pages");
        eq(1, snapshot.matching("蔚蓝天空", PresetCategories.ALL).size(), "find preset after first 20 and first 50");
        eq(1, snapshot.matching(" 天空 ", "风景").size(), "trimmed partial Chinese name and category");
        eq(0, snapshot.matching("蔚蓝天空", "胶片").size(), "category still applies");
        eq(0, snapshot.matching("蔚蓝天空", "").size(), "uncategorized filter does not include landscape");
        eq(390, snapshot.matching("", PresetCategories.ALL).size(), "empty query returns complete index");
        eq(0, snapshot.matching("不存在的预设", PresetCategories.ALL).size(), "valid empty match");
        for (String q : new String[]{"蔚", "蔚蓝", "蔚蓝天", "蔚蓝天空", "天空", ""}) {
            snapshot.matching(q, PresetCategories.ALL); search.load(false);
        }
        eq(1, source.fetches, "typing reuses index instead of fetching per character");
        eq(0, source.cacheReads, "successful search never reads fallback");
        yes(OnlinePresetSearch.matchesName(" Ｆｉｌｍ １００ ", "film 100"), "width normalization and case folding");
        yes(OnlinePresetSearch.matchesName("Velvia", "vELVIA"), "case insensitive");
        no(OnlinePresetSearch.matchesName("蔚蓝天空", "蔚蓝天空1"), "no invented result");
        immutable(() -> snapshot.presets.clear(), "immutable catalog");
        immutable(() -> snapshot.categories.clear(), "immutable categories");
        immutable(() -> snapshot.matching("天空", PresetCategories.ALL).clear(), "immutable matches");
        search.load(true); eq(2, source.fetches, "explicit refresh bypasses fresh memo");
        clock.addAndGet(300001); search.load(false); eq(3, source.fetches, "stale index refreshes");
        clock.set(0); search.load(false); eq(4, source.fetches, "clock rollback cannot extend stale index");
        source.online = false; source.disk = true;
        OnlinePresetSearch.Snapshot cached = search.load(true);
        yes(cached.available && cached.fromCache, "offline full disk index labeled cached");
        eq(1, cached.matching("天空", PresetCategories.ALL).size(), "offline full-index name match");
        source.disk = false;
        cached = search.load(true); yes(cached.available && cached.fromCache, "retains previous full index after refresh failure");
        Fake unavailable = new Fake(rows); unavailable.online = false;
        OnlinePresetSearch emptySearch = new OnlinePresetSearch(unavailable, clock::get);
        OnlinePresetSearch.Snapshot failed = emptySearch.load(false);
        no(failed.available, "network error without full cache is not zero search matches");
        eq(0, failed.presets.size(), "partial page never substituted");
        unavailable.online = true;
        yes(emptySearch.load(false).available, "failure does not poison next retry");
        Fake validEmpty = new Fake(List.of());
        yes(new OnlinePresetSearch(validEmpty, clock::get).load(false).available, "valid empty catalog distinct from failure");
        realRepositoryIndex(rows);
        System.out.println("PASS OnlinePresetSearchTest " + checks + " checks; complete-catalog search, query reuse, categories, cache/error distinction and metadata-only HTTP.");
    }

    private static void realRepositoryIndex(List<OnlinePreset> rows) throws Exception {
        List<Object> raw = new ArrayList<>(); for (OnlinePreset p : rows) raw.add(p.toMap());
        byte[] manifest = LibraryJson.stringify(Map.of("version", 1, "presets", raw)).getBytes(StandardCharsets.UTF_8);
        List<String> urls = new ArrayList<>();
        SecureHttpClient http = new SecureHttpClient(url -> { urls.add(url.toString()); return new Connection(url, manifest); });
        File dir = Files.createTempDirectory("online-search171-").toFile();
        OnlinePresetRepository repository = new OnlinePresetRepository(dir, new PresetLibrary(dir), http);
        repository.useManagedEndpoint(OnlinePresetRepository.MANAGED_CATALOG_URL);
        OnlinePresetSearch engine = new OnlinePresetSearch(repository);
        OnlinePresetSearch.Snapshot result = engine.load(false);
        eq(1, result.matching("蔚蓝天空", PresetCategories.ALL).size(), "real validated repository includes deep item");
        eq(List.of(OnlinePresetRepository.MANAGED_CATALOG_URL), urls, "one metadata request, no page/image/preset downloads");
        engine.load(false); eq(1, urls.size(), "warm search performs no HTTP");
        eq(390, repository.cachedCatalog().presets.size(), "entire validated index persists in existing metadata cache");
    }

    private static OnlinePreset item(String id, String name, String category) throws Exception {
        Map<String,Object> map = new LinkedHashMap<>(); map.put("id", id); map.put("name", name);
        map.put("description", ""); map.put("fileUrl", "https://example.invalid/preset.ncp");
        map.put("previewUrl", "https://example.invalid/sample.jpg"); map.put("sha256", "0".repeat(64));
        map.put("byteLength", java.math.BigDecimal.valueOf(52)); map.put("category", category); map.put("compatibleModels", List.of());
        return OnlinePreset.fromMap(map);
    }
    private static final class Fake implements OnlinePresetSearch.Source {
        final List<OnlinePreset> rows; int fetches, cacheReads; boolean online = true, disk;
        Fake(List<OnlinePreset> rows) { this.rows = rows; }
        public OnlinePresetRepository.CatalogResult fetch() { fetches++; return new OnlinePresetRepository.CatalogResult(online ? "ok" : "error", "", online ? rows : List.of(), false); }
        public OnlinePresetRepository.CatalogResult cached() { cacheReads++; return new OnlinePresetRepository.CatalogResult(disk ? "cached" : "no_cache", "", disk ? rows : List.of(), true); }
    }
    private static final class Connection extends HttpsURLConnection {
        private final byte[] data;
        Connection(URL url, byte[] data) { super(url); this.data = data; }
        public int getResponseCode() { return 200; }
        public long getContentLengthLong() { return data.length; }
        public InputStream getInputStream() { return new ByteArrayInputStream(data); }
        public void disconnect() { }
        public boolean usingProxy() { return false; }
        public void connect() { }
        public String getCipherSuite() { return "TEST"; }
        public Certificate[] getLocalCertificates() { return new Certificate[0]; }
        public Certificate[] getServerCertificates() { return new Certificate[0]; }
    }
    private static void immutable(Runnable r, String label) { try { r.run(); throw new AssertionError(label); } catch (UnsupportedOperationException expected) { checks++; } }
    private static void no(boolean value, String label) { yes(!value, label); }
    private static void yes(boolean value, String label) { checks++; if (!value) throw new AssertionError(label); }
    private static void eq(Object expected, Object actual, String label) { checks++; if (!java.util.Objects.equals(expected, actual)) throw new AssertionError(label + ": " + actual); }
}
