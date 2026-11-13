package cc.huevia.shared;

import cc.huevia.library.SharedJson;
import cc.huevia.ncp.*;
import java.io.*;
import java.util.*;
import java.util.function.BooleanSupplier;

/** The original dialog's selection overlay, rendered from real masks and source pixels. */
public final class SharedPortraitOverlay {
    private SharedPortraitOverlay() {}
    public static String render(String json,int[] pixels,int width,int height,BooleanSupplier cancel)throws IOException {
        check(cancel);
        if(pixels==null||width<2||height<2||width>1280||height>1280||pixels.length!=width*height)throw new IOException("人物分析像素无效。");
        Map<String,Object> p=SharedJson.object(json);PhotoLocalEdits local=SharedRetouch.local(p);PhotoPortrait portrait=SharedRetouch.portrait(local,p);
        Map<String,Object> result=SharedJson.object(SharedRetouch.resultFor(local,p,cancel));result.put("selectionOverlay",null);
        AdjustmentRegion.Brush brush=null;String regionId=SharedRuntime.text(p,"regionId",64);
        if(!regionId.isEmpty())for(AdjustmentRegion region:local.regions())if(region.id.equals(regionId)){brush=region.compileBrush(width,height);break;}
        Object flag=p.get("global");if(flag!=null&&!(flag instanceof Boolean))throw new IOException("选区显示范围无效。");boolean global=Boolean.TRUE.equals(flag);
        int w,h;byte[] rgba;
        if(global){
            if(portrait.globalSkinMask==null)return SharedJson.encode(result);
            w=h=PhotoPortrait.BodySkinMask.SIZE;rgba=new byte[w*h*4];byte[] coverage=portrait.globalSkinMask.copyCoverage();
            for(int y=0;y<h;y++){check(cancel);for(int x=0;x<w;x++){
                double selected=brush==null?1:brush.weight((x+.5)/w,(y+.5)/h);
                put(rgba,y*w+x,(int)Math.round((coverage[y*w+x]&255)*38.0/255*selected));
            }}
        }else{
            int index=SharedRuntime.integer(p,"index",0);if(portrait.faces().isEmpty()&&index==-1)return SharedJson.encode(result);
            if(index<0||index>=portrait.faces().size())throw new IOException("请先选择一张人脸。");
            PhotoPortrait.Face face=portrait.faces().get(index).withSettings(PhotoPortrait.Settings.NONE);
            PortraitPreviewFilter.Mask mask=PortraitPreviewFilter.mask(face,width,height);
            w=240;h=Math.max(1,(int)Math.round(height*240.0/width));if(h>320){w=Math.max(1,(int)Math.round(w*320.0/h));h=320;}
            rgba=new byte[w*h*4];
            for(int y=0;y<h;y++){check(cancel);double ny=(y+.5)/h;for(int x=0;x<w;x++){
                double nx=(x+.5)/w;int source=pixels[Math.min(height-1,(int)(ny*height))*width+Math.min(width-1,(int)(nx*width))];
                int alpha=(int)Math.round(mask.weight(source,nx,ny)*38*(brush==null?1:brush.weight(nx,ny)));put(rgba,y*w+x,alpha);
            }}
        }
        // Flutter's rgba8888 raw decoder uses premultiplied channels, as Android's bitmap does.
        result.put("selectionOverlay",SharedRuntime.map("width",w,"height",h,"rgba",Base64.getEncoder().encodeToString(rgba),"premultiplied",true));
        check(cancel);return SharedJson.encode(result);
    }
    private static void put(byte[] rgba,int index,int alpha){int at=index*4;rgba[at]=(byte)alpha;rgba[at+1]=(byte)Math.round(241.0*alpha/255);rgba[at+2]=(byte)Math.round(228.0*alpha/255);rgba[at+3]=(byte)alpha;}
    private static void check(BooleanSupplier cancel)throws InterruptedIOException{if(cancel.getAsBoolean()||Thread.currentThread().isInterrupted())throw new InterruptedIOException("选区已关闭。");}
}
