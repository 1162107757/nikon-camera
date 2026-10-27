package android.content.pm;
public final class SigningInfo {
    private final Signature[] signers;
    public SigningInfo(Signature... signers) { this.signers = signers; }
    public Signature[] getApkContentsSigners() { return signers; }
}
