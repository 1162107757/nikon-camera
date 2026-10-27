package cc.huevia.remote;

import java.io.IOException;

/** Explicitly granted capture session; never the generic album or preset write API. */
public interface RemoteTransport {
    byte[] data(int operation, int maximum, long... parameters) throws IOException;
    void command(int operation, long... parameters) throws IOException;
    boolean isOpen();
}
