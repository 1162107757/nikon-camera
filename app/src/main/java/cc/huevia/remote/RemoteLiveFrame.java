package cc.huevia.remote;

import java.io.IOException;
import java.util.Arrays;

/** One bounded JPEG from a Nikon live-view response, with validated AF coordinate metadata. */
public final class RemoteLiveFrame {
    public final byte[] jpeg;
    public final int width,height,afWidth,afHeight,rotation;
    public final boolean focusKnown,focused;
    private RemoteLiveFrame(byte[] jpeg,int width,int height,int aw,int ah,boolean known,boolean focused){
        this.jpeg=jpeg;this.width=width;this.height=height;afWidth=aw;afHeight=ah;focusKnown=known;this.focused=focused;rotation=0;
    }
    private RemoteLiveFrame(RemoteLiveFrame source,int rotation){jpeg=source.jpeg;width=source.width;height=source.height;afWidth=source.afWidth;afHeight=source.afHeight;focusKnown=source.focusKnown;focused=source.focused;this.rotation=rotation;}
    public static RemoteLiveFrame parse(byte[] data) throws IOException {
        if(data==null||data.length<16||data.length>8*1024*1024)throw new IOException("取景帧不完整。");
        int start=-1,end=-1,w=0,h=0;
        for(int i=0;i<Math.min(data.length-1,4096);i++)if((data[i]&255)==255&&(data[i+1]&255)==216){start=i;break;}
        if(start<0)throw new IOException("相机没有返回 JPEG 取景帧。");
        int at=start+2;boolean scan=false;
        while(at<data.length){
            if((data[at++]&255)!=255){if(scan)continue;throw new IOException("取景 JPEG 标记无效。");}
            while(at<data.length&&(data[at]&255)==255)at++;
            if(at>=data.length)break;
            int marker=data[at++]&255;
            if(marker==0&&scan)continue;
            if(marker==217){end=at;break;}
            if(marker>=208&&marker<=215)continue;
            if(marker==216||marker==0)throw new IOException("取景 JPEG 标记无效。");
            if(at+2>data.length)break;
            int length=((data[at]&255)<<8)|(data[at+1]&255);
            if(length<2||at+length>data.length)throw new IOException("取景 JPEG 数据被截断。");
            if(marker==192||marker==193||marker==194){
                if(length<8)throw new IOException("取景 JPEG 尺寸无效。");
                h=((data[at+3]&255)<<8)|(data[at+4]&255);w=((data[at+5]&255)<<8)|(data[at+6]&255);
            }
            if(marker==218)scan=true;
            at+=length;
        }
        if(end<0||w<1||h<1||w>4096||h>4096||(long)w*h>8_000_000)throw new IOException("取景 JPEG 不完整或尺寸超出上限。");
        int aw=0,ah=0;
        // Nikon Z-family live-view metadata uses little-endian image/AF extents.
        // Only expose tap AF when the decoded JPEG and reported frame geometry agree.
        if(start>=64&&RemoteProperty.u16(data,0)==w&&RemoteProperty.u16(data,2)==h){
            aw=RemoteProperty.u16(data,4);ah=RemoteProperty.u16(data,6);
            if(aw<1||ah<1||aw>16384||ah>16384||Math.abs((long)aw*h-(long)ah*w)>Math.max((long)aw*h,(long)ah*w)/100){aw=0;ah=0;}
        }
        RemoteLiveFrame frame=new RemoteLiveFrame(Arrays.copyOfRange(data,start,end),w,h,aw,ah,aw>0&&ah>0,(aw>0&&ah>0)&&(data[40]&255)==2);
        if(aw>0&&ah>0&&(data[29]==1||data[29]==2))return new RemoteLiveFrame(frame,data[29]==1?-90:90);
        return frame;
    }
    public int[] focusPoint(double x,double y) throws IOException {
        if(afWidth==0||afHeight==0||!Double.isFinite(x)||!Double.isFinite(y)||x<0||x>1||y<0||y>1)throw new IOException("当前取景帧没有可用的点按对焦坐标。");
        if(rotation==90){double old=x;x=y;y=1-old;}else if(rotation==-90){double old=x;x=1-y;y=old;}
        return new int[]{(int)Math.round(x*(afWidth-1)),(int)Math.round(y*(afHeight-1))};
    }
}
