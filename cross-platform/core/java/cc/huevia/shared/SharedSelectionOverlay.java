package cc.huevia.shared;

import cc.huevia.ncp.*;
import java.io.*;
import java.util.*;
import java.util.function.BooleanSupplier;

/** The original editor's display-only region layer, bounded to a 320px edge. */
public final class SharedSelectionOverlay {
    private SharedSelectionOverlay(){}
    public static Map<String,Object> render(Map<String,Object> p,BooleanSupplier cancel)throws IOException{
        check(cancel);
        int sw=dimension(p,"sourceWidth"),sh=dimension(p,"sourceHeight"),ow=dimension(p,"outputWidth"),oh=dimension(p,"outputHeight");
        SharedRecipe recipe=new SharedRecipe(cc.huevia.library.SharedJson.encode(SharedRuntime.object(p.get("recipe"))));
        String id=SharedRuntime.text(p,"regionId",64);AdjustmentRegion region=null;
        for(AdjustmentRegion candidate:recipe.local.regions())if(candidate.id.equals(id)){region=candidate;break;}
        if(region==null)throw new IOException("局部区域已变化，请重新选择。");
        PhotoGeometry.Plan plan=recipe.geometry.plan(sw,sh,1);PhotoBorder frame=recipe.border;
        int[] framed=frame.dimensions(plan.width,plan.height);
        double scale=Math.min(1,320.0/Math.max(ow,oh));int w=Math.max(1,(int)Math.round(ow*scale)),h=Math.max(1,(int)Math.round(oh*scale));
        byte[] rgba=new byte[w*h*4];float margin=frame.margin/100f;
        float left=frame.isNone()||frame.template==3?0:frame.template==1?(framed[0]-plan.width)/2f:framed[0]-plan.width-plan.width*.08f*margin;
        float top=frame.isNone()||frame.template==3?0:plan.width*(frame.template==1?.06f:.07f)*margin;
        double radius=frame.isNone()||frame.template==3?0:plan.width*.025f*frame.corner/100f;
        radius=Math.min(radius,Math.min(plan.width,plan.height)/2.0);
        AdjustmentRegion.Brush brush=region.compileBrush(sw,sh);
        for(int y=0;y<h;y++){
            check(cancel);
            for(int x=0;x<w;x++){
                double px=(x+.5)*framed[0]/w-left,py=(y+.5)*framed[1]/h-top;
                if(px<0||py<0||px>=plan.width||py>=plan.height)continue;
                if(radius>0){double dx=px-Math.max(radius,Math.min(plan.width-radius,px)),dy=py-Math.max(radius,Math.min(plan.height-radius,py));if(dx*dx+dy*dy>radius*radius)continue;}
                double[] source=plan.inverse(px,py);
                if(source[0]<0||source[1]<0||source[0]>=sw||source[1]>=sh)continue;
                PhotoBodyWarp.source(recipe.local.portrait.bodyShape,source[0]/sw,source[1]/sh,source);
                int alpha=(int)Math.round(38*brush.weight(source[0],source[1])),at=(y*w+x)*4;
                // Flutter's rgba8888 decoder consumes premultiplied channels.
                rgba[at]=(byte)alpha;rgba[at+1]=(byte)Math.round(241*alpha/255.0);rgba[at+2]=(byte)Math.round(228*alpha/255.0);rgba[at+3]=(byte)alpha;
            }
        }
        check(cancel);
        return SharedRuntime.map("width",w,"height",h,"rgba",Base64.getEncoder().encodeToString(rgba));
    }
    private static int dimension(Map<String,Object> p,String key)throws IOException{
        Object value=p.get(key);if(!(value instanceof Number))throw new IOException("选区预览尺寸无效。");
        double n=((Number)value).doubleValue();if(!Double.isFinite(n)||n!=Math.rint(n)||n<1||n>65535)throw new IOException("选区预览尺寸无效。");return (int)n;
    }
    private static void check(BooleanSupplier cancel)throws InterruptedIOException{
        if(Thread.currentThread().isInterrupted()||cancel!=null&&cancel.getAsBoolean())throw new InterruptedIOException("选区预览已取消。");
    }
}
