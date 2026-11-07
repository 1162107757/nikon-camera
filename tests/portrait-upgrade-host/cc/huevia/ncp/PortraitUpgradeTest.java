package cc.huevia.ncp;
import java.io.*;
import java.util.*;
import static cc.huevia.ncp.PortraitRetouch.Parameter.*;

public final class PortraitUpgradeTest {
    private static int checks;
    private static void check(boolean b,String label){checks++;if(!b)throw new AssertionError(label);}
    public static void main(String[] args)throws Exception{wire();skin();face();body();System.out.println("PASS PortraitUpgradeTest "+checks+" checks");}
    private static byte[] bytes(PhotoPortrait p)throws Exception{ByteArrayOutputStream b=new ByteArrayOutputStream();p.write(new DataOutputStream(b));return b.toByteArray();}
    private static PhotoPortrait read(byte[] b)throws Exception{return PhotoPortrait.read(new DataInputStream(new ByteArrayInputStream(b)));}
    private static PhotoPortrait.BodySkinMask mask(boolean half){int n=PhotoPortrait.BodySkinMask.SIZE;byte[] b=new byte[n*n];for(int y=0;y<n;y++)for(int x=0;x<n;x++)if(!half||x<n/2)b[y*n+x]=(byte)255;return new PhotoPortrait.BodySkinMask(b);}
    private static void wire()throws Exception{
        PhotoPortrait legacy=PhotoPortrait.NONE.withGlobalSkinMask(mask(false)).withSkinSmoothing(35);PortraitRetouch p=PortraitRetouch.NONE.with(EVENNESS,55).with(SHINE,40).with(TEXTURE,85).with(NATURAL,20);
        PhotoPortrait active=legacy.withRetouch(p).addFace(faceSettings(PortraitRetouch.NONE.with(TEETH,44).with(FILL,60))).withBodyShape(PhotoBodyShape.NONE.withBackgroundProtection(mask(true),70));
        check(active.identity().startsWith("portrait-v7:"),"optional v7 identity");check(read(bytes(active)).equals(active),"all advanced controls and protection roundtrip");
        PhotoPortrait original=legacy.withRetouch(p).withRetouch(PortraitRetouch.NONE);check(Arrays.equals(bytes(original),bytes(legacy)),"130 exact wire restored");
        check(active.withGlobalTone(PhotoPortrait.Tone.NONE).retouch.equals(p)&&active.withGlobalSkinMask(null).retouch.equals(p)&&active.withBodyShape(PhotoBodyShape.NONE).retouch.equals(p),"global mutations preserve controls");
        PhotoPortrait.Face f=active.faces().get(0);for(PhotoPortrait.Face changed:new PhotoPortrait.Face[]{f.withEnabled(false),f.withSkin(170,140,120),f.withBounds(.5,.5,.4,.4,1),f.withSettings(PhotoPortrait.Settings.NONE),f.withLandmarks(f.landmarks),f.withSkinMask(null),f.withBodySkinMask(null),f.withTone(PhotoPortrait.Tone.NONE),f.withStrokes(Collections.emptyList())})check(changed.retouch.equals(f.retouch),"face mutation preserves controls");
        byte[] broken=bytes(active);try{read(Arrays.copyOf(broken,broken.length-1));throw new AssertionError("truncated protection accepted");}catch(IOException e){checks++;}
        try{PortraitRetouch.NONE.with(TEETH,101);throw new AssertionError("invalid accepted");}catch(IllegalArgumentException e){checks++;}
    }
    private static int[] render(int[] source,int w,int h,PhotoPortrait p)throws Exception{int[] out=source.clone();PortraitPreviewFilter.apply(new SpatialPreviewFilter.Pixels(){public int width(){return w;}public int height(){return h;}public void read(int[] target,int row,int n){System.arraycopy(out,row*w,target,0,n*w);}public void write(int[] pixels,int row,int n){System.arraycopy(pixels,0,out,row*w,n*w);}},p,()->false,null);return out;}
    private static void skin()throws Exception{
        int w=128,h=96;int[] image=new int[w*h];Arrays.fill(image,0xffb89880);for(int y=20;y<50;y++)for(int x=20;x<40;x++)image[y*w+x]=0xffd69a80;for(int y=55;y<70;y++)for(int x=20;x<40;x++)image[y*w+x]=0xffeee8e0;
        PhotoPortrait p=PhotoPortrait.NONE.withGlobalSkinMask(mask(true)).withRetouch(PortraitRetouch.NONE.with(EVENNESS,90).with(SHINE,90));int[] result=render(image,w,h,p);
        check(((result[30*w+30]>>>16)&255)-((result[30*w+30]>>>8)&255)<(0xd6-0x9a),"red blotch chroma reduced");check(luma(result[60*w+30])<luma(image[60*w+30])-3,"specular brightness reduced");
        for(int y=0;y<h;y++)for(int x=75;x<w;x++)check(result[y*w+x]==image[y*w+x],"exterior bit exact");
        check(Arrays.equals(image,render(image,w,h,p.withRetouch(PortraitRetouch.NONE))),"neutral retouch exact");
        PhotoPortrait natural=PhotoPortrait.NONE.withGlobalSkinMask(mask(false)).withRetouch(PortraitRetouch.NONE.with(NATURAL,50));check(!Arrays.equals(image,render(image,w,h,natural)),"natural pipeline actually changes skin");
    }
    private static PhotoPortrait.Face faceSettings(PortraitRetouch p){
        double[] xy=new double[468*2];int[] oval={10,338,297,332,284,251,389,356,454,323,361,288,397,365,379,378,400,377,152,148,176,149,150,136,172,58,132,93,234,127,162,21,54,103,67,109};for(int i=0;i<oval.length;i++){double a=2*Math.PI*i/oval.length;xy[oval[i]*2]=Math.sin(a)*.92;xy[oval[i]*2+1]=-Math.cos(a)*1.2;}
        int[] left={33,7,163,144,145,153,154,155,133,173,157,158,159,160,161,246},right={263,249,390,373,374,380,381,382,362,398,384,385,386,387,388,466},mouth={78,95,88,178,87,14,317,402,318,324,308,415,310,311,312,13,82,81,80,191};ellipse(xy,left,-.48,-.45,.24,.11);ellipse(xy,right,.48,-.45,.24,.11);ellipse(xy,mouth,0,.55,.3,.12);
        return new PhotoPortrait.Face(.5,.5,.4,.4,0,184,152,128,true,PhotoPortrait.Settings.NONE,Collections.emptyList(),new PhotoPortrait.Landmarks(xy),null).withRetouch(p);
    }
    private static void ellipse(double[] xy,int[] indices,double cx,double cy,double rx,double ry){for(int i=0;i<indices.length;i++){double a=2*Math.PI*i/indices.length;xy[indices[i]*2]=cx+rx*Math.cos(a);xy[indices[i]*2+1]=cy+ry*Math.sin(a);}}
    private static void face()throws Exception{
        int w=200,h=200;int[] source=new int[w*h];Arrays.fill(source,0xffb89880);for(int y=65;y<82;y++)for(int x=48;x<69;x++)source[y*w+x]=0xffc5bdb5;for(int y=125;y<140;y++)for(int x=85;x<116;x++)source[y*w+x]=0xffd6c998;
        PhotoPortrait p=PhotoPortrait.NONE.addFace(faceSettings(PortraitRetouch.NONE.with(TEETH,100).with(EYE_WHITE,100)));int[] result=render(source,w,h,p);int eyes=0,teeth=0,outside=0;for(int y=0;y<h;y++)for(int x=0;x<w;x++)if(result[y*w+x]!=source[y*w+x]){if(y>=64&&y<84&&(x>=40&&x<80||x>=120&&x<165))eyes++;else if(y>120&&y<150&&x>70&&x<130)teeth++;else outside++;}check(eyes>0,"eye whites changed");check(teeth>0,"teeth changed");check(outside==0,"no eye/teeth effect outside features");
        PhotoPortrait.Face erased=p.faces().get(0).withStrokes(Arrays.asList(new PhotoPortrait.Stroke(new double[]{.3,.3667},.14,0,true),new PhotoPortrait.Stroke(new double[]{.7,.3667},.14,0,true),new PhotoPortrait.Stroke(new double[]{.5,.663},.14,0,true)));check(Arrays.equals(source,render(source,w,h,p.withFace(0,erased))),"authored face erasure also excludes eye and teeth tools");
        PhotoPortrait left=PhotoPortrait.NONE.addFace(faceSettings(PortraitRetouch.NONE.with(FILL,100).with(LIGHT_X,-100))),right=PhotoPortrait.NONE.addFace(faceSettings(PortraitRetouch.NONE.with(FILL,100).with(LIGHT_X,100)));int[] a=render(source,w,h,left),b=render(source,w,h,right);check(luma(a[100*w+65])>luma(b[100*w+65]),"left light illuminates left cheek");check(luma(b[100*w+135])>luma(a[100*w+135]),"right light illuminates right cheek");
    }
    private static void body()throws Exception{
        PhotoBodyShape s=PhotoBodyShape.NONE.withArea(0,new PhotoBodyShape.Area(.1,.1,.9,.9,65));byte[] data=new byte[PhotoPortrait.BodySkinMask.SIZE*PhotoPortrait.BodySkinMask.SIZE];Arrays.fill(data,(byte)255);s=s.withBackgroundProtection(new PhotoPortrait.BodySkinMask(data),100);double[] p=new double[2];for(int y=0;y<=50;y++)for(int x=0;x<=50;x++){double nx=x/50.0,ny=y/50.0;PhotoBodyWarp.source(s,nx,ny,p);check(p[0]==nx&&p[1]==ny,"fully protected source map exact");}
        PhotoBodyShape turned=s.withArea(1,PhotoBodyShape.NONE.legs.withAmount(45)).withSingleLeg(true);check(turned.backgroundProtection==100&&turned.backgroundMask.equals(s.backgroundMask),"body edits preserve frozen background data");
        int w=128,h=96;int[] source=new int[w*h];for(int y=0;y<h;y++)for(int x=0;x<w;x++)source[y*w+x]=0x80000000|((x*2)<<16)|((y*2)<<8)|96;
        PhotoBodyShape half=PhotoBodyShape.NONE.withArea(0,new PhotoBodyShape.Area(.1,.1,.9,.9,65)).withBackgroundProtection(mask(true),100);int[] output=render(source,w,h,PhotoPortrait.NONE.withBodyShape(half));int changed=0;
        for(int y=0;y<h;y++)for(int x=0;x<w;x++){if(x<50)check(output[y*w+x]==source[y*w+x],"protected full-resolution pixels exact");else if(output[y*w+x]!=source[y*w+x])changed++;check((output[y*w+x]>>>24)==128,"protected warp alpha exact");}check(changed>10,"unprotected body warp still operates");
    }
    private static int luma(int p){return(((p>>>16)&255)+((p>>>8)&255)+(p&255))/3;}
}
