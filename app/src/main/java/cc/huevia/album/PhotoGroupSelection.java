package cc.huevia.album;
import java.util.Collection;
import java.util.LinkedHashSet;
import java.util.Set;
/** Selection only: callers supply eligible keys from their current source/date snapshot. */
public final class PhotoGroupSelection {
    public enum State { NONE, PARTIAL, ALL }
    private PhotoGroupSelection() {}
    public static State state(Collection<String> members, Set<String> selected) {
        Set<String> keys = keys(members); int count = 0;
        for (String key : keys) if (selected.contains(key)) count++;
        return count == 0 ? State.NONE : count == keys.size() ? State.ALL : State.PARTIAL;
    }
    /** Atomic limit check prevents silently selecting just the first N photos. */
    public static boolean toggle(Collection<String> members, Set<String> selected, int maximum) {
        Set<String> keys = keys(members);
        if (keys.isEmpty()) return false;
        if (state(keys, selected) == State.ALL) { selected.removeAll(keys); return true; }
        Set<String> next = new LinkedHashSet<>(selected); next.addAll(keys);
        if (next.size() > maximum) return false;
        selected.addAll(keys); return true;
    }
    private static Set<String> keys(Collection<String> members) {
        Set<String> keys = new LinkedHashSet<>();
        for (String key : members) if (key != null && !key.isEmpty()) keys.add(key);
        return keys;
    }
}
