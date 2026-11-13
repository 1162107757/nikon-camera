"""Patch generated copies only. The original legacy app remains frozen."""
from pathlib import Path
import argparse
import hashlib

BASE_HASHES = {
    "cc/huevia/album/AlbumController.java": "66fcc6ffb8deb377f90f607671eda1c143ae8fb72b0166c4ed6ed6e0c61cc821",
    "cc/huevia/album/PhotoFormat.java": "68147b8c15af41b6a4f0956dab2f6ad1970a44b5a3db9fee3982512443631a20",
    "cc/huevia/ui/AlbumPanel.java": "59a961413486ecd8255d30c18e150f93bc5f0a030d2bcde097e1ac77ff9f11e7",
}


def replace_once(source, before, after):
    if source.count(before) != 1:
        raise ValueError("Legacy patch context changed: " + before[:100])
    return source.replace(before, after, 1)


def patch(root):
    workspace = Path(__file__).resolve().parents[2]
    root = Path(root).resolve()
    expected = (workspace / "app/build/generated/legacy-jpeg195/java").resolve()
    if root != expected:
        raise ValueError("Only the generated legacy-jpeg195 Java tree may be patched")
    sources = {}
    for name, expected_hash in BASE_HASHES.items():
        content = (root / name).read_bytes()
        if hashlib.sha256(content).hexdigest() != expected_hash:
            raise ValueError("Frozen legacy source changed: " + name)
        sources[name] = content.decode("utf-8").replace("\r\n", "\n")

    name = "cc/huevia/album/AlbumController.java"
    source = sources[name]
    source = replace_once(source, "    private static final int MAX_HANDLES = 20000;", "    private static final int MAX_HANDLES = 20000;\n    private volatile String jpegIndexWarning = \"\";\n    public String jpegIndexWarning() { return jpegIndexWarning; }")
    start = source.index("        LinkedHashSet<Long> collected = new LinkedHashSet<>();", source.index("private ConnectionInfo readConnectionSnapshot"))
    end = source.index("        ConnectionInfo connected =", start)
    source = source[:start] + '''        LegacyJpegInventory.Result inventory = LegacyJpegInventory.read(
                (stage, operation, limit, parameters) -> readBrowseData(client, stage, operation, limit, parameters),
                () -> requireCurrentSession(client, request), ConnectionTrace::diagnosticReason);
        if (inventory.readableStorages == 0) {
            throw new BrowseUnavailableException(inventory.storageCount == 0
                    ? "相机未提供可读取的存储卡，请检查存储卡后刷新。"
                    : "相机存储卡暂不可读，请在相机上确认存储卡状态后刷新。");
        }
        long[] observedHandles = inventory.handles;
''' + source[end:]
    source = replace_once(source, '            cachedConnectionInfo = connected; sessionConnectionInfo = connected; browseError = "";', '''            cachedConnectionInfo = connected; sessionConnectionInfo = connected; browseError = "";
            jpegIndexWarning = inventory.unavailableStorages > 0 ? "部分存储卡暂不可读，请确认相机存储卡状态后刷新" : "";''')
    sources[name] = source

    name = "cc/huevia/album/PhotoFormat.java"
    source = sources[name]
    source = replace_once(source, '        return info.objectFormat() == 0x3801 ? JPEG : OTHER;', '''        if (info.objectFormat() == 0x3801) return JPEG;
        // Some cameras enumerate independent JPEG files as generic objects.
        // Keep known video/other formats and NEF previews outside the JPEG list.
        int format = info.objectFormat();
        String name = info.filename();
        boolean plainName = name != null && !name.isEmpty() && name.indexOf('/') < 0 && name.indexOf('\\\\') < 0
                && name.chars().noneMatch(Character::isISOControl);
        String lower = plainName ? name.toLowerCase(Locale.ROOT) : "";
        return (format == 0 || format == 0x3000) && (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) ? JPEG : OTHER;''')
    sources[name] = source

    name = "cc/huevia/ui/AlbumPanel.java"
    source = sources[name]
    source = replace_once(source,
        '            if (grid != expectedGrid || grid.getChildCount() == 0 || grid.getLastVisiblePosition() < photos.size() - 1) return;',
        '''            if (grid != expectedGrid) return;
            // A bounded scan may contain only RAW/folder objects. Continue until
            // JPEGs appear or AlbumPaging reaches the end/stall guard.
            if (!photos.isEmpty() && (grid.getChildCount() == 0 || grid.getLastVisiblePosition() < photos.size() - 1)) return;''')
    source = replace_once(source, '        cameraPageFooter.setVisibility(loading || atEnd ? View.VISIBLE : View.GONE);', '''        String indexWarning = controller.jpegIndexWarning();
        cameraPageFooter.setVisibility(loading || atEnd || !indexWarning.isEmpty() ? View.VISIBLE : View.GONE);''')
    source = replace_once(source, '        if (!label.contentEquals(pageStatus.getText())) pageStatus.setText(label);', '''        if (!loading && !paging.isPaused() && !indexWarning.isEmpty()) label = "部分存储卡暂不可读 · 可继续浏览";
        if (!label.contentEquals(pageStatus.getText())) pageStatus.setText(label);''')
    source = replace_once(source, '        cameraPageFooter.setTooltipText(paging.isPaused() ? cameraError : label);',
        '        cameraPageFooter.setTooltipText(paging.isPaused() ? cameraError : !indexWarning.isEmpty() ? indexWarning : label);')
    source = replace_once(source, '            TextView emptyTitle = text(title, compactEmpty ? 18 : 19, palette.text, true);', '''            if (!downloadedTab && !pending && isConnected() && !controller.jpegIndexWarning().isEmpty()) {
                title = "部分存储卡暂不可读";
                body = "当前可读取范围内未找到 JPEG。" + controller.jpegIndexWarning() + "。";
            }
            TextView emptyTitle = text(title, compactEmpty ? 18 : 19, palette.text, true);''')
    sources[name] = source

    for name, content in sources.items():
        (root / name).write_text(content, encoding="utf-8", newline="\n")
    print("Legacy JPEG 195: patched 3 generated files; original app unchanged")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    patch(parser.parse_args().source)
