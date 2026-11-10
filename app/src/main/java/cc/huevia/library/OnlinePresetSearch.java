package cc.huevia.library;

import java.text.Normalizer;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.function.LongSupplier;

/** Full-catalog name search; a list page is never a complete search index. */
public final class OnlinePresetSearch {
    private static final long FRESH_MILLIS = 5 * 60 * 1000L;
    interface Source {
        OnlinePresetRepository.CatalogResult fetch();
        OnlinePresetRepository.CatalogResult cached();
    }

    public static final class Snapshot {
        public final List<OnlinePreset> presets;
        public final Set<String> categories;
        public final boolean available, fromCache;
        public final String message;

        private Snapshot(List<OnlinePreset> items, boolean available, boolean fromCache, String message) {
            presets = Collections.unmodifiableList(new ArrayList<>(items));
            Set<String> values = new LinkedHashSet<>();
            for (OnlinePreset item : items) values.add(item.category);
            categories = Collections.unmodifiableSet(values);
            this.available = available; this.fromCache = fromCache; this.message = message;
        }

        public List<OnlinePreset> matching(String query, String category) {
            List<OnlinePreset> result = new ArrayList<>();
            for (OnlinePreset item : presets)
                if ((PresetCategories.ALL.equals(category) || item.category.equals(category)) && matchesName(item.name, query))
                    result.add(item);
            return Collections.unmodifiableList(result);
        }
    }

    private final Source source;
    private final LongSupplier clock;
    private Snapshot last;
    private long fetchedAt;

    public OnlinePresetSearch(OnlinePresetRepository repository) {
        this(new Source() {
            public OnlinePresetRepository.CatalogResult fetch() { return repository.fetchCatalog(); }
            public OnlinePresetRepository.CatalogResult cached() { return repository.cachedCatalog(); }
        }, System::currentTimeMillis);
    }

    OnlinePresetSearch(Source source, LongSupplier clock) { this.source = source; this.clock = clock; }

    /** Worker-thread only. Serialize index loads; keystrokes search the immutable returned snapshot. */
    public synchronized Snapshot load(boolean refresh) {
        long now = clock.getAsLong();
        if (!refresh && last != null && last.available && now >= fetchedAt && now - fetchedAt < FRESH_MILLIS)
            return last;
        OnlinePresetRepository.CatalogResult result = source.fetch();
        if ("ok".equals(result.status)) {
            last = new Snapshot(result.presets, true, false, ""); fetchedAt = now;
            return last;
        }
        OnlinePresetRepository.CatalogResult cached = source.cached();
        if ("cached".equals(cached.status)) {
            last = new Snapshot(cached.presets, true, true, "正在搜索缓存目录"); fetchedAt = now;
            return last;
        }
        if (last != null && last.available) {
            last = new Snapshot(last.presets, true, true, "正在搜索缓存目录"); fetchedAt = now;
            return last;
        }
        return new Snapshot(Collections.emptyList(), false, false, "暂时无法搜索，请联网后重试。");
    }

    public static boolean matchesName(String name, String query) {
        return normalized(name).contains(normalized(query));
    }

    private static String normalized(String value) {
        return Normalizer.normalize(value == null ? "" : value, Normalizer.Form.NFKC).trim().toLowerCase(Locale.ROOT);
    }
}
