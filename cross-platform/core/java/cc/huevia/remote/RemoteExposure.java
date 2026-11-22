package cc.huevia.remote;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.TreeSet;

/** Nikon still-photo exposure and white balance on the authorized remote channel. */
public final class RemoteExposure {
    public static final int APERTURE = 0x5007;
    public static final int SHUTTER = 0x500d;
    public static final int ISO = 0x500f;
    public static final int COMPENSATION = 0x5010;
    public static final int WHITE_BALANCE = 0x5005;
    public static final int COLOR_TEMPERATURE = 0xd01e;
    public static final int TEMPERATURE_MODE = 0x8012;
    private static final int MAX_OPTIONS = 2048;

    public final long current;
    public final List<Long> choices;
    private final int size;

    private RemoteExposure(long current, List<Long> choices, int size) {
        this.current = current;
        this.choices = List.copyOf(choices);
        this.size = size;
    }

    public static boolean allows(int code) {
        return code == APERTURE || code == SHUTTER || code == ISO || code == COMPENSATION ||
                code == WHITE_BALANCE || code == COLOR_TEMPERATURE;
    }

    public static RemoteExposure parse(int code, byte[] bytes) throws IOException {
        if (!allows(code)) throw new IOException("此参数不支持遥控调节。");
        RemoteProperty descriptor = RemoteProperty.descriptor(code, bytes);
        int size = size(code);
        int type = code == COMPENSATION ? 3 : size == 4 ? 6 : 4;
        if (descriptor.type != type || bytes[4] < 0 || bytes[4] > 1) {
            throw new IOException("机身提供的参数档位格式不受支持。");
        }
        int tail = 5 + size * 2;
        var choices = new TreeSet<Long>();
        if (bytes[4] == 1 && bytes[tail] == 2) {
            int count = RemoteProperty.u16(bytes, tail + 1);
            if (count > MAX_OPTIONS) throw new IOException("机身提供的参数档位过多。");
            for (int i = 0; i < count; i++) {
                long value = scalar(code, bytes, tail + 3 + i * size);
                if (acceptsValue(code, value)) choices.add(value);
            }
        } else if (bytes[4] == 1 && bytes[tail] == 1) {
            long first = scalar(code, bytes, tail + 1);
            long last = scalar(code, bytes, tail + 1 + size);
            long step = scalar(code, bytes, tail + 1 + 2 * size);
            if (step <= 0 || first > last) throw new IOException("参数档位范围无效。");
            if ((last - first) / step < MAX_OPTIONS) {
                for (long value = first; value <= last; value += step) {
                    if (acceptsValue(code, value)) choices.add(value);
                }
            }
        }
        return new RemoteExposure(descriptor.value, new ArrayList<>(choices), size);
    }

    public byte[] encode(long value) throws IOException {
        if (!choices.contains(value)) throw new IOException("机身当前设置不允许这个档位。");
        byte[] result = new byte[size];
        for (int i = 0; i < size; i++) result[i] = (byte) (value >>> (8 * i));
        return result;
    }

    public static long read(int code, byte[] bytes) throws IOException {
        if (!allows(code) || bytes.length != size(code)) {
            throw new IOException("无法确认机身返回的参数值。");
        }
        return scalar(code, bytes, 0);
    }

    public static boolean acceptsValue(int code, long value) {
        switch (code) {
            case COMPENSATION: return value >= Short.MIN_VALUE && value <= Short.MAX_VALUE;
            case WHITE_BALANCE: return value >= 1 && value <= 7 || value >= 0x8010 && value <= 0x8016;
            case COLOR_TEMPERATURE: return value >= 1000 && value <= 20000;
            case SHUTTER: return value > 0 && value < 0xfffffffdL;
            case APERTURE: return value > 0 && value < 65535;
            case ISO: return value > 0 && value <= 65535;
            default: return false;
        }
    }

    private static int size(int code) { return code == SHUTTER ? 4 : 2; }

    private static long scalar(int code, byte[] bytes, int offset) {
        long value = 0;
        for (int i = 0; i < size(code); i++) value |= (bytes[offset + i] & 255L) << (8 * i);
        return code == COMPENSATION ? (short)value : value;
    }
}
