package cc.huevia.shared;

import cc.huevia.library.SharedJson;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InterruptedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.BooleanSupplier;

/** Account-private equivalent of the original portrait_skin_swatches/swatches_v1. */
public final class SharedPortraitToneCards {
    private static final Object LOCK = new Object();
    private static final int LIMIT = 12, MAX_BYTES = 32768;
    private SharedPortraitToneCards() {}

    public static Map<String,Object> request(File root, String verifiedOwner, String operation,
            Map<String,Object> p, BooleanSupplier cancel) throws IOException {
        synchronized (LOCK) {
            check(cancel);
            if (verifiedOwner == null || verifiedOwner.length() > 64)
                throw new IOException("个人色卡账户身份无效。");
            if (!operation.equals("toneCards.list") && !operation.equals("toneCards.save") && !operation.equals("toneCards.remove"))
                throw new IOException("不支持的个人色卡操作。");
            File base = root.getCanonicalFile();
            File directory = checked(base, new File(base, "portrait-tone-cards/" + hash(verifiedOwner)));
            File file = checked(base, new File(directory, "swatches_v1.json"));
            List<Map<String,Object>> cards = read(file, cancel);
            if (operation.equals("toneCards.save")) {
                String name = name(p.get("name")); int rgb = rgb(p.get("rgb"));
                if (cards.size() >= LIMIT) throw new IOException("个人色卡已满（12 张），请先删除一张再保存。");
                for (Map<String,Object> card : cards) {
                    if (((Number)card.get("rgb")).intValue() == rgb) throw new IOException("这个颜色已经保存在个人色卡中。");
                    if (((String)card.get("name")).equalsIgnoreCase(name)) throw new IOException("已有同名色卡，请换一个名称。");
                }
                Map<String,Object> added = new LinkedHashMap<>();
                added.put("id", UUID.randomUUID().toString()); added.put("name", name); added.put("rgb", rgb);
                cards.add(added); write(base, directory, file, cards, cancel);
            } else if (operation.equals("toneCards.remove")) {
                Object value = p.get("id"); if (!(value instanceof String) || !id((String)value)) throw new IOException("色卡身份无效。");
                cards.removeIf(card -> card.get("id").equals(value));
                write(base, directory, file, cards, cancel);
            }
            Map<String,Object> result = new LinkedHashMap<>(); result.put("cards", cards); return result;
        }
    }

    private static List<Map<String,Object>> read(File file, BooleanSupplier cancel) throws IOException {
        List<Map<String,Object>> result = new ArrayList<>();
        if (!file.exists()) return result;
        if (!file.isFile() || file.length() < 2 || file.length() > MAX_BYTES) throw new IOException("个人色卡文件损坏，未覆盖原资料。");
        try {
            Object raw = SharedJson.object("{\"cards\":" + new String(Files.readAllBytes(file.toPath()), StandardCharsets.UTF_8) + "}").get("cards");
            if (!(raw instanceof List) || ((List<?>)raw).size() > LIMIT) throw new IOException("个人色卡文件损坏，未覆盖原资料。");
            for (Object row : (List<?>)raw) {
                check(cancel); if (!(row instanceof Map)) throw new IOException("个人色卡文件损坏，未覆盖原资料。");
                Map<?,?> value = (Map<?,?>)row; Object identity = value.get("id");
                if (!(identity instanceof String) || !id((String)identity)) throw new IOException("个人色卡文件损坏，未覆盖原资料。");
                String name = name(value.get("name")); int rgb = rgb(value.get("rgb"));
                for (Map<String,Object> prior : result)
                    if (prior.get("id").equals(identity) || ((String)prior.get("name")).equalsIgnoreCase(name) || ((Number)prior.get("rgb")).intValue() == rgb)
                        throw new IOException("个人色卡文件损坏，未覆盖原资料。");
                Map<String,Object> card = new LinkedHashMap<>(); card.put("id", identity); card.put("name", name); card.put("rgb", rgb); result.add(card);
            }
            return result;
        } catch (InterruptedIOException cancelled) { throw cancelled; }
        catch (IOException failure) { throw failure; }
        catch (RuntimeException invalid) { throw new IOException("个人色卡文件损坏，未覆盖原资料。", invalid); }
    }

    private static void write(File base, File directory, File file, List<Map<String,Object>> cards, BooleanSupplier cancel) throws IOException {
        check(cancel); checked(base, directory);
        if (!directory.isDirectory() && !directory.mkdirs()) throw new IOException("色卡未能保存，请重试。");
        checked(base, directory); checked(base, file);
        File temporary = File.createTempFile("swatches-", ".part", directory);
        try {
            byte[] data = SharedJson.encode(cards).getBytes(StandardCharsets.UTF_8);
            try (FileOutputStream output = new FileOutputStream(temporary)) { output.write(data); output.getFD().sync(); }
            check(cancel); checked(base, file);
            try { Files.move(temporary.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING); }
            catch (AtomicMoveNotSupportedException unavailable) { throw new IOException("此存储无法安全保存色卡，原资料已保留。", unavailable); }
        } finally { Files.deleteIfExists(temporary.toPath()); }
    }

    private static File checked(File base, File file) throws IOException {
        File current = file;
        while (current != null && !current.equals(base)) {
            if (Files.isSymbolicLink(current.toPath())) throw new IOException("色卡目录不可用，未改动资料。");
            current = current.getParentFile();
        }
        File canonical = file.getCanonicalFile();
        if (current == null || !canonical.toPath().startsWith(base.toPath())) throw new IOException("色卡目录不可用，未改动资料。");
        return canonical;
    }

    private static String name(Object value) throws IOException {
        if (!(value instanceof String)) throw new IOException("请为色卡填写 1–12 个字的名称。");
        String name = ((String)value).trim();
        if (name.isEmpty() || name.length() > 12) throw new IOException("请为色卡填写 1–12 个字的名称。");
        for (int i = 0; i < name.length(); i++) if (Character.isISOControl(name.charAt(i))) throw new IOException("色卡名称不能含控制字符。");
        return name;
    }
    private static int rgb(Object value) throws IOException {
        if (!(value instanceof Number)) throw new IOException("色卡颜色无效。");
        double n = ((Number)value).doubleValue();
        if (!Double.isFinite(n) || n < 0 || n > 0xffffff || n != Math.rint(n)) throw new IOException("色卡颜色无效。");
        return (int)n;
    }
    private static boolean id(String value) { return value.matches("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"); }
    private static String hash(String owner) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(owner.getBytes(StandardCharsets.UTF_8));
            StringBuilder value = new StringBuilder();
            for (byte b : digest) value.append(Character.forDigit((b >>> 4) & 15, 16)).append(Character.forDigit(b & 15, 16));
            return value.toString();
        } catch (Exception impossible) { throw new AssertionError(impossible); }
    }
    private static void check(BooleanSupplier cancel) throws InterruptedIOException { if (cancel.getAsBoolean()) throw new InterruptedIOException("个人色卡操作已取消。"); }
}
