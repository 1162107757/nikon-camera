package android.app;
import android.content.Context;
import android.database.Cursor;
import android.net.Uri;
import java.io.File;
import java.nio.file.Files;
public final class DownloadManager {
    public static final String COLUMN_STATUS = "status", COLUMN_BYTES_DOWNLOADED_SO_FAR = "received";
    public static final int STATUS_SUCCESSFUL = 8, STATUS_FAILED = 16, STATUS_PAUSED = 4;
    public int status = STATUS_PAUSED, removals;
    public long received, id;
    public byte[] payload = new byte[0];
    public long enqueue(Request request) {
        try { Files.write(request.target.toPath(), payload); }
        catch (Exception failure) { throw new IllegalStateException(failure); }
        id++; return id;
    }
    public int remove(long ignored) { removals++; return 1; }
    public Cursor query(Query ignored) {
        return new Cursor() {
            public boolean moveToFirst() { return true; }
            public int getColumnIndexOrThrow(String column) { return COLUMN_STATUS.equals(column) ? 0 : 1; }
            public int getInt(int index) { return status; }
            public long getLong(int index) { return received; }
            public void close() {}
        };
    }
    public static final class Query { public Query setFilterById(long... ids) { return this; } }
    public static final class Request {
        public static final int VISIBILITY_VISIBLE = 0;
        File target;
        public Request(Uri uri) {}
        public Request setTitle(String value) { return this; }
        public Request setDescription(String value) { return this; }
        public Request setMimeType(String value) { return this; }
        public Request setAllowedOverMetered(boolean value) { return this; }
        public Request setAllowedOverRoaming(boolean value) { return this; }
        public Request setNotificationVisibility(int value) { return this; }
        public Request setDestinationInExternalFilesDir(Context context, String type, String name) { target = new File(context.getExternalFilesDir(type), name); return this; }
    }
}
