package cc.huevia.usb;

import java.io.IOException;
import java.math.BigInteger;

/** Strict scalar descriptor including GetSet, enum and stepped range constraints. */
public final class CameraParameterDescriptor {
    public final int code, type, size;
    public final boolean writable;
    public final long current;
    private final int form;
    private final long[] constraints;
    private CameraParameterDescriptor(int code, int type, boolean writable, long current, int form, long[] constraints) {
        this.code = code; this.type = type; this.size = 1 << ((type - 1) / 2);
        this.writable = writable; this.current = current; this.form = form; this.constraints = constraints;
    }
    public static CameraParameterDescriptor parse(int code, byte[] bytes) throws IOException {
        if (bytes == null || bytes.length < 8 || u16(bytes, 0) != code) throw invalid();
        int type = u16(bytes, 2);
        if (!CameraParameterRequest.allowedCode(code)
                || type != (code == CameraParameterRequest.EXPOSURE_BIAS ? 3 : 4)) throw invalid();
        // Only the audited standard property scalar types, not arbitrary 64-bit or arrays.
        if (type < 1 || type > 6 || (bytes[4] != 0 && bytes[4] != 1)) throw invalid();
        int size = 1 << ((type - 1) / 2), at = 5 + size * 2;
        if (at >= bytes.length) throw invalid();
        int form = bytes[at++] & 255, count;
        if (form == 0) count = 0;
        else if (form == 1) count = 3;
        else if (form == 2 && at + 2 <= bytes.length) { count = u16(bytes, at); at += 2; }
        else throw invalid();
        if (count > 2048 || bytes.length != at + size * count) throw invalid();
        long[] constraints = new long[count];
        for (int i = 0; i < count; i++) constraints[i] = scalar(bytes, at + i * size, type);
        if (form == 1 && (constraints[0] > constraints[1] || constraints[2] <= 0)) throw invalid();
        return new CameraParameterDescriptor(code, type, bytes[4] == 1, scalar(bytes, 5 + size, type), form, constraints);
    }
    public boolean accepts(long value) {
        long low = (type & 1) == 1 ? -(1L << (size * 8 - 1)) : 0;
        long high = (type & 1) == 1 ? (1L << (size * 8 - 1)) - 1 : (1L << (size * 8)) - 1;
        if (!writable || value < low || value > high) return false;
        if (form == 0) return false; // No declared constraints: do not guess a writable range.
        if (form == 1) return value >= constraints[0] && value <= constraints[1]
                && BigInteger.valueOf(value).subtract(BigInteger.valueOf(constraints[0]))
                .mod(BigInteger.valueOf(constraints[2])).signum() == 0;
        for (long option : constraints) if (option == value) return true;
        return false;
    }
    public byte[] encode(long value) throws IOException {
        if (!accepts(value)) throw new IOException("相机当前模式不允许所选" + CameraParameterRequest.name(code) + "。");
        byte[] bytes = new byte[size]; for (int i = 0; i < size; i++) bytes[i] = (byte) (value >> (i * 8));
        return bytes;
    }
    public long read(byte[] bytes) throws IOException {
        if (bytes == null || bytes.length != size) throw invalid();
        return scalar(bytes, 0, type);
    }
    private static long scalar(byte[] bytes, int at, int type) {
        int size = 1 << ((type - 1) / 2); long value = 0;
        for (int i = 0; i < size; i++) value |= (bytes[at + i] & 255L) << (8 * i);
        return (type & 1) == 1 ? (value << (64 - size * 8)) >> (64 - size * 8) : value;
    }
    private static int u16(byte[] b, int at) { return (b[at] & 255) | (b[at + 1] & 255) << 8; }
    private static IOException invalid() { return new IOException("机身参数描述不完整或不受支持。"); }
}
