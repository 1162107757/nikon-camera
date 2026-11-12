package cc.huevia.shared;

import cc.huevia.album.PhotoEditStore;
import cc.huevia.album.PhotoExportQuality;
import cc.huevia.album.PhotoExportSpec;
import cc.huevia.ncp.BorderPreviewProfile;
import cc.huevia.ncp.GeometryPreviewProfile;
import cc.huevia.ncp.PhotoGeometry;
import cc.huevia.ncp.PresetPreviewProfile;
import java.io.IOException;
import java.io.InterruptedIOException;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.function.BooleanSupplier;

/** Original quick-save ceilings and finished-canvas geometry, without rendering
 * or saving an editor draft. Both platform forms consume this same descriptor. */
public final class SharedExportSpecs {
    private SharedExportSpecs() {}
    public static Map<String,Object> describe(PhotoEditStore.Draft frozen,Map<String,Object> p,BooleanSupplier cancel)throws IOException {
        check(cancel);
        int width=SharedRuntime.integer(p,"width",0),height=SharedRuntime.integer(p,"height",0),orientation=SharedRuntime.integer(p,"orientation",1);
        if(width<1||height<1||width>65535||height>65535||orientation<1||orientation>8)throw new IOException("照片原始尺寸或方向无效。");
        try {
            PresetPreviewProfile profile=frozen.profile();
            PhotoGeometry.Plan plan=GeometryPreviewProfile.geometry(profile).plan(width,height,orientation);
            int[] canvas=BorderPreviewProfile.border(profile).dimensions(plan.width,plan.height);
            Object batch=p.get("batch");if(batch!=null&&!(batch instanceof Boolean))throw new IOException("导出批次类型无效。");
            int fullEdge=Math.max(canvas[0],canvas[1]),maximum=Boolean.TRUE.equals(batch)?PhotoExportSpec.MAX_CUSTOM_EDGE:Math.min(PhotoExportSpec.MAX_CUSTOM_EDGE,fullEdge);
            List<Object> qualities=new ArrayList<>();
            for(PhotoExportQuality quality:PhotoExportQuality.values()) {
                check(cancel);
                Map<String,Object> item=resolved(profile,quality.spec(),canvas);
                item.put("id",quality.name().toLowerCase(java.util.Locale.ROOT));item.put("label",quality.label);item.put("detail",quality.detail());
                qualities.add(item);
            }
            Map<String,Object> result=SharedRuntime.map("sourceSha",frozen.sourceSha,"fullWidth",canvas[0],"fullHeight",canvas[1],
                "geometryWidth",plan.width,"geometryHeight",plan.height,"metadataPolicy",PhotoExportSpec.METADATA_POLICY,
                "qualities",qualities,"full",resolved(profile,PhotoExportSpec.full(),canvas),"share",resolved(profile,PhotoExportSpec.share(),canvas),
                "customEnabled",maximum>=PhotoExportSpec.MIN_CUSTOM_EDGE,"minimumEdge",PhotoExportSpec.MIN_CUSTOM_EDGE,"maximumEdge",maximum);
            if(p.containsKey("longEdge")||p.containsKey("quality")) {
                int edge=SharedRuntime.integer(p,"longEdge",Math.min(2048,maximum)),quality=SharedRuntime.integer(p,"quality",95);
                if(maximum<PhotoExportSpec.MIN_CUSTOM_EDGE||edge>maximum)throw new IOException("自定义长边不能超过当前成品尺寸。");
                result.put("custom",resolved(profile,PhotoExportSpec.custom(edge,quality),canvas));
            }
            check(cancel);return result;
        } catch(IllegalArgumentException invalid) {throw new IOException(invalid.getMessage(),invalid);}
    }
    private static Map<String,Object> resolved(PresetPreviewProfile profile,PhotoExportSpec spec,int[] canvas) {
        PhotoExportSpec.Resolved r=spec.resolve(canvas[0],canvas[1]);
        return SharedRuntime.map("size",spec.mode.name().toLowerCase(java.util.Locale.ROOT),"longEdge",spec.longEdge,"quality",r.quality,
            "width",r.width,"height",r.height,"identity",r.identity(),"model",SharedExportModel.of(profile,r));
    }
    private static void check(BooleanSupplier cancel)throws InterruptedIOException {
        if(cancel!=null&&cancel.getAsBoolean())throw new InterruptedIOException("导出设置已取消。");
    }
}
