package android.database;
public interface Cursor extends AutoCloseable {
    boolean moveToFirst();
    int getColumnIndexOrThrow(String column);
    int getInt(int index);
    long getLong(int index);
    void close();
}
