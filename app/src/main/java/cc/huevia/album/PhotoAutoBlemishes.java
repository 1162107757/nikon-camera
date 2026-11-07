package cc.huevia.album;
import android.graphics.Bitmap;
import cc.huevia.ncp.PhotoPortrait;
import java.io.*;
import java.util.*;
import java.util.function.BooleanSupplier;

/** Conservative small red-spot proposals. Dark neutral beauty marks are not candidates. */
public final class PhotoAutoBlemishes {
    private PhotoAutoBlemishes(){}
    public static List<PhotoPortrait.Heal> detect(Bitmap image,PhotoPortrait.BodySkinMask skin,List<PhotoPortrait.Heal> existing,BooleanSupplier cancel)throws IOException{
        if(image==null||skin==null)throw new IOException("请先识别皮肤。");if(existing.size()>=PhotoPortrait.MAX_HEALS)return Collections.emptyList();int w=image.getWidth(),h=image.getHeight(),radius=Math.max(2,Math.round(Math.min(w,h)*.005f));ArrayList<double[]> candidates=new ArrayList<>();
        for(int y=radius*2;y<h-radius*2;y++){check(cancel);for(int x=radius*2;x<w-radius*2;x++){
            double nx=(x+.5)/w,ny=(y+.5)/h;if(skin.weight(nx,ny)<.85)continue;int q=image.getPixel(x,y),r=(q>>>16)&255,g=(q>>>8)&255,b=q&255;double rr=0,gg=0,bb=0,square=0;int count=0;
            for(int dy=-2;dy<=2;dy++)for(int dx=-2;dx<=2;dx++)if(Math.abs(dx)==2||Math.abs(dy)==2){int xx=x+dx*radius,yy=y+dy*radius;if(skin.weight((xx+.5)/w,(yy+.5)/h)<.7)continue;int p=image.getPixel(xx,yy);double ar=(p>>>16)&255,ag=(p>>>8)&255,ab=p&255;rr+=ar;gg+=ag;bb+=ab;double l=.2126*ar+.7152*ag+.0722*ab;square+=l*l;count++;}
            if(count<12)continue;rr/=count;gg/=count;bb/=count;double local=.2126*rr+.7152*gg+.0722*bb,var=square/count-local*local,red=(r-g)-(rr-gg),dark=local-(.2126*r+.7152*g+.0722*b);
            if(red<10||red>48||dark<3||dark>38||var>70||g<35)continue;boolean near=false;for(PhotoPortrait.Heal heal:existing)if(Math.hypot((nx-heal.tx)*w,(ny-heal.ty)*h)<radius*4){near=true;break;}if(!near)candidates.add(new double[]{nx,ny,red+dark*.4});
        }}
        candidates.sort((a,b)->Double.compare(b[2],a[2]));ArrayList<PhotoPortrait.Heal> result=new ArrayList<>();double separation=radius*5.0/Math.min(w,h),brush=Math.max(.003,Math.min(.016,radius*1.8/Math.min(w,h)));
        for(double[] c:candidates){check(cancel);boolean near=false;for(PhotoPortrait.Heal p:result)if(Math.hypot(c[0]-p.tx,c[1]-p.ty)<separation){near=true;break;}if(near)continue;PhotoPortrait.Heal proposal=PhotoPortraitDetection.heal(image,c[0],c[1],brush);if(proposal!=null&&skin.weight(proposal.sx,proposal.sy)>.75)result.add(proposal);if(result.size()>=Math.min(24,PhotoPortrait.MAX_HEALS-existing.size()))break;}
        return Collections.unmodifiableList(result);
    }
    private static void check(BooleanSupplier c)throws InterruptedIOException{if(Thread.currentThread().isInterrupted()||c.getAsBoolean())throw new InterruptedIOException("自动祛痘已取消。");}
}
