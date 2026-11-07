package cc.huevia.album;

import android.content.Context;

import java.io.FilterInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InterruptedIOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.function.BooleanSupplier;
import java.util.zip.Inflater;
import java.util.zip.InflaterInputStream;

/** Restores the bundled, byte-for-byte official semantic model without changing its weights. */
final class FaceSkinModel {
    private static final String ASSET = "portrait/face_skin_multiclass.shuffle4.zlib";
    private static final int MODEL_BYTES = 16_371_837;
    private static final int PACKED_BYTES = 13_881_786;
    private static final int BUFFER_BYTES = 64 * 1024;
    private static final byte[] MODEL_SHA256 = hex(
            "c6748b1253a99067ef71f7e26ca71096cd449baefa8f101900ea23016507e0e0");
    private static final byte[] PACKED_SHA256 = hex(
            "9920fafc503c9090b3840c6fb433efc7eeb117bb00176b04034bd589c0e19bb0");
    private static volatile ByteBuffer cachedModel;

    private FaceSkinModel() {}

    static ByteBuffer load(Context context, BooleanSupplier cancelled) throws IOException {
        checkCancelled(cancelled);
        ByteBuffer ready = cachedModel;
        if (ready != null) return duplicate(ready);
        synchronized (FaceSkinModel.class) {
            checkCancelled(cancelled);
            ready = cachedModel;
            if (ready == null) {
                try (InputStream input = context.getAssets().open(ASSET)) {
                    ready = decode(input, cancelled).asReadOnlyBuffer().order(ByteOrder.nativeOrder());
                }
                checkCancelled(cancelled);
                cachedModel = ready;
            }
            return duplicate(ready);
        }
    }

    /** Reads one pinned zlib stream. The caller retains ownership of {@code input}. */
    static ByteBuffer decode(InputStream input, BooleanSupplier cancelled) throws IOException {
        checkCancelled(cancelled);
        if (input == null) throw new IOException("Missing bundled face skin model");
        MessageDigest packedDigest = sha256();
        ModelInput source = new ModelInput(input, packedDigest, cancelled);
        Inflater inflater = new Inflater();
        try {
            InflaterInputStream decoded = new InflaterInputStream(source, inflater, BUFFER_BYTES);
            ByteBuffer model = ByteBuffer.allocateDirect(MODEL_BYTES).order(ByteOrder.nativeOrder());
            byte[] block = new byte[BUFFER_BYTES];
            int words = MODEL_BYTES / 4;
            for (int plane = 0; plane < 4; plane++) {
                checkCancelled(cancelled);
                int word = 0;
                while (word < words) {
                    checkCancelled(cancelled);
                    int count = decoded.read(block, 0, Math.min(block.length, words - word));
                    if (count < 0) throw new IOException("Truncated face skin model byte plane");
                    if (count == 0) continue;
                    for (int index = 0; index < count; index++) {
                        model.put((word + index) * 4 + plane, block[index]);
                    }
                    word += count;
                }
            }
            for (int tail = words * 4; tail < MODEL_BYTES; tail++) {
                checkCancelled(cancelled);
                int value = decoded.read();
                if (value < 0) throw new IOException("Truncated face skin model tail");
                model.put(tail, (byte) value);
            }
            checkCancelled(cancelled);
            if (decoded.read() != -1) throw new IOException("Oversized decoded face skin model");
            if (!inflater.finished()) throw new IOException("Incomplete face skin model stream");
            if (inflater.getRemaining() != 0 || source.read() != -1) {
                throw new IOException("Trailing compressed face skin model data");
            }
            if (source.count != PACKED_BYTES) throw new IOException("Face skin model packed length mismatch");
            if (!MessageDigest.isEqual(PACKED_SHA256, packedDigest.digest())) {
                throw new IOException("Face skin model packed SHA-256 mismatch");
            }
            checkCancelled(cancelled);
            MessageDigest modelDigest = sha256();
            ByteBuffer hashInput = model.asReadOnlyBuffer();
            // Keep hashing cancellable without allocating a second model-sized array.
            while (hashInput.hasRemaining()) {
                checkCancelled(cancelled);
                int count = Math.min(block.length, hashInput.remaining());
                hashInput.get(block, 0, count);
                modelDigest.update(block, 0, count);
            }
            if (!MessageDigest.isEqual(MODEL_SHA256, modelDigest.digest())) {
                throw new IOException("Face skin model restored SHA-256 mismatch");
            }
            checkCancelled(cancelled);
            return model.asReadOnlyBuffer().order(ByteOrder.nativeOrder());
        } finally {
            // Supplied Inflater instances are caller-owned by InflaterInputStream.
            inflater.end();
        }
    }

    private static ByteBuffer duplicate(ByteBuffer model) {
        ByteBuffer result = model.asReadOnlyBuffer().order(ByteOrder.nativeOrder());
        result.position(0);
        result.limit(MODEL_BYTES);
        return result;
    }

    private static void checkCancelled(BooleanSupplier cancelled) throws InterruptedIOException {
        if (Thread.currentThread().isInterrupted() || (cancelled != null && cancelled.getAsBoolean())) {
            throw new InterruptedIOException("Face skin model loading cancelled");
        }
    }

    private static MessageDigest sha256() throws IOException {
        try {
            return MessageDigest.getInstance("SHA-256");
        } catch (NoSuchAlgorithmException error) {
            throw new IOException("SHA-256 unavailable for face skin model", error);
        }
    }

    private static byte[] hex(String text) {
        byte[] result = new byte[text.length() / 2];
        for (int index = 0; index < result.length; index++) {
            result[index] = (byte) Integer.parseInt(text.substring(index * 2, index * 2 + 2), 16);
        }
        return result;
    }

    private static final class ModelInput extends FilterInputStream {
        private final MessageDigest digest;
        private final BooleanSupplier cancelled;
        private int count;

        ModelInput(InputStream source, MessageDigest digest, BooleanSupplier cancelled) {
            super(source);
            this.digest = digest;
            this.cancelled = cancelled;
        }

        @Override public int read() throws IOException {
            checkCancelled(cancelled);
            int value = in.read();
            if (value >= 0) {
                if (++count > PACKED_BYTES) throw new IOException("Oversized packed face skin model");
                digest.update((byte) value);
            }
            return value;
        }

        @Override public int read(byte[] bytes, int offset, int length) throws IOException {
            checkCancelled(cancelled);
            int read = in.read(bytes, offset, length);
            if (read > 0) {
                count += read;
                if (count > PACKED_BYTES) throw new IOException("Oversized packed face skin model");
                digest.update(bytes, offset, read);
            }
            return read;
        }
    }
}
