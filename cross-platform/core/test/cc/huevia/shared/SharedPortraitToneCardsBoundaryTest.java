package cc.huevia.shared;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.BooleanSupplier;

/** Real account-private persistence, corruption preservation and cancellation. */
public final class SharedPortraitToneCardsBoundaryTest {
    private static int checks;
    private interface Action { void run() throws Exception; }
    private static void yes(boolean result) { checks++; if (!result) throw new AssertionError("Portrait tone cards " + checks); }
    private static void rejects(Action action) throws Exception { checks++; try { action.run(); } catch (IOException expected) { return; } throw new AssertionError("Invalid tone card accepted"); }
    private static Map<String,Object> values(Object... pairs) { Map<String,Object> result = new LinkedHashMap<>(); for(int i=0;i<pairs.length;i+=2)result.put((String)pairs[i],pairs[i+1]);return result; }
    @SuppressWarnings("unchecked") private static List<Map<String,Object>> request(Path root,String owner,String op,Map<String,Object> p,BooleanSupplier cancel)throws Exception {
        return (List<Map<String,Object>>)SharedPortraitToneCards.request(root.toFile(),owner,"toneCards."+op,p,cancel).get("cards");
    }
    private static List<Map<String,Object>> request(Path root,String owner,String op,Map<String,Object> p)throws Exception{return request(root,owner,op,p,()->false);}
    public static int run(Path temporary)throws Exception {
        checks=0;Path root=temporary.resolve("portrait-tone-card-boundary");Files.createDirectories(root);
        yes(request(root,"alice","list",Collections.emptyMap()).isEmpty());
        List<Map<String,Object>> cards=request(root,"alice","save",values("name"," 日常暖肤 ","rgb",0xc9977c));
        yes(cards.size()==1&&cards.get(0).get("name").equals("日常暖肤")&&((Number)cards.get(0).get("rgb")).intValue()==0xc9977c);
        String id=(String)cards.get(0).get("id");yes(id.matches("[0-9a-f-]{36}"));
        yes(request(root,"bob","list",Collections.emptyMap()).isEmpty());
        yes(request(root,"alice","list",Collections.emptyMap()).equals(cards));
        Path stored;try(java.util.stream.Stream<Path> paths=Files.walk(root)){stored=paths.filter(p->p.getFileName().toString().equals("swatches_v1.json")).findFirst().orElseThrow();}
        byte[] before=Files.readAllBytes(stored);yes(new String(before,StandardCharsets.UTF_8).startsWith("[{\"id\":"));
        rejects(()->request(root,"alice","save",values("name","日常暖肤","rgb",1)));
        rejects(()->request(root,"alice","save",values("name","其他颜色","rgb",0xc9977c)));
        rejects(()->request(root,"alice","save",values("name"," ","rgb",2)));
        rejects(()->request(root,"alice","save",values("name","1234567890123","rgb",2)));
        rejects(()->request(root,"alice","save",values("name","换\n行","rgb",2)));
        rejects(()->request(root,"alice","save",values("name","小数","rgb",2.5)));
        rejects(()->request(root,"alice","save",values("name","越界","rgb",0x1000000)));
        rejects(()->request(root,"alice","remove",values("id","../escape")));
        rejects(()->request(root,null,"list",Collections.emptyMap()));
        yes(Arrays.equals(before,Files.readAllBytes(stored)));
        rejects(()->request(root,"alice","save",values("name","已取消","rgb",2),()->true));
        AtomicInteger calls=new AtomicInteger();
        rejects(()->request(root,"alice","save",values("name","写入前取消","rgb",2),()->calls.incrementAndGet()==4));
        yes(Arrays.equals(before,Files.readAllBytes(stored)));
        try(java.util.stream.Stream<Path> paths=Files.walk(root)){yes(paths.noneMatch(p->p.getFileName().toString().endsWith(".part")));}
        request(root,"bob","save",values("name","日常暖肤","rgb",0xc9977c));yes(request(root,"alice","list",Collections.emptyMap()).equals(cards));
        yes(request(root,"","list",Collections.emptyMap()).isEmpty());
        List<Map<String,Object>> guest=request(root,"","save",values("name","访客暖肤","rgb",0xabc123));
        yes(guest.size()==1&&request(root,"","list",Collections.emptyMap()).equals(guest));
        yes(request(root,"alice","list",Collections.emptyMap()).equals(cards)&&request(root,"bob","list",Collections.emptyMap()).size()==1);
        for(int i=0;i<11;i++)request(root,"alice","save",values("name","色卡"+i,"rgb",i));
        yes(request(root,"alice","list",Collections.emptyMap()).size()==12);
        rejects(()->request(root,"alice","save",values("name","第十三张","rgb",100)));
        yes(request(root,"alice","remove",values("id",id)).size()==11);
        yes(request(root,"bob","list",Collections.emptyMap()).size()==1);
        byte[] valid=Files.readAllBytes(stored);Files.write(stored,"[{}]".getBytes(StandardCharsets.UTF_8));
        rejects(()->request(root,"alice","save",values("name","不可覆盖损坏","rgb",100)));
        yes(new String(Files.readAllBytes(stored),StandardCharsets.UTF_8).equals("[{}]"));Files.write(stored,valid);
        Path blocked=temporary.resolve("portrait-tone-card-blocked");Files.createDirectories(blocked);Files.write(blocked.resolve("portrait-tone-cards"),new byte[]{1});
        rejects(()->request(blocked,"alice","save",values("name","被阻断","rgb",1)));
        yes(Files.readAllBytes(blocked.resolve("portrait-tone-cards"))[0]==1);
        return checks;
    }
    public static void main(String[] args)throws Exception { System.out.println("Portrait tone cards checks: "+run(Files.createTempDirectory("portrait-tone-cards-test-"))); }
}
