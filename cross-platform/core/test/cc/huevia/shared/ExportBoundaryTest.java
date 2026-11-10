package cc.huevia.shared;

import cc.huevia.album.*;
import cc.huevia.ncp.*;

public final class ExportBoundaryTest {
    private static int checks;
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Export boundary "+checks);}
    public static int run()throws Exception{
        checks=0;PresetPreviewProfile profile=new PhotoEditStore.Draft("a".repeat(64),NcpCompatibilityFixtures.ncp(),"Frozen",75,false).profile();
        String full=SharedExportModel.of(profile,PhotoExportSpec.full().resolve(4000,3000));
        yes(full.equals(profile.modelVersion()+":full-jpeg95-srgb-v1"));
        yes(SharedExportModel.of(profile,PhotoExportSpec.full().resolve(2000,1000)).equals(full));
        String share=SharedExportModel.of(profile,PhotoExportSpec.share().resolve(4000,3000));
        yes(share.startsWith("export-jpeg-v1:")&&!share.equals(full));
        yes(!share.equals(SharedExportModel.of(profile,PhotoExportSpec.share().resolve(4000,2000))));
        yes(SharedExportModel.of(profile,PhotoExportSpec.custom(8192,95).resolve(4000,3000)).equals(full));
        yes(!SharedExportModel.of(profile,PhotoExportSpec.custom(2048,90).resolve(4000,3000)).equals(SharedExportModel.of(profile,PhotoExportSpec.custom(2048,95).resolve(4000,3000))));
        return checks;
    }
}
