package cc.huevia.album;

import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.atomic.AtomicReference;
import java.util.zip.CRC32;

/** Informational real loopback TCP benchmark. No camera, Wi-Fi, image decode or disk. */
public final class PtpIpTcpThroughputBenchmark {
    private static final int BYTES = 32 * 1024 * 1024;

    public static void main(String[] args) throws Exception {
        int trials = args.length == 0 ? 3 : Integer.parseInt(args[0]);
        for (int chunk : new int[] {1024, 16384, 65536, 262144}) {
            for (int trial = 0; trial < trials; trial++) run(chunk, trial);
        }
    }

    private static void run(int chunk, int trial) throws Exception {
        try (Peer peer = new Peer(chunk)) {
            List<MeasuredSocket> sockets = new ArrayList<>();
            try (PtpIpClient client = new PtpIpClient((host, port, timeout) -> {
                MeasuredSocket socket = new MeasuredSocket();
                socket.connect(new InetSocketAddress(InetAddress.getLoopbackAddress(), port), timeout);
                sockets.add(socket); return socket;
            })) {
                client.connect("127.0.0.1", peer.port(), new byte[16], "Loopback benchmark");
                MeasuredSocket command = sockets.get(0);
                command.timeouts = 0; command.reads = 0;
                CRC32 checksum = new CRC32(); long[] written = {0}, progress = {0};
                OutputStream sink = new OutputStream() {
                    @Override public void write(int value) { checksum.update(value); written[0]++; }
                    @Override public void write(byte[] bytes, int offset, int length) {
                        checksum.update(bytes, offset, length); written[0] += length;
                    }
                };
                long began = System.nanoTime();
                long received = client.readTo(0x1009, sink, BYTES, BYTES, (done, total) -> {
                    if (done < progress[0] || done > total || total != BYTES) throw new AssertionError("Progress boundary");
                    progress[0] = done;
                }, 42);
                long elapsed = System.nanoTime() - began;
                int timeoutCalls = command.timeouts, readCalls = command.reads;
                if (received != BYTES || written[0] != BYTES || progress[0] != BYTES
                        || checksum.getValue() != peer.expectedCrc || !client.isOpen()) throw new AssertionError("Incomplete original");
                if (!Arrays.equals(new byte[] {1, 4, 9}, client.getData(0x1001, 32))) throw new AssertionError("Lost transaction boundary");
                System.out.println("TCP_BENCH chunk=" + chunk + " trial=" + trial + " bytes=" + received
                        + " elapsed_us=" + (elapsed / 1000) + " reads=" + readCalls + " set_timeout_calls=" + timeoutCalls
                        + " crc32=" + checksum.getValue() + " transport=loopback_tcp sink=crc_no_disk");
            }
            peer.check();
        }
    }

    private static final class MeasuredSocket extends Socket {
        int timeouts, reads;
        @Override public synchronized void setSoTimeout(int value) throws SocketException { super.setSoTimeout(value); timeouts++; }
        @Override public InputStream getInputStream() throws IOException {
            return new FilterInputStream(super.getInputStream()) {
                @Override public int read(byte[] b, int off, int len) throws IOException { reads++; return in.read(b, off, len); }
            };
        }
    }

    private static final class Peer implements AutoCloseable {
        final ServerSocket server;
        final Thread thread;
        final AtomicReference<Throwable> error = new AtomicReference<>();
        volatile Socket command, events;
        final byte[] payload;
        final long expectedCrc;
        Peer(int chunk) throws IOException {
            server = new ServerSocket(0, 2, InetAddress.getLoopbackAddress());
            server.setSoTimeout(10000);
            payload = new byte[chunk];
            for (int i = 0; i < payload.length; i++) payload[i] = (byte) i;
            CRC32 crc = new CRC32();
            for (int at = 0; at < BYTES; at += chunk) crc.update(payload);
            expectedCrc = crc.getValue();
            thread = new Thread(this::serve, "ptpip-loopback-peer"); thread.setDaemon(true); thread.start();
        }
        int port() { return server.getLocalPort(); }
        void serve() {
            try {
                command = server.accept(); command.setTcpNoDelay(true); command.setSoTimeout(10000);
                InputStream in = command.getInputStream();
                OutputStream out = new BufferedOutputStream(command.getOutputStream(), 256 * 1024);
                byte[] init = packet(in);
                if (u32(init, 4) != 1) throw new IOException("Expected command init");
                byte[] name = "Loopback\0".getBytes(StandardCharsets.UTF_16LE);
                frame(out, 2, join(le32(1), new byte[16], name, le32(0x10000))); out.flush();
                events = server.accept(); events.setSoTimeout(10000);
                if (u32(packet(events.getInputStream()), 4) != 3) throw new IOException("Expected event init");
                frame(events.getOutputStream(), 4, new byte[0]); events.getOutputStream().flush();
                while (true) {
                    byte[] request;
                    try { request = packet(in); } catch (EOFException done) { break; }
                    if (u32(request, 4) != 6) throw new IOException("Unexpected request");
                    int operation = (request[12] & 255) | ((request[13] & 255) << 8);
                    long tx = u32(request, 14);
                    if (operation == 0x1001) {
                        frame(out, 9, join(le32(tx), le64(3)));
                        frame(out, 12, join(le32(tx), new byte[] {1, 4, 9}));
                    } else if (operation == 0x1009) {
                        frame(out, 9, join(le32(tx), le64(BYTES)));
                        for (int at = 0; at < BYTES; at += payload.length) {
                            out.write(le32(payload.length + 12)); out.write(le32(at + payload.length == BYTES ? 12 : 10));
                            out.write(le32(tx)); out.write(payload);
                        }
                    } else if (operation != 0x1002 && operation != 0x1003) throw new IOException("Unexpected camera operation");
                    frame(out, 7, join(new byte[] {1, 32}, le32(tx))); out.flush();
                }
            } catch (Throwable problem) { if (!server.isClosed()) error.set(problem); }
        }
        void check() throws Exception {
            thread.join(2000);
            if (error.get() != null) throw new AssertionError("Loopback server", error.get());
            if (thread.isAlive()) throw new AssertionError("Server did not drain");
        }
        @Override public void close() throws IOException {
            server.close(); if (command != null) command.close(); if (events != null) events.close();
        }
    }

    private static byte[] packet(InputStream in) throws IOException {
        byte[] header = in.readNBytes(8); if (header.length != 8) throw new EOFException();
        int length = (int) u32(header, 0); if (length < 8 || length > 4096) throw new IOException("Invalid request length");
        byte[] body = in.readNBytes(length - 8); if (body.length != length - 8) throw new EOFException();
        return join(header, body);
    }
    private static void frame(OutputStream out, int type, byte[] bytes) throws IOException {
        out.write(le32(bytes.length + 8)); out.write(le32(type)); out.write(bytes);
    }
    private static long u32(byte[] b, int off) { return (b[off] & 255L) | ((b[off + 1] & 255L) << 8) | ((b[off + 2] & 255L) << 16) | ((b[off + 3] & 255L) << 24); }
    private static byte[] le32(long value) { return new byte[] {(byte) value, (byte) (value >>> 8), (byte) (value >>> 16), (byte) (value >>> 24)}; }
    private static byte[] le64(long value) { return join(le32(value), le32(value >>> 32)); }
    private static byte[] join(byte[]... arrays) {
        ByteArrayOutputStream out = new ByteArrayOutputStream(); for (byte[] array : arrays) out.writeBytes(array); return out.toByteArray();
    }
}
