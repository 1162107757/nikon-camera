package cc.huevia.shared;

import cc.huevia.library.OnlinePreset;
import cc.huevia.library.SharedJson;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

final class CommunityBoundaryTest {
    private static final String SHA_A="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    private static final String SHA_B="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    private static final String ID_A="11111111-1111-4111-8111-111111111111",ID_B="22222222-2222-4222-8222-222222222222";
    private static int checks;
    private interface Action{void run()throws Exception;}
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Community boundary "+checks);}
    private static void rejects(Action action)throws Exception{
        checks++;try{action.run();}catch(IOException expected){return;}throw new AssertionError("Invalid discussion association accepted");
    }
    private static OnlinePreset preset(String id,String sha)throws IOException{
        return OnlinePreset.fromMap(SharedJson.object(SharedJson.encode(SharedRuntime.map("id",id,"name","同名预设","sha256",sha,"fileUrl","https://example.com/sample.ncp","byteLength",8,
            "previewUrl","","compatibleModels",List.of(),"fileFormat","NCP","source","community"))));
    }
    static int run(Path temporary)throws Exception{
        checks=0;Path root=Files.createDirectory(temporary.resolve("community-links"));
        Path file=root.resolve("shared-community-links-v1.json");SharedCommunityLinks links=new SharedCommunityLinks(root.toFile());
        yes(links.snapshot().isEmpty());
        links.remember(SHA_A,ID_A);yes(ID_A.equals(new SharedCommunityLinks(root.toFile()).snapshot().get(SHA_A)));
        links.remember(SHA_B,ID_B);yes(links.snapshot().size()==2&&ID_A.equals(links.snapshot().get(SHA_A)));
        links.remember(SHA_A,ID_B);yes(ID_B.equals(links.snapshot().get(SHA_A))&&ID_B.equals(links.snapshot().get(SHA_B)));
        yes("missing".equals(SharedCommunityLinks.match(SHA_A,List.of()).get("status")));
        yes("missing".equals(SharedCommunityLinks.match(SHA_A,List.of(preset(ID_A,SHA_B))).get("status")));
        yes(ID_A.equals(SharedCommunityLinks.match(SHA_A,List.of(preset(ID_A,SHA_A))).get("id")));
        yes(ID_A.equals(SharedCommunityLinks.match(SHA_A,List.of(preset(ID_A,SHA_A),preset(ID_A,SHA_A))).get("id")));
        yes("ambiguous".equals(SharedCommunityLinks.match(SHA_A,List.of(preset(ID_A,SHA_A),preset(ID_B,SHA_A))).get("status")));
        yes("missing".equals(SharedCommunityLinks.match(SHA_A,List.of(preset("legacy-entry",SHA_A))).get("status")));
        byte[] before=Files.readAllBytes(file);
        rejects(()->links.remember("../preset",ID_A));rejects(()->links.remember(SHA_A,"../discussion"));
        yes(Arrays.equals(before,Files.readAllBytes(file)));
        byte[] corrupt="{broken".getBytes(StandardCharsets.UTF_8);Files.write(file,corrupt);
        rejects(links::snapshot);rejects(()->links.remember(SHA_A,ID_A));yes(Arrays.equals(corrupt,Files.readAllBytes(file)));
        yes(links.optionalSnapshot().isEmpty());
        Files.write(file,SharedJson.encode(SharedRuntime.map("schema",1,"links",SharedRuntime.map(SHA_A,17))).getBytes(StandardCharsets.UTF_8));
        rejects(links::snapshot);
        Files.write(file,new byte[2*1024*1024+1]);rejects(links::snapshot);
        Files.write(file,before);yes(ID_B.equals(links.snapshot().get(SHA_A)));
        try(java.util.stream.Stream<Path> files=Files.list(root)){yes(files.noneMatch(p->p.getFileName().toString().endsWith(".part")));}
        return checks;
    }
}
