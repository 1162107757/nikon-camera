package cc.huevia.shared;

import cc.huevia.ptp.PtpDeviceInfo;
import cc.huevia.ptp.PtpResponseException;
import cc.huevia.remote.NikonRemoteCamera;
import cc.huevia.remote.RemoteExposure;
import cc.huevia.remote.RemoteTransport;
import java.io.IOException;
import java.io.InterruptedIOException;
import java.util.function.BooleanSupplier;

/** Revocable remote operations over the already-owned USB photo session. */
public final class SharedWiredRemote implements RemoteTransport, AutoCloseable {
    private static final int DEVICE_READY = 0x90c8;
    public interface Wire {
        boolean isOpen();
        byte[] exchange(int operation, int maximum, byte[] outgoing, long... parameters) throws IOException;
    }

    private final Wire wire;
    private final PtpDeviceInfo device;
    private boolean closed;

    SharedWiredRemote(Wire wire, PtpDeviceInfo device) throws IOException {
        if (wire == null || !wire.isOpen() || !device.isNikonCamera()) {
            throw new IOException("此 USB 连接未提供尼康遥控通道。");
        }
        this.wire = wire;
        this.device = device;
    }

    @Override public boolean isOpen() { return !closed && wire.isOpen(); }
    @Override public void close() { closed = true; }

    boolean canWriteExposure() { return device.supportsOperation(0x1016); }

    void checkReady() throws IOException {
        if (!device.supportsOperation(DEVICE_READY)) return;
        try {
            command(DEVICE_READY);
        } catch (PtpResponseException response) {
            if (response.responseCode() != 0x2005) throw response;
        }
    }

    @Override public byte[] data(int operation, int maximum, long... p) throws IOException {
        require(operation, p);
        int limit = 0;
        if (operation == NikonRemoteCamera.FRAME && p.length == 0) limit = 8 * 1024 * 1024;
        if (operation == 0x90ca && p.length == 0) limit = 65536;
        if (operation == 0x1004 && p.length == 0) limit = 4096;
        if (operation == 0x1007 && p.length == 3) limit = 1024 * 1024;
        if ((operation == 0x1008 || operation == 0x100a) && p.length == 1 && p[0] > 0 && p[0] < 0xffffffffL) {
            limit = operation == 0x1008 ? 65536 : 4 * 1024 * 1024;
        }
        if ((operation == 0x1014 || operation == 0x1015) && p.length == 1 && p[0] <= 0xffff) {
            for (int property : NikonRemoteCamera.PROPERTIES) {
                if (p[0] == property) limit = operation == 0x1014 ? 65536 : 16;
            }
        }
        if (maximum < 1 || maximum > limit) throw new IOException("USB 遥控读取超出授权范围。");
        return wire.exchange(operation, maximum, null, p);
    }

    @Override public void command(int operation, long... p) throws IOException {
        require(operation, p);
        boolean allowed;
        switch (operation) {
            case NikonRemoteCamera.START:
            case NikonRemoteCamera.END:
            case NikonRemoteCamera.AF:
            case DEVICE_READY:
                allowed = p.length == 0;
                break;
            case NikonRemoteCamera.AREA:
                allowed = p.length == 2 && p[0] <= 16384 && p[1] <= 16384;
                break;
            case NikonRemoteCamera.CAPTURE:
                allowed = p.length == 2 && p[0] == 0xffffffffL && p[1] == 0;
                break;
            default:
                allowed = false;
        }
        if (!allowed) throw new IOException("USB 遥控操作超出授权范围。");
        wire.exchange(operation, 0, null, p);
    }

    void setExposure(int code, long value, BooleanSupplier cancel) throws IOException {
        if (!canWriteExposure() || !RemoteExposure.allows(code)) throw new IOException("相机未开放此项曝光调节。");
        RemoteExposure property = RemoteExposure.parse(code, data(0x1014, 65536, code));
        byte[] bytes = property.encode(value);
        if (property.current == value) return;
        if (cancel.getAsBoolean()) throw new InterruptedIOException("曝光调节已取消。");
        require(0x1016, new long[]{code});
        wire.exchange(0x1016, 0, bytes, code);
    }

    private void require(int operation, long[] p) throws IOException {
        if (!isOpen() || !device.supportsOperation(operation)) throw new IOException("相机未提供此项 USB 遥控能力。");
        for (long value : p) {
            if (value < 0 || value > 0xffffffffL) throw new IOException("USB 遥控参数无效。");
        }
    }
}
