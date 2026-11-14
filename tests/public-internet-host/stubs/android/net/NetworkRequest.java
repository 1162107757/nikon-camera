package android.net;
public final class NetworkRequest {
    public int transport=-1, capability=-1;
    public static final class Builder {
        private final NetworkRequest request=new NetworkRequest();
        public Builder addTransportType(int value) { request.transport=value; return this; }
        public Builder addCapability(int value) { request.capability=value; return this; }
        public NetworkRequest build() { return request; }
    }
}
