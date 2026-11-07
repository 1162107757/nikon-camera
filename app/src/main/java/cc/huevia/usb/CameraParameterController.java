package cc.huevia.usb;

import cc.huevia.ptp.PtpResponseException;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Applies user choices only after preset verification, with fresh descriptors and exact readback. */
public final class CameraParameterController {
    private CameraParameterController() {}
    public interface Access {
        byte[] get(int operation, int code) throws IOException;
        void authorize(Map<Integer, byte[]> writes) throws IOException;
        void set(int code, byte[] value) throws IOException;
    }
    public interface Audit { void beforeWrites(Result snapshot) throws IOException; }
    public static final class Change {
        public final int code;
        public final long desired;
        public Long before, observed;
        public String status = "未执行", reason = "";
        private CameraParameterDescriptor descriptor;
        Change(int code, long desired) { this.code = code; this.desired = desired; }
        public String text() {
            return CameraParameterRequest.name(code) + "：" + status
                    + (before == null ? "" : "（" + CameraParameterRequest.label(code, before) + " → "
                    + CameraParameterRequest.label(code, desired) + "）")
                    + (reason.isEmpty() ? "" : " · " + reason);
        }
    }
    public static final class Result {
        private final List<Change> changes = new ArrayList<>();
        public boolean uncertain;
        public List<Change> changes() { return Collections.unmodifiableList(changes); }
        public String text() {
            if (changes.isEmpty()) return "拍摄参数：未调整";
            List<String> lines = new ArrayList<>();
            for (Change change : changes) lines.add(change.text());
            return String.join("\n", lines);
        }
    }
    public static Result prepare(CameraParameterRequest request) {
        Result result = new Result();
        for (Map.Entry<Integer, Long> item : request.values().entrySet()) result.changes.add(new Change(item.getKey(), item.getValue()));
        return result;
    }
    public static void apply(Result result, boolean operationsSupported, Access access, Audit audit) throws IOException {
        if (result.changes.isEmpty()) return;
        if (!operationsSupported) { skipAll(result, "连接未声明支持参数写入"); return; }
        for (Change change : result.changes) {
            byte[] descriptor;
            try { descriptor = access.get(0x1014, change.code); }
            catch (PtpResponseException unsupported) { change.status = "已跳过"; change.reason = "相机当前不提供此参数"; continue; }
            try { change.descriptor = CameraParameterDescriptor.parse(change.code, descriptor); }
            catch (IOException malformed) { change.status = "已跳过"; change.reason = malformed.getMessage(); continue; }
            change.before = change.descriptor.read(access.get(0x1015, change.code));
            if (change.before == change.desired) change.status = "已是所选值";
            else if (!change.descriptor.accepts(change.desired)) {
                change.status = "已跳过"; change.reason = "当前模式只读，或不支持所选值";
            } else change.status = "待调整";
        }
        // Kelvin and the associated WB mode are one user choice; neither changes if the pair is unavailable.
        Change wb = find(result, CameraParameterRequest.WHITE_BALANCE), kelvin = find(result, CameraParameterRequest.COLOR_TEMPERATURE);
        if (kelvin != null && (wb == null || skipped(wb) || skipped(kelvin))) {
            if (wb != null) { wb.status = "已跳过"; wb.reason = "色温模式或色温值不可用"; }
            kelvin.status = "已跳过"; kelvin.reason = "色温模式或色温值不可用";
        }
        Map<Integer, byte[]> writes = new LinkedHashMap<>();
        for (Change change : result.changes) if ("待调整".equals(change.status)) writes.put(change.code, change.descriptor.encode(change.desired));
        if (writes.isEmpty()) return;
        if (audit == null) throw new IOException("参数变更记录不可用，未修改拍摄参数。");
        audit.beforeWrites(result); // Durable originals and intended values precede the first mutation.
        access.authorize(writes);
        for (Change change : result.changes) {
            if (!"待调整".equals(change.status)) continue;
            boolean writeAccepted = false;
            try {
                if (change.code == CameraParameterRequest.COLOR_TEMPERATURE
                        && (wb == null || (!"已调整并核对".equals(wb.status) && !"已是所选值".equals(wb.status)))) {
                    change.status = "已跳过"; change.reason = "白平衡模式未确认"; continue;
                }
                if (change.code == CameraParameterRequest.COLOR_TEMPERATURE
                        && wb.descriptor.read(access.get(0x1015, CameraParameterRequest.WHITE_BALANCE)) != CameraParameterRequest.KELVIN_MODE) {
                    change.status = "已跳过"; change.reason = "白平衡模式已变化"; continue;
                }
                // Re-read immediately before each write; do not overwrite a user's intervening camera change.
                long fresh = change.descriptor.read(access.get(0x1015, change.code));
                CameraParameterDescriptor current = CameraParameterDescriptor.parse(change.code, access.get(0x1014, change.code));
                if (fresh != change.before || current.type != change.descriptor.type || !current.accepts(change.desired)) {
                    change.status = "已跳过"; change.reason = "确认后机身参数或模式已变化"; continue;
                }
                change.status = "结果待核对";
                access.set(change.code, change.descriptor.encode(change.desired));
                writeAccepted = true;
                change.observed = change.descriptor.read(access.get(0x1015, change.code));
                if (change.observed != change.desired) {
                    change.status = "读回不一致"; change.reason = "未重试，请在相机核对";
                    skipPending(result, "前一项未通过核对"); return;
                }
                change.status = "已调整并核对";
            } catch (PtpResponseException rejected) {
                change.status = writeAccepted ? "已写入，读回未确认" : "相机未接受";
                change.reason = writeAccepted ? "请在相机核对，勿重复执行" : "请检查相机当前模式";
                result.uncertain |= writeAccepted;
                skipPending(result, "前一项未完成"); return;
            } catch (IOException error) {
                if ("待调整".equals(change.status)) change.status = "未执行";
                result.uncertain = true; change.reason = "连接中断，请在相机核对，勿重复执行";
                skipPending(result, "连接中断"); throw error;
            }
        }
    }
    private static boolean skipped(Change change) { return "已跳过".equals(change.status); }
    private static Change find(Result result, int code) { for (Change change : result.changes) if (change.code == code) return change; return null; }
    private static void skipPending(Result result, String reason) { for (Change change : result.changes) if ("待调整".equals(change.status)) { change.status = "未执行"; change.reason = reason; } }
    private static void skipAll(Result result, String reason) { for (Change change : result.changes) { change.status = "已跳过"; change.reason = reason; } }
}
