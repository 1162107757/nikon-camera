package android.content.pm;
import java.util.Arrays;
public final class Signature {
    private final byte[] value;
    public Signature(byte[] value) { this.value = value.clone(); }
    public byte[] toByteArray() { return value.clone(); }
    @Override public boolean equals(Object other) { return other instanceof Signature && Arrays.equals(value, ((Signature) other).value); }
    @Override public int hashCode() { return Arrays.hashCode(value); }
}
