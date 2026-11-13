package cc.huevia.shared;

import cc.huevia.library.SharedJson;
import cc.huevia.ncp.AdjustmentRegion;
import cc.huevia.ncp.PhotoLocalEdits;
import cc.huevia.ncp.PhotoPortrait;
import java.io.IOException;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.BooleanSupplier;

/** Conservative original red-spot selection, source bounds and immutable proposals. */
public final class SharedAutoBlemishesBoundaryTest {
    private static int checks;
    private interface Action { void run() throws Exception; }
    private static void yes(boolean result) { checks++; if(!result)throw new AssertionError("Auto blemishes "+checks); }
    private static void rejects(Action action)throws Exception { checks++;try{action.run();}catch(IOException expected){return;}throw new AssertionError("Invalid blemish analysis accepted"); }
    private static PhotoPortrait skin(boolean full) {
        byte[] mask=new byte[PhotoPortrait.BodySkinMask.SIZE*PhotoPortrait.BodySkinMask.SIZE];
        if(full)Arrays.fill(mask,(byte)255);
        return PhotoPortrait.NONE.withGlobalSkinMask(new PhotoPortrait.BodySkinMask(mask));
    }
    private static Map<String,Object> request(PhotoLocalEdits local,String region)throws Exception {
        Map<String,Object> p=SharedJson.object(SharedRetouch.result(local,()->false));p.put("regionId",region);return p;
    }
    private static Map<String,Object> analyze(Map<String,Object> p,int[] pixels,int w,int h,BooleanSupplier cancel)throws Exception {
        return SharedJson.object(SharedAutoBlemishes.analyze(SharedJson.encode(p),pixels,w,h,cancel));
    }
    @SuppressWarnings("unchecked") private static List<Map<String,Object>> candidates(Map<String,Object> result) { return (List<Map<String,Object>>)result.get("healCandidates"); }
    private static int[] image(int w,int h) { int[] pixels=new int[w*h];Arrays.fill(pixels,0xffc89682);return pixels; }
    public static int run()throws Exception {
        checks=0;int w=256,h=256;int[] pixels=image(w,h);pixels[128*w+128]=0xffcd7d69;
        int[] original=pixels.clone();PhotoLocalEdits local=PhotoLocalEdits.NONE.withPortrait(skin(true));Map<String,Object> p=request(local,"");
        Map<String,Object> result=analyze(p,pixels,w,h,()->false);List<Map<String,Object>> proposed=candidates(result);
        yes(proposed.size()==1);Map<String,Object> one=proposed.get(0);
        yes(one.size()==7&&one.get("enabled").equals(true)&&((Number)one.get("radius")).doubleValue()>=.003);
        yes(Math.abs(((Number)one.get("tx")).doubleValue()-(128.5/w))<1e-10);
        yes(result.get("localData").equals(p.get("localData"))&&SharedRetouch.local(result).portrait.heals().isEmpty());
        yes(Arrays.equals(original,pixels));
        yes(SharedJson.encode(analyze(p,pixels,w,h,()->false)).equals(SharedJson.encode(result)));
        yes(candidates(analyze(p,image(w,h),w,h,()->false)).isEmpty());
        int[] neutral=image(w,h);neutral[128*w+128]=0xffaa7864; // Dark neutral beauty mark: same local red/green difference.
        yes(candidates(analyze(p,neutral,w,h,()->false)).isEmpty());
        yes(candidates(analyze(request(PhotoLocalEdits.NONE.withPortrait(skin(false)),""),pixels,w,h,()->false)).isEmpty());
        rejects(()->analyze(request(PhotoLocalEdits.NONE,""),pixels,w,h,()->false));
        rejects(()->analyze(p,pixels,w,h,()->true));
        AtomicInteger calls=new AtomicInteger();rejects(()->analyze(p,pixels,w,h,()->calls.incrementAndGet()>30));
        yes(Arrays.equals(original,pixels)&&p.get("localData").equals(result.get("localData")));
        rejects(()->analyze(p,new int[3],2,2,()->false));
        rejects(()->SharedAutoBlemishes.analyze(SharedJson.encode(p),null,w,h,()->false));
        PhotoPortrait occupied=skin(true).addHeal(new PhotoPortrait.Heal(.4,.4,128.5/w,128.5/h,.01,.7,true));
        yes(candidates(analyze(request(PhotoLocalEdits.NONE.withPortrait(occupied),""),pixels,w,h,()->false)).isEmpty());
        int[] many=image(w,h);for(int y=0;y<6;y++)for(int x=0;x<6;x++)many[(32+y*32)*w+32+x*32]=0xffcd7d69;
        List<Map<String,Object>> maximum=candidates(analyze(p,many,w,h,()->false));yes(maximum.size()==24);
        for(Map<String,Object> candidate:maximum) {
            double sx=((Number)candidate.get("sx")).doubleValue(),sy=((Number)candidate.get("sy")).doubleValue();
            yes(sx>=0&&sx<=1&&sy>=0&&sy<=1&&local.portrait.globalSkinMask.weight(sx,sy)>.75);
        }
        PhotoPortrait capped=skin(true);for(int i=0;i<63;i++)capped=capped.addHeal(new PhotoPortrait.Heal(.8,.8,.8,.8,.01,.7,true));
        yes(candidates(analyze(request(PhotoLocalEdits.NONE.withPortrait(capped),""),many,w,h,()->false)).size()==1);
        capped=capped.addHeal(new PhotoPortrait.Heal(.8,.8,.8,.8,.01,.7,true));
        yes(candidates(analyze(request(PhotoLocalEdits.NONE.withPortrait(capped),""),many,w,h,()->false)).isEmpty());
        AdjustmentRegion region=AdjustmentRegion.create("局部皮肤").withPortrait(skin(true));
        PhotoLocalEdits regional=PhotoLocalEdits.NONE.withPortrait(skin(false)).addRegion(region);
        Map<String,Object> regionalRequest=request(regional,region.id),regionalResult=analyze(regionalRequest,pixels,w,h,()->false);
        yes(candidates(regionalResult).size()==1&&regionalResult.get("regionId").equals(region.id));
        yes(regionalResult.get("localData").equals(regionalRequest.get("localData")));
        PhotoLocalEdits unchanged=SharedRetouch.local(regionalResult);
        yes(unchanged.portrait.heals().isEmpty()&&unchanged.regions().get(0).portrait.heals().isEmpty());
        yes(candidates(analyze(request(regional,""),pixels,w,h,()->false)).isEmpty());
        regionalRequest.put("regionId","missing");rejects(()->analyze(regionalRequest,pixels,w,h,()->false));
        return checks;
    }
    public static void main(String[] args)throws Exception { System.out.println("Auto blemishes checks: "+run()); }
}
