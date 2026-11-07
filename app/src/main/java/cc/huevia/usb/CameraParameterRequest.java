package cc.huevia.usb;

import java.util.LinkedHashMap;
import java.util.Map;

/** Explicit absolute values selected by the user. Null always means leave the camera alone. */
public final class CameraParameterRequest {
    public static final int WHITE_BALANCE = 0x5005, EXPOSURE_BIAS = 0x5010, COLOR_TEMPERATURE = 0xd01e;
    public static final int KELVIN_MODE = 0x8012;
    public static final CameraParameterRequest NONE = new CameraParameterRequest(null, null, null);
    public final Long whiteBalance, kelvin, exposureMilliEv;
    public CameraParameterRequest(Long whiteBalance, Long kelvin, Long exposureMilliEv) {
        if (whiteBalance != null && whiteBalance != 2 && whiteBalance != 4 && whiteBalance != 5
                && whiteBalance != 6 && whiteBalance != 7 && whiteBalance != 0x8010
                && whiteBalance != 0x8011 && whiteBalance != KELVIN_MODE)
            throw new IllegalArgumentException("不支持此白平衡选项。");
        if (kelvin != null && (whiteBalance == null || whiteBalance != KELVIN_MODE || kelvin < 2500 || kelvin > 10000))
            throw new IllegalArgumentException("色温须为 2500–10000 K，并选择色温白平衡。");
        if (whiteBalance != null && whiteBalance == KELVIN_MODE && kelvin == null)
            throw new IllegalArgumentException("请选择色温。");
        if (exposureMilliEv != null && (exposureMilliEv < -5000 || exposureMilliEv > 5000))
            throw new IllegalArgumentException("曝光补偿超出可选范围。");
        this.whiteBalance = whiteBalance; this.kelvin = kelvin; this.exposureMilliEv = exposureMilliEv;
    }
    public boolean isEmpty() { return whiteBalance == null && kelvin == null && exposureMilliEv == null; }
    public Map<Integer, Long> values() {
        Map<Integer, Long> values = new LinkedHashMap<>();
        if (whiteBalance != null) values.put(WHITE_BALANCE, whiteBalance);
        if (kelvin != null) values.put(COLOR_TEMPERATURE, kelvin);
        if (exposureMilliEv != null) values.put(EXPOSURE_BIAS, exposureMilliEv);
        return values;
    }
    public String summary() {
        if (isEmpty()) return "不调整";
        String wb = whiteBalance == null ? "" : "白平衡 " + whiteBalanceLabel(whiteBalance);
        if (kelvin != null) wb = "色温 " + kelvin + " K";
        String ev = exposureMilliEv == null ? "" : "曝光 " + evLabel(exposureMilliEv) + " EV";
        return wb.isEmpty() ? ev : ev.isEmpty() ? wb : wb + " · " + ev;
    }
    public static String whiteBalanceLabel(long value) {
        if (value == 2) return "自动"; if (value == 4) return "晴天";
        if (value == 5) return "荧光灯"; if (value == 6) return "白炽灯";
        if (value == 7) return "闪光灯"; if (value == 0x8010) return "阴天";
        if (value == 0x8011) return "阴影"; if (value == KELVIN_MODE) return "色温";
        return "代码 " + Long.toHexString(value);
    }
    public static String evLabel(long value) {
        return String.format(java.util.Locale.ROOT, "%s%.1f", value > 0 ? "+" : "", value / 1000.0);
    }
    public static boolean allowedCode(long code) {
        return cc.huevia.picturecontrol.CameraParameterWriteGuard.allowedCode(code);
    }
    public static String label(int code, long value) {
        if (code == WHITE_BALANCE) return whiteBalanceLabel(value);
        if (code == COLOR_TEMPERATURE) return value + " K";
        return evLabel(value) + " EV";
    }
    public static String name(int code) {
        return code == WHITE_BALANCE ? "白平衡" : code == COLOR_TEMPERATURE ? "色温" : "曝光补偿";
    }
}
