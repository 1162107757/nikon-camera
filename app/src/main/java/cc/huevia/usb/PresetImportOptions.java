package cc.huevia.usb;

import cc.huevia.ncp.CameraPresetAdapter;
import cc.huevia.ncp.NcpPictureControlConverter;
import java.io.IOException;

/** Frozen approval for one source-derived adaptation and optional explicit camera settings. */
public final class PresetImportOptions {
    public final boolean acceptApproximation;
    public final String expectedDataSha256;
    public final CameraParameterRequest parameters;
    public final CameraParameterController.Audit audit;
    public PresetImportOptions(boolean acceptApproximation, String expectedDataSha256,
            CameraParameterRequest parameters, CameraParameterController.Audit audit) {
        if (expectedDataSha256 == null || !expectedDataSha256.matches("[a-f0-9]{64}"))
            throw new IllegalArgumentException("缺少已确认的适配数据校验值。");
        this.acceptApproximation = acceptApproximation; this.expectedDataSha256 = expectedDataSha256;
        this.parameters = parameters == null ? CameraParameterRequest.NONE : parameters; this.audit = audit;
    }
    public NcpPictureControlConverter.Conversion convert(byte[] source, int middle, int clarity) throws IOException {
        NcpPictureControlConverter.Conversion value = CameraPresetAdapter.plan(source, middle, clarity).approved(acceptApproximation);
        if (!expectedDataSha256.equals(value.dataSha256())) throw new IOException("适配数据与确认页不一致，未写入相机。");
        return value;
    }
}
