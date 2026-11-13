package cc.huevia.album;

import cc.huevia.ptp.PtpObjectHandles;
import cc.huevia.ptp.PtpResponseException;
import cc.huevia.ptp.PtpStorageIds;
import java.io.IOException;
import java.util.LinkedHashSet;

/** Read-only compatibility enumeration for legacy cameras with empty JPEG filters. */
public final class LegacyJpegInventory {
    public interface Reader {
        byte[] read(String stage, int operation, int limit, long... parameters) throws IOException;
    }
    public interface Cancellation { void check() throws IOException; }
    public interface Diagnostics { void reason(String stage, int count, int detail); }
    public static final class Result {
        public final long[] handles;
        public final int storageCount, readableStorages, unavailableStorages;
        Result(long[] handles, int storageCount, int readable, int unavailable) {
            this.handles = handles;
            this.storageCount = storageCount;
            this.readableStorages = readable;
            this.unavailableStorages = unavailable;
        }
    }

    public static Result read(Reader reader, Cancellation cancellation, Diagnostics diagnostics) throws IOException {
        cancellation.check();
        long[] storages = PtpStorageIds.parse(reader.read("ALBUM_STORAGE", 0x1004, 4096));
        cancellation.check();
        diagnostics.reason("ALBUM_STORAGE_COUNT", storages.length, 0);
        if (storages.length > 64) throw new IOException("相机存储空间数量超过浏览上限。");
        LinkedHashSet<Long> collected = new LinkedHashSet<>();
        int readable = 0, unavailable = 0;
        for (long storage : storages) {
            cancellation.check();
            long[] entries;
            try {
                boolean fallback = false;
                try {
                    entries = PtpObjectHandles.parse(reader.read("ALBUM_HANDLES", 0x1007, 1024 * 1024, storage, 0x3801, 0));
                    cancellation.check();
                    fallback = entries.length == 0;
                    if (fallback) diagnostics.reason("ALBUM_EMPTY_FORMAT_FALLBACK", 0, 0x3801);
                } catch (PtpResponseException unsupported) {
                    if (unsupported.responseCode() != 0x2014) throw unsupported;
                    cancellation.check();
                    diagnostics.reason("ALBUM_FORMAT_FALLBACK", 0, 0x2014);
                    entries = new long[0];
                    fallback = true;
                }
                if (fallback) {
                    cancellation.check();
                    entries = PtpObjectHandles.parse(reader.read("ALBUM_HANDLES", 0x1007, 1024 * 1024, storage, 0, 0));
                    cancellation.check();
                }
                readable++;
            } catch (PtpResponseException error) {
                if (error.responseCode() != 0x2013) throw error;
                cancellation.check();
                unavailable++;
                diagnostics.reason("ALBUM_STORAGE_UNAVAILABLE", unavailable, 0x2013);
                continue;
            }
            for (long handle : entries) {
                cancellation.check();
                if (handle == 0 || handle == 0xffffffffL) throw new IOException("相机返回了无效照片索引。");
                collected.add(handle);
                if (collected.size() > 20000) throw new IOException("相机对象过多，本版一次最多浏览 20000 个对象。");
            }
        }
        cancellation.check();
        long[] handles = new long[collected.size()];
        int cursor = 0;
        for (long handle : collected) handles[cursor++] = handle;
        diagnostics.reason("ALBUM_STORAGE_READABLE", readable, unavailable);
        diagnostics.reason("ALBUM_HANDLE_COUNT", handles.length, storages.length);
        return new Result(handles, storages.length, readable, unavailable);
    }

    private LegacyJpegInventory() { }
}
