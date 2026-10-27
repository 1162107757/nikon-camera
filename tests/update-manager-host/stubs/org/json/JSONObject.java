package org.json;
import java.util.Map;
import java.util.LinkedHashMap;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;
/** Object fixture registry, not a JSON parser; Android JSON syntax needs native validation. */
public final class JSONObject {
    public static final Object NULL = new Object();
    private static final Map<String, Map<String, Object>> SAVED = new ConcurrentHashMap<>();
    private static final AtomicLong NEXT = new AtomicLong();
    private final Map<String, Object> fields = new LinkedHashMap<>();
    public JSONObject() {}
    public JSONObject(String encoded) {
        Map<String, Object> saved = SAVED.get(encoded);
        if (saved == null) throw new IllegalArgumentException("unregistered JSON fixture");
        fields.putAll(saved);
    }
    public JSONObject put(String key, Object value) { fields.put(key, value == null ? NULL : value); return this; }
    public boolean has(String key) { return fields.containsKey(key); }
    public Object get(String key) { if (!has(key)) throw new IllegalArgumentException(key); return fields.get(key); }
    public boolean isNull(String key) { return !has(key) || fields.get(key) == NULL; }
    public String optString(String key) { Object value = fields.get(key); return value == null || value == NULL ? "" : String.valueOf(value); }
    public long optLong(String key) { return optLong(key, 0); }
    public long optLong(String key, long fallback) { Object value = fields.get(key); return value instanceof Number ? ((Number) value).longValue() : fallback; }
    public int optInt(String key) { return (int) optLong(key); }
    public JSONObject optJSONObject(String key) { Object value = fields.get(key); return value instanceof JSONObject ? (JSONObject) value : null; }
    public JSONObject getJSONObject(String key) { JSONObject value = optJSONObject(key); if (value == null) throw new IllegalArgumentException(key); return value; }
    @Override public String toString() { String key = "json-fixture-" + NEXT.incrementAndGet(); SAVED.put(key, new LinkedHashMap<>(fields)); return key; }
}
