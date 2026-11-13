"""Patch generated copies only. The original legacy app remains frozen."""
from pathlib import Path
import argparse
import hashlib

BASE_HASHES = {
    "cc/huevia/album/AlbumController.java": "66fcc6ffb8deb377f90f607671eda1c143ae8fb72b0166c4ed6ed6e0c61cc821",
    "cc/huevia/album/PhotoFormat.java": "68147b8c15af41b6a4f0956dab2f6ad1970a44b5a3db9fee3982512443631a20",
    "cc/huevia/ui/AlbumPanel.java": "59a961413486ecd8255d30c18e150f93bc5f0a030d2bcde097e1ac77ff9f11e7",
    "cc/huevia/MainActivity.java": "94cac83c021c69cf87071f3c639306c30272351c2bf7c644dbbf43c87ece2ff3",
}


def replace_once(source, before, after):
    if source.count(before) != 1:
        raise ValueError("Legacy patch context changed: " + before[:100])
    return source.replace(before, after, 1)


def patch(root):
    workspace = Path(__file__).resolve().parents[2]
    root = Path(root).resolve()
    expected = (workspace / "app/build/generated/legacy-jpeg196/java").resolve()
    if root != expected:
        raise ValueError("Only the generated legacy-jpeg196 Java tree may be patched")
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
    source = replace_once(source, 'package cc.huevia.ui;', 'package cc.huevia.ui;\n\nimport cc.huevia.album.ConnectionTrace;')
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

    name = "cc/huevia/ui/AlbumPanel.java"
    source = sources[name]
    source = replace_once(source, '    public View createView() {', '''    /** Pull the authoritative index even when a different UI owned its callback. */
    public boolean reconcileCameraSnapshot() {
        if (closed || localWorkspace || downloading || exporting || recoveringDownloads || ownsConnectionRequest && connecting) return false;
        ConnectionInfo current = controller.connectionInfo();
        if (current == null || connection == current && !connecting) return false;
        ConnectionTrace.diagnosticReason("ALBUM_UI_SNAPSHOT_RECOVERED", current.totalHandles(), connection == null ? 1 : 2);
        restoreConnection(current);
        return true;
    }

    /** Reclaim the single legacy listener when this host becomes foreground. */
    public boolean resumeCameraConnection() {
        if (closed || localWorkspace) return false;
        controller.setConnectionListener(connectionListener);
        if (ownsConnectionRequest && connecting) return false;
        if (controller.connectionInfo() != null) return reconcileCameraSnapshot();
        // A background host can miss disconnect/connecting notifications too.
        ConnectionInfo before = connection;
        boolean wasConnecting = connecting, wasDownloading = downloading, wasRecovering = recoveringDownloads;
        if (!controller.hasLiveSession() && !controller.isConnecting()
                && (before != null || wasConnecting || wasDownloading || wasRecovering || !photos.isEmpty())) {
            resetRemoteConnection(false);
            if (before != null) cameraError = "无线连接已断开。已下载照片仍可查看，请重新连接相机后浏览。";
            else if (wasConnecting) connectionError = "相册连接未完成，请检查相机网络后重试。";
            ConnectionTrace.diagnosticReason("ALBUM_UI_DISCONNECT_RECOVERED", 0, 0);
            changed();
            return true;
        }
        controllerStateChanged();
        return before != connection || wasConnecting != connecting || wasDownloading != downloading || wasRecovering != recoveringDownloads;
    }

    public View createView() {
        reconcileCameraSnapshot();''')
    source = replace_once(source, '    public void setSharedCameraState(boolean connected, boolean preparing, String error, Runnable retry) {', '''    public void setSharedCameraState(boolean connected, boolean preparing, String error, Runnable retry) {
        reconcileCameraSnapshot();''')
    source = replace_once(source, '        pendingPage = pageRequest;', '''        ConnectionTrace.diagnosticReason("ALBUM_UI_PAGE_QUEUED", pageRequest.offset(), PAGE_SIZE);
        pendingPage = pageRequest;''')
    sources[name] = source

    name = "cc/huevia/MainActivity.java"
    source = sources[name]
    source = replace_once(source, '                    connections.prepareAlbumFromCurrent(true);', '''                    album.resumeCameraConnection();
                    if (album.isConnected()) { render(); return; }
                    connections.prepareAlbumFromCurrent(true);''')
    source = replace_once(source, '            ConnectionUiState current = new ConnectionUiState(connections, album, preparedWireless);', '''            boolean albumCameraRecovered = album.reconcileCameraSnapshot();
            ConnectionUiState current = new ConnectionUiState(connections, album, preparedWireless);''')
    source = replace_once(source, '            if (shellChanged || !current.sameAs(renderedConnectionState)) render();',
        '            if (shellChanged || albumCameraRecovered || !current.sameAs(renderedConnectionState)) render();')
    source = replace_once(source, '        if (album != null) album.refreshGalleryStatus();', '''        boolean albumCameraRecovered = album != null && album.resumeCameraConnection();
        if (album != null) album.refreshGalleryStatus();''')
    source = replace_once(source, '        if (ready && settingsTab && !destroyed) render();',
        '        if (ready && (settingsTab || albumTab && albumCameraRecovered) && !destroyed) render();')
    source = replace_once(source, '                .put("preparingAlbum", connections.isPreparingAlbum()).put("connecting", connections.album.isConnecting())',
        '                .put("photoPanelConnected", album != null && album.isConnected())\n                .put("preparingAlbum", connections.isPreparingAlbum()).put("connecting", connections.album.isConnecting())')
    sources[name] = source

    name = "cc/huevia/album/AlbumController.java"
    source = sources[name]
    source = replace_once(source, '            int cursor = offset, scanned = 0;', '''            int cursor = offset, scanned = 0, nefCount = 0, otherCount = 0;
            ConnectionTrace.diagnosticReason("ALBUM_JPEG_PAGE_BEGIN", offset, limit);''')
    source = replace_once(source, '                if (PhotoFormat.of(info) == PhotoFormat.JPEG) photos.add(new PhotoItem(session, handle, info));', '''                PhotoFormat sourceFormat = PhotoFormat.of(info);
                if (sourceFormat == PhotoFormat.JPEG) photos.add(new PhotoItem(session, handle, info));
                else if (sourceFormat == PhotoFormat.NEF) nefCount++;
                else otherCount++;''')
    source = replace_once(source, '            return new PhotoPage(photos, cursor, handles.length);', '''            ConnectionTrace.diagnosticReason("ALBUM_JPEG_PAGE_RESULT", photos.size(), cursor);
            ConnectionTrace.diagnosticReason("ALBUM_PAGE_NEF_FILTERED", nefCount, otherCount);
            return new PhotoPage(photos, cursor, handles.length);''')
    sources[name] = source

    for name, content in sources.items():
        (root / name).write_text(content, encoding="utf-8", newline="\n")
    print("Legacy JPEG 196: patched 4 generated files; original app unchanged")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    patch(parser.parse_args().source)
