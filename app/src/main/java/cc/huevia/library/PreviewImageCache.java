package cc.huevia.library;

import java.io.File;
import java.io.IOException;
import java.io.InterruptedIOException;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Comparator;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.FutureTask;

/** Bounded disk cache for optional online sample images. Saved library samples are read-only here. */
final class PreviewImageCache {
    private static final long MAX_BYTES = 100L * 1024 * 1024;
    private static final int MAX_FILES = 256;
    private static final Object DISK_LOCK = new Object();
    private static final ConcurrentHashMap<String, FutureTask<byte[]>> IN_FLIGHT = new ConcurrentHashMap<>();
    interface Fetcher { byte[] fetch() throws IOException; }
    interface Validator { void validate(byte[] bytes) throws IOException; }
    private final File directory, savedDirectory;
    private final String flightPrefix;
    private final int imageLimit, fileLimit;
    private final long byteLimit;
    private final Validator validator;

    PreviewImageCache(File directory, File savedDirectory, int imageLimit, Validator validator) throws IOException {
        this(directory, savedDirectory, imageLimit, validator, MAX_BYTES, MAX_FILES);
    }

    PreviewImageCache(File directory, File savedDirectory, int imageLimit, Validator validator,
                      long byteLimit, int fileLimit) throws IOException {
        this.directory = directory; this.savedDirectory = savedDirectory;
        this.imageLimit = imageLimit; this.validator = validator;
        this.byteLimit = byteLimit; this.fileLimit = fileLimit;
        flightPrefix = directory.getCanonicalPath() + File.separator;
    }

    byte[] read(String url, Fetcher fetcher) throws IOException {
        String name = LibraryFiles.sha256(url.getBytes(StandardCharsets.UTF_8)) + ".image";
        String flightKey = flightPrefix + name;
        FutureTask<byte[]> task = new FutureTask<>(() -> load(name, fetcher));
        FutureTask<byte[]> shared = IN_FLIGHT.putIfAbsent(flightKey, task);
        boolean owner = shared == null;
        if (owner) shared = task;
        try {
            if (owner) task.run();
            // Callers may mutate/decode independently; never expose the shared result buffer.
            return shared.get().clone();
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
            throw new InterruptedIOException("读取参考图已取消。");
        } catch (ExecutionException failed) {
            Throwable cause = failed.getCause();
            if (cause instanceof IOException) throw (IOException) cause;
            if (cause instanceof RuntimeException) throw (RuntimeException) cause;
            if (cause instanceof Error) throw (Error) cause;
            throw new IOException("参考图读取失败。", cause);
        } finally {
            if (owner) IN_FLIGHT.remove(flightKey, task);
        }
    }

    private byte[] load(String name, Fetcher fetcher) throws IOException {
        File file = new File(directory, name);
        synchronized (DISK_LOCK) {
            // Saved samples can predate this cache and must remain usable offline without copying.
            byte[] bytes = readValid(new File(savedDirectory, name));
            if (bytes != null) return bytes;
            bytes = readValid(file);
            if (bytes != null) {
                file.setLastModified(System.currentTimeMillis());
                trim(file);
                return bytes;
            }
        }
        byte[] bytes = fetcher.fetch();
        validate(bytes);
        synchronized (DISK_LOCK) {
            try { LibraryFiles.atomicWrite(file, bytes); }
            catch (IOException cacheUnavailable) { return bytes; } // Display is still possible.
            trim(file);
        }
        return bytes;
    }

    private byte[] readValid(File file) {
        if (!file.isFile()) return null;
        try {
            byte[] bytes = LibraryFiles.read(file, imageLimit);
            validate(bytes);
            return bytes;
        } catch (IOException invalid) { return null; }
    }

    private void validate(byte[] bytes) throws IOException {
        if (bytes == null || bytes.length == 0 || bytes.length > imageLimit)
            throw new IOException("参考图文件大小无效。");
        validator.validate(bytes);
    }

    private void trim(File keep) {
        File[] files = directory.listFiles(file -> file.isFile() && file.getName().matches("[0-9a-f]{64}\\.image"));
        if (files == null) return;
        Arrays.sort(files, Comparator.comparingLong(File::lastModified).thenComparing(File::getName));
        long size = 0; for (File file : files) size += file.length();
        int count = files.length;
        for (File file : files) {
            if (size <= byteLimit && count <= fileLimit) break;
            if (file.equals(keep)) continue;
            long length = file.length();
            if (file.delete()) { size -= length; count--; }
        }
    }
}
