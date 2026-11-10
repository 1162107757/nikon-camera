package cc.huevia.shared;

import cc.huevia.album.PhotoEditStore;
import cc.huevia.album.PhotoExportSpec;
import cc.huevia.ncp.PresetPreviewProfile;
import java.nio.charset.StandardCharsets;

/** Portable form of PhotoPresetRenderer.modelVersion; verified against it on Android. */
public final class SharedExportModel {
    private SharedExportModel(){}
    public static String of(PresetPreviewProfile profile,PhotoExportSpec.Resolved spec){
        if(profile==null||spec==null)throw new IllegalArgumentException("导出模型信息无效。");
        String full=profile.modelVersion()+":full-jpeg95-srgb-v1";
        return spec.isFullJpeg95()?full:"export-jpeg-v1:"+PhotoEditStore.hash((full+"\n"+spec.identity()).getBytes(StandardCharsets.UTF_8));
    }
}
