package cc.huevia.shared;

import cc.huevia.album.*;
import cc.huevia.ncp.*;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import cc.huevia.account.AccountRepository;
import cc.huevia.library.SharedJson;

public final class ExportBoundaryTest {
    private static int checks;
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Export boundary "+checks);}
    public static int run(Path temporary)throws Exception{
        checks=0;PresetPreviewProfile profile=new PhotoEditStore.Draft("a".repeat(64),NcpCompatibilityFixtures.ncp(),"Frozen",75,false).profile();
        String full=SharedExportModel.of(profile,PhotoExportSpec.full().resolve(4000,3000));
        yes(full.equals(profile.modelVersion()+":full-jpeg95-srgb-v1"));
        yes(SharedExportModel.of(profile,PhotoExportSpec.full().resolve(2000,1000)).equals(full));
        String share=SharedExportModel.of(profile,PhotoExportSpec.share().resolve(4000,3000));
        yes(share.startsWith("export-jpeg-v1:")&&!share.equals(full));
        yes(!share.equals(SharedExportModel.of(profile,PhotoExportSpec.share().resolve(4000,2000))));
        yes(SharedExportModel.of(profile,PhotoExportSpec.custom(8192,95).resolve(4000,3000)).equals(full));
        yes(!SharedExportModel.of(profile,PhotoExportSpec.custom(2048,90).resolve(4000,3000)).equals(SharedExportModel.of(profile,PhotoExportSpec.custom(2048,95).resolve(4000,3000))));
        PhotoEditStore.Draft frozen=new PhotoEditStore.Draft("a".repeat(64),NcpCompatibilityFixtures.ncp(),"Frozen",75,false);
        for(int orientation=1;orientation<=8;orientation++) {
            Map<String,Object> descriptor=SharedExportSpecs.describe(frozen,SharedRuntime.map("width",4000,"height",3000,"orientation",orientation),()->false);
            boolean swapped=orientation>=5;
            yes(descriptor.get("fullWidth").equals(swapped?3000:4000)&&descriptor.get("fullHeight").equals(swapped?4000:3000));
            List<?> qualities=(List<?>)descriptor.get("qualities");yes(qualities.size()==4);
            Map<?,?> compact=(Map<?,?>)qualities.get(0),high=(Map<?,?>)qualities.get(2),original=(Map<?,?>)qualities.get(3);
            yes(compact.get("width").equals(swapped?960:1280)&&compact.get("height").equals(swapped?1280:960)&&compact.get("quality").equals(80));
            yes(high.get("width").equals(swapped?3000:4000)&&high.get("height").equals(swapped?4000:3000)&&high.get("quality").equals(92));
            yes(original.get("model").equals(full));
        }
        Map<String,Object> tiny=SharedExportSpecs.describe(frozen,SharedRuntime.map("width",320,"height",200),()->false);
        yes(Boolean.FALSE.equals(tiny.get("customEnabled")));
        yes(((Map<?,?>)((List<?>)tiny.get("qualities")).get(0)).get("width").equals(320));
        Map<String,Object> invalid=SharedRuntime.map("width",1200,"height",800,"longEdge",1201);
        try {SharedExportSpecs.describe(frozen,invalid,()->false);throw new AssertionError("Single-photo custom upscaling was accepted");}catch(IOException expected){checks++;}
        invalid.put("longEdge",640);invalid.put("quality",69);
        try {SharedExportSpecs.describe(frozen,invalid,()->false);throw new AssertionError("Out-of-range JPEG quality was accepted");}catch(IOException expected){checks++;}
        Map<String,Object> batch=SharedExportSpecs.describe(frozen,SharedRuntime.map("width",320,"height",200,"batch",true,"longEdge",2048,"quality",85),()->false);
        yes(Boolean.TRUE.equals(batch.get("customEnabled"))&&((Map<?,?>)batch.get("custom")).get("width").equals(320));
        try {SharedExportSpecs.describe(frozen,SharedRuntime.map("width",320,"height",200,"batch","true"),()->false);throw new AssertionError("Invalid batch flag was accepted");}catch(IOException expected){checks++;}
        try {SharedExportSpecs.describe(frozen,SharedRuntime.map("width",1200,"height",800),()->true);throw new AssertionError("Cancelled export description was accepted");}catch(IOException expected){checks++;}
        Path root=Files.createDirectories(temporary.resolve("export-form-readonly")),photo=Files.createDirectories(root.resolve("originals")).resolve("own.jpg");
        byte[] source={1,2,3,4};Files.write(photo,source);
        AccountRepository.Store store=new AccountRepository.Store(){public byte[] read(){return null;}public void write(byte[] b){}public void clear(){}};
        SharedRuntime runtime=new SharedRuntime(root.toString(),store,(method,path,token,body)->{throw new AssertionError("Export form contacted network");});
        Map<String,Object> input=SharedRuntime.map("path",photo.toString(),"owner","","recipe",SharedRuntime.map("schema",1),"width",1200,"height",800);
        runtime.request("draft.save",SharedJson.encode(input));String before=runtime.request("draft.load",SharedJson.encode(input)),versions=runtime.request("version.list","{\"owner\":\"\"}");
        input.put("recipe",SharedRuntime.map("schema",1,"border",SharedRuntime.map("template",3)));
        Map<String,Object> described=SharedJson.object(runtime.request("export.describe",SharedJson.encode(input)));
        if(((Number)described.get("fullWidth")).intValue()!=1200||((Number)described.get("fullHeight")).intValue()!=934)
            throw new AssertionError("Original white-info export fixture: "+described.get("fullWidth")+"x"+described.get("fullHeight"));
        checks++;
        yes(runtime.request("draft.load",SharedJson.encode(input)).equals(before));
        yes(runtime.request("version.list","{\"owner\":\"\"}").equals(versions));yes(Arrays.equals(Files.readAllBytes(photo),source));
        input.put("owner","different");
        try{runtime.request("export.describe",SharedJson.encode(input));throw new AssertionError("Another owner read export settings");}catch(IOException expected){checks++;}
        input.put("owner","");input.put("path",temporary.resolve("outside.jpg").toString());
        try{runtime.request("export.describe",SharedJson.encode(input));throw new AssertionError("Outside source was accepted");}catch(IOException expected){checks++;}
        input.put("path",photo.toString());
        try{runtime.request("export.describe",SharedJson.encode(input),()->true,value->{});throw new AssertionError("Cancelled form read was accepted");}catch(IOException expected){checks++;}
        input.put("orientation",9);
        try{runtime.request("export.describe",SharedJson.encode(input));throw new AssertionError("Invalid source direction was accepted");}catch(IOException expected){checks++;}
        String sourceHash=PhotoEditStore.hash(source);Path named=root.resolve("originals").resolve(sourceHash+".jpg");Files.write(named,source);
        Map<String,Object> original=SharedRuntime.map("owner","","path",named.toString(),"expectedSourceSha",sourceHash);
        Map<String,Object> inspected=SharedJson.object(runtime.request("source.inspect",SharedJson.encode(original)));
        yes(sourceHash.equals(inspected.get("sourceSha"))&&"JPG".equals(inspected.get("format")));
        original.put("expectedSourceSha","0".repeat(64));
        try{runtime.request("source.inspect",SharedJson.encode(original));throw new AssertionError("Changed original was accepted");}catch(IOException expected){checks++;}
        original.put("expectedSourceSha",sourceHash);original.put("owner","another");
        try{runtime.request("source.inspect",SharedJson.encode(original));throw new AssertionError("Another owner exported original");}catch(IOException expected){checks++;}
        original.put("owner","");original.put("path",photo.toString());
        try{runtime.request("source.inspect",SharedJson.encode(original));throw new AssertionError("Unverified filename exported");}catch(IOException expected){checks++;}
        original.put("path",named.toString());
        try{runtime.request("source.inspect",SharedJson.encode(original),()->true,value->{});throw new AssertionError("Cancelled original exported");}catch(IOException expected){checks++;}
        yes(Arrays.equals(Files.readAllBytes(named),source));
        return checks;
    }
}
