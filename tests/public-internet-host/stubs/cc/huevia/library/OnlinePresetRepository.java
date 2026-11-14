package cc.huevia.library;
import java.io.IOException;
/** Only the callback type used by the production HTTP client; no repository behavior is mocked. */
public final class OnlinePresetRepository {
    public interface ProgressListener { void onProgress(long downloaded,long total)throws IOException; }
}
