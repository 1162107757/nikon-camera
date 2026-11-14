package cc.huevia.account;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InterruptedIOException;
import java.io.OutputStream;
import java.net.URL;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import javax.net.ssl.HttpsURLConnection;

/** Fixed HTTPS origin. Redirects, cookies and arbitrary destinations are never followed. */
public final class AccountHttpTransport implements AccountRepository.Transport {
    public static final String BASE_URL = "https://nikon-d8girdjsr252fd90e-1252602548.ap-shanghai.app.tcloudbase.com/preset-library";
    /** The platform may choose a network for this connection without changing process routing. */
    public interface ConnectionOpener { OpenedConnection open(URL url) throws IOException; }
    public static final class OpenedConnection implements AutoCloseable {
        public final HttpsURLConnection connection;
        private final Runnable release;
        private final AtomicBoolean closed = new AtomicBoolean();
        public OpenedConnection(HttpsURLConnection connection, Runnable release) {
            this.connection = java.util.Objects.requireNonNull(connection);
            this.release = java.util.Objects.requireNonNull(release);
        }
        @Override public void close() {
            if (!closed.compareAndSet(false, true)) return;
            try { connection.disconnect(); } finally { release.run(); }
        }
    }
    private static volatile ConnectionOpener publicConnections = url ->
            new OpenedConnection((HttpsURLConnection) url.openConnection(), () -> {});
    /** Platform adapter hook shared by product HTTPS clients, never by camera sockets. */
    public static void setPublicConnectionOpener(ConnectionOpener opener) {
        publicConnections = java.util.Objects.requireNonNull(opener);
    }
    public static OpenedConnection openPublicConnection(URL url) throws IOException { return publicConnections.open(url); }
    private final ConnectionOpener opener;
    public AccountHttpTransport() { this(AccountHttpTransport::openPublicConnection); }
    public AccountHttpTransport(ConnectionOpener opener) { this.opener = java.util.Objects.requireNonNull(opener); }
    private static final ScheduledExecutorService DEADLINES = Executors.newSingleThreadScheduledExecutor(task -> {
        Thread thread = new Thread(task, "account-network-deadline"); thread.setDaemon(true); return thread;
    });

    @Override public AccountRepository.Response request(String method, String path, String token, byte[] body) throws IOException {
        validateRequest(method, path, token, body);
        return execute(method, path, token, body, null, null, false);
    }

    @Override public AccountRepository.Response profileRequest(String method, String path, String token, byte[] body,
                                                               String installationId, String expectedUpdatedAt) throws IOException {
        validateProfileRequest(method, path, token, body, installationId, expectedUpdatedAt);
        return execute(method, path, token, body, installationId, expectedUpdatedAt, "/profile/avatar".equals(path));
    }

