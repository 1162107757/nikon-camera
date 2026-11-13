package cc.huevia.shared;

import cc.huevia.library.SharedJson;
import cc.huevia.ncp.PhotoLocalEdits;
import cc.huevia.ncp.PhotoPortrait;
import java.io.IOException;
import java.io.InterruptedIOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.function.BooleanSupplier;

/** Original PhotoAutoBlemishes proposal criteria on bounded shared raster pixels. */
public final class SharedAutoBlemishes {
    private SharedAutoBlemishes() {}
    public static String analyze(String json, int[] pixels, int width, int height, BooleanSupplier cancel) throws IOException {
        check(cancel);
        if (pixels == null || width < 2 || height < 2 || width > 1280 || height > 1280 || pixels.length != width * height)
            throw new IOException("人物分析像素无效。");
        Map<String,Object> p = SharedJson.object(json);
        PhotoLocalEdits local = SharedRetouch.local(p);
        PhotoPortrait portrait = SharedRetouch.portrait(local, p);
        if (portrait.globalSkinMask == null) throw new IOException("请先识别皮肤。");
        List<PhotoPortrait.Heal> found = portrait.heals().size() >= PhotoPortrait.MAX_HEALS
                ? Collections.emptyList() : detect(p, pixels, width, height, portrait, cancel);
        Map<String,Object> result = SharedJson.object(SharedRetouch.resultFor(local, p, cancel));
        List<Object> rows = new ArrayList<>();
        for (PhotoPortrait.Heal heal : found) {
            check(cancel); Map<String,Object> row = new LinkedHashMap<>();
            row.put("sx", heal.sx); row.put("sy", heal.sy); row.put("tx", heal.tx); row.put("ty", heal.ty);
            row.put("radius", heal.radius); row.put("feather", heal.feather); row.put("enabled", heal.enabled); rows.add(row);
        }
        result.put("healCandidates", rows); check(cancel); return SharedJson.encode(result);
    }

    private static List<PhotoPortrait.Heal> detect(Map<String,Object> p, int[] pixels, int w, int h,
            PhotoPortrait portrait, BooleanSupplier cancel) throws IOException {
        PhotoPortrait.BodySkinMask skin = portrait.globalSkinMask;
        List<PhotoPortrait.Heal> existing = portrait.heals();
        int radius = Math.max(2, Math.round(Math.min(w,h) * .005f));
        ArrayList<double[]> candidates = new ArrayList<>();
        for (int y=radius*2; y<h-radius*2; y++) {
            check(cancel);
            for (int x=radius*2; x<w-radius*2; x++) {
                double nx=(x+.5)/w, ny=(y+.5)/h;
                if (skin.weight(nx,ny)<.85) continue;
                int q=pixels[y*w+x], r=(q>>>16)&255, g=(q>>>8)&255, b=q&255;
                double rr=0,gg=0,bb=0,square=0; int count=0;
                for (int dy=-2;dy<=2;dy++) for (int dx=-2;dx<=2;dx++) if (Math.abs(dx)==2||Math.abs(dy)==2) {
                    int xx=x+dx*radius, yy=y+dy*radius;
                    if (skin.weight((xx+.5)/w,(yy+.5)/h)<.7) continue;
                    int pixel=pixels[yy*w+xx]; double ar=(pixel>>>16)&255, ag=(pixel>>>8)&255, ab=pixel&255;
                    rr+=ar; gg+=ag; bb+=ab; double luminance=.2126*ar+.7152*ag+.0722*ab; square+=luminance*luminance; count++;
                }
                if (count<12) continue;
                rr/=count; gg/=count; bb/=count;
                double local=.2126*rr+.7152*gg+.0722*bb, variance=square/count-local*local;
                double red=(r-g)-(rr-gg), dark=local-(.2126*r+.7152*g+.0722*b);
                if (red<10||red>48||dark<3||dark>38||variance>70||g<35) continue;
                boolean near=false;
                for (PhotoPortrait.Heal heal:existing) if (Math.hypot((nx-heal.tx)*w,(ny-heal.ty)*h)<radius*4) { near=true; break; }
                if (!near) candidates.add(new double[]{nx,ny,red+dark*.4});
            }
        }
        candidates.sort((a,b)->Double.compare(b[2],a[2]));
        ArrayList<PhotoPortrait.Heal> result=new ArrayList<>();
        double separation=radius*5.0/Math.min(w,h), brush=Math.max(.003,Math.min(.016,radius*1.8/Math.min(w,h)));
        for (double[] candidate:candidates) {
            check(cancel); boolean near=false;
            for (PhotoPortrait.Heal prior:result) if (Math.hypot(candidate[0]-prior.tx,candidate[1]-prior.ty)<separation) { near=true; break; }
            if (near) continue;
            PhotoPortrait.Heal proposal = proposal(p, pixels, w, h, candidate[0], candidate[1], brush, cancel);
            if (proposal!=null&&skin.weight(proposal.sx,proposal.sy)>.75) result.add(proposal);
            if (result.size()>=Math.min(24,PhotoPortrait.MAX_HEALS-existing.size())) break;
        }
        return result;
    }

    private static PhotoPortrait.Heal proposal(Map<String,Object> p,int[] pixels,int w,int h,
            double x,double y,double radius,BooleanSupplier cancel)throws IOException {
        Map<String,Object> temporary = new LinkedHashMap<>(p);
        temporary.put("x",x); temporary.put("y",y); temporary.put("radius",radius);
        try {
            Map<String,Object> response=SharedJson.object(SharedPortraitInference.heal(SharedJson.encode(temporary),pixels,w,h,cancel));
            PhotoPortrait next=SharedRetouch.portrait(SharedRetouch.local(response),p);
            return next.heals().get(next.heals().size()-1);
        } catch (InterruptedIOException cancelled) { throw cancelled; }
        catch (IOException unavailable) {
            if ("瑕疵太靠近边缘，请缩小修复范围。".equals(unavailable.getMessage())) return null;
            throw unavailable;
        }
    }
    private static void check(BooleanSupplier cancel)throws InterruptedIOException {
        if (Thread.currentThread().isInterrupted()||cancel.getAsBoolean()) throw new InterruptedIOException("自动祛痘已取消。");
    }
}
