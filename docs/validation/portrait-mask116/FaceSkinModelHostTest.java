package cc.huevia.album;

import java.io.*;
import java.nio.*;
import java.nio.file.*;
import java.security.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.BooleanSupplier;
import java.util.zip.*;

public final class FaceSkinModelHostTest {
    private static int checks;
    private static void require(boolean value, String name) {
        if (!value) throw new AssertionError(name);
        checks++;
    }
    private static void reject(byte[] packed, BooleanSupplier cancelled, String expected) throws Exception {
        try {
            FaceSkinModel.decode(new ByteArrayInputStream(packed), cancelled);
            throw new AssertionError("Accepted invalid/cancelled stream: " + expected);
        } catch (IOException error) {
            if (!expected.isEmpty()) require(error.getMessage().contains(expected), "Expected " + expected + ": " + error);
            else checks++;
        }
    }
    public static void main(String[] args) throws Exception {
        byte[] packed = Files.readAllBytes(Paths.get(args[0]));
        byte[] official = Files.readAllBytes(Paths.get(args[1]));
        ByteBuffer model = FaceSkinModel.decode(new ByteArrayInputStream(packed), () -> false);
        require(model.isDirect() && model.isReadOnly(), "read-only direct buffer");
        require(model.order().equals(ByteOrder.nativeOrder()), "native byte order");
        require(model.position() == 0 && model.remaining() == 16_371_837, "exact buffer limits");
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        digest.update(model.duplicate());
        require(Arrays.equals(digest.digest(), MessageDigest.getInstance("SHA-256").digest(official)), "official restored SHA-256");
        require(model.position() == 0, "caller position unchanged by hash");

        reject(Arrays.copyOf(packed, packed.length - 2), null, "");
        byte[] trailing = Arrays.copyOf(packed, packed.length + 1);
        trailing[trailing.length - 1] = 1;
        reject(trailing, null, "");
        byte[] badHeader = packed.clone(); badHeader[0] ^= 0x55;
        reject(badHeader, null, "");
        byte[] alternateHeader = packed.clone(); alternateHeader[0] = 0x78; alternateHeader[1] = (byte) 0x9c;
        reject(alternateHeader, null, "packed SHA-256");
        reject(packed, () -> true, "cancelled");
        AtomicInteger steps = new AtomicInteger();
        reject(packed, () -> steps.incrementAndGet() > 12, "cancelled");

        ByteArrayOutputStream bomb = new ByteArrayOutputStream();
        try (DeflaterOutputStream encoder = new DeflaterOutputStream(bomb)) {
            byte[] zeros = new byte[64 * 1024];
            int remaining = 16_371_838;
            while (remaining > 0) { int n = Math.min(remaining, zeros.length); encoder.write(zeros, 0, n); remaining -= n; }
        }
        reject(bomb.toByteArray(), null, "Oversized decoded");
        final boolean[] closed = {false};
        ByteArrayInputStream owned = new ByteArrayInputStream(packed) {
            @Override public void close() { closed[0] = true; }
        };
        FaceSkinModel.decode(owned, null);
        require(!closed[0], "decode leaves input ownership with caller");
        InputStream shortReads = new ByteArrayInputStream(packed) {
            @Override public synchronized int read(byte[] b, int off, int len) { return super.read(b, off, Math.min(257, len)); }
        };
        require(FaceSkinModel.decode(shortReads, null).remaining() == official.length, "short reads supported");
        System.out.println("PASS FaceSkinModel host decode: " + checks + " checks; official byte-exact SHA, bounded stream, cancellation, corruption, trailing bytes, short reads, stream ownership.");
    }
}