    private AccountRepository.Response execute(String method, String path, String token, byte[] body,
                                                String installationId, String expectedUpdatedAt, boolean jpeg) throws IOException {
        final OpenedConnection opened = opener.open(new URL(BASE_URL + path));
        final HttpsURLConnection connection = opened.connection;
        String stage = "configure";
        try {
        connection.setInstanceFollowRedirects(false);
        connection.setConnectTimeout(8000); connection.setReadTimeout(10000);
        connection.setRequestMethod(method); connection.setUseCaches(false);
        connection.setRequestProperty("Accept", "application/json");
        connection.setRequestProperty("Accept-Encoding", "identity");
        connection.setRequestProperty("Cache-Control", "no-store");
        connection.setRequestProperty("Cookie", ""); connection.setRequestProperty("Cookie2", "");
        if (token != null) connection.setRequestProperty("Authorization", "Bearer " + token);
        if (installationId != null) connection.setRequestProperty("X-Installation-Id", installationId);
        if (expectedUpdatedAt != null) connection.setRequestProperty("X-Expected-Updated-At", expectedUpdatedAt);
        AtomicBoolean timedOut = new AtomicBoolean();
        ScheduledFuture<?> timeout = DEADLINES.schedule(() -> { timedOut.set(true); connection.disconnect(); }, 30, TimeUnit.SECONDS);
        int status = 0;
        try {
            stage = "request";
            if (body != null) {
                connection.setDoOutput(true); connection.setFixedLengthStreamingMode(body.length);
                connection.setRequestProperty("Content-Type", jpeg ? "image/jpeg" : "application/json; charset=utf-8");
                try (OutputStream output = connection.getOutputStream()) { output.write(body); }
            }
            status = connection.getResponseCode();
            stage = "response_headers";
            if (status >= 300 && status < 400) throw new AccountException("HTTP_REDIRECT_REJECTED", status, "账号服务地址异常，请稍后重试。");
            String encoding = connection.getContentEncoding();
            if (encoding != null && !encoding.isEmpty() && !"identity".equalsIgnoreCase(encoding)) throw invalid();
            long declared = connection.getContentLengthLong();
            if (declared > AccountRepository.MAX_RESPONSE_BYTES) throw invalid();
            String mime = connection.getContentType();
            if (status != 204 && (mime == null || !mime.toLowerCase(java.util.Locale.ROOT).matches("application/json(?:\\s*;.*)?"))) throw invalid();
            InputStream stream = status >= 400 ? connection.getErrorStream() : connection.getInputStream();
            stage = "response_body";
            byte[] result;
            if (stream == null) result = new byte[0];
            else try (InputStream input = stream) { result = readBounded(input, timedOut); }
            if (timedOut.get()) throw new InterruptedIOException("账号请求超时，请重试。");
            if (declared >= 0 && declared != result.length) throw invalid();
            return new AccountRepository.Response(status, result);
        } catch (IOException error) {
            // Only controlled stage/status/type are logged; credentials and response data stay private.
            java.util.logging.Logger.getLogger("HueviaAccount").warning("stage=" + stage + " status=" + status + " type=" + error.getClass().getSimpleName());
            // HTTP denials and service failures remain authoritative even if a gateway returns HTML.
            if (status == 401 || status == 403 || status == 429 || status >= 500)
                return new AccountRepository.Response(status, null);
            throw error;
        } finally { timeout.cancel(false); }
        } finally { opened.close(); }
    }

    static void validateRequest(String method, String path, String token, byte[] body) throws AccountException {
        if (path != null && path.matches("/auth/challenge\\?installationId=(?i:[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12})")) {
            if (!"GET".equals(method) || token != null || body != null) throw invalid();
            return;
        }
        boolean auth = "/auth/register".equals(path) || "/auth/login".equals(path) || "/auth/qq".equals(path);
        boolean me = "/auth/me".equals(path);
        boolean logout = "/auth/logout".equals(path);
        if ((!auth && !me && !logout) || !(me ? "GET".equals(method) : "POST".equals(method))) throw invalid();
        if ((auth && token != null) || (!auth && (token == null || !token.matches("[A-Za-z0-9_-]{43}")))) throw invalid();
        if ((me && body != null) || (!me && (body == null || body.length > 4096))) throw invalid();
    }
    static void validateProfileRequest(String method, String path, String token, byte[] body,
                                       String installationId, String expectedUpdatedAt) throws AccountException {
        boolean upload = "/profile/avatar".equals(path) && "PUT".equals(method);
        boolean reset = "/profile/avatar/reset".equals(path) && "POST".equals(method);
        if ((!upload && !reset) || token == null || !token.matches("[A-Za-z0-9_-]{43}")
                || installationId == null || !installationId.matches("(?i)[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}")
                || expectedUpdatedAt == null || expectedUpdatedAt.length() > 40
                || !expectedUpdatedAt.matches("[0-9TtZz:+.\\-]{20,40}")
                || body == null || body.length == 0 || body.length > (upload ? AccountRepository.MAX_AVATAR_BYTES : 256)) throw invalid();
        try { java.time.Instant.parse(expectedUpdatedAt); }
        catch (RuntimeException invalidTime) { throw invalid(); }
        if (upload && (body.length < 4 || (body[0] & 255) != 255 || (body[1] & 255) != 216
                || (body[body.length-2] & 255) != 255 || (body[body.length-1] & 255) != 217)) throw invalid();
    }
    static byte[] readBounded(InputStream input, AtomicBoolean timedOut) throws IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream(); byte[] bytes = new byte[4096]; int count;
        while ((count = input.read(bytes)) != -1) {
            if (timedOut.get() || Thread.currentThread().isInterrupted()) throw new InterruptedIOException("账号请求已取消或超时。");
            if (count == 0 || count > AccountRepository.MAX_RESPONSE_BYTES - output.size()) throw invalid();
            output.write(bytes, 0, count);
        }
        return output.toByteArray();
    }
    private static AccountException invalid() { return new AccountException("INVALID_RESPONSE", 0, "账号服务返回异常，请稍后重试。"); }
}
