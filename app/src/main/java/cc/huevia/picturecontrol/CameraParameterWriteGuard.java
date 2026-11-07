package cc.huevia.picturecontrol;

import java.io.IOException;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.Map;

/** One immutable authorization, one attempt per exact property/value; never rearms on failure. */
public final class CameraParameterWriteGuard {
    private boolean authorized;
    private final Map<Integer, byte[]> approved = new LinkedHashMap<>();
    public void authorize(Map<Integer, byte[]> values) throws IOException {
        if (authorized || values == null || values.size() > 3) throw new IOException("参数授权已使用或无效。");
        Map<Integer, byte[]> checked = new LinkedHashMap<>();
        for (Map.Entry<Integer, byte[]> entry : values.entrySet()) {
            byte[] b = entry.getValue();
            if (!allowedCode(entry.getKey()) || b == null || b.length != 2)
                throw new IOException("参数授权超出允许范围。");
            checked.put(entry.getKey(), b.clone());
        }
        authorized = true; approved.putAll(checked);
    }
    public void consume(byte[] bytes, long[] parameters) throws IOException {
        if (!authorized || parameters == null || parameters.length != 1
                || !allowedCode(parameters[0])) throw new IOException("未授权此机身参数写入。");
        byte[] expected = approved.get((int) parameters[0]);
        if (expected == null || !Arrays.equals(expected, bytes)) throw new IOException("参数值与用户确认不一致，或已尝试写入。");
        approved.remove((int) parameters[0]);
    }
    public static boolean propertyRead(int operation, long[] p) {
        return (operation == 0x1014 || operation == 0x1015) && p != null && p.length == 1
                && allowedCode(p[0]);
    }
    public static boolean allowedCode(long code) { return code == 0x5005 || code == 0x5010 || code == 0xd01e; }
}
