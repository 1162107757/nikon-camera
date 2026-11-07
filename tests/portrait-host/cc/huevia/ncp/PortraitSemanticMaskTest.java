package cc.huevia.ncp;

import java.io.IOException;
import java.util.*;

/** Synthetic semantic probabilities verify processing contracts, not inference or photo quality. */
public final class PortraitSemanticMaskTest {
    private static final int SKIN=0xffb48269,COOL=0xff2060d0;
    private static int checks;
    public static void main(String[] args)throws Exception{
        PhotoPortrait.Face face=PortraitLandmarkMaskTest.face(0).withSkinMask(semantic());
        coverageAndExclusions(face);
        strokes(face);
        frames(face);
        render(face,401,277);
        // Clip the left cheek while keeping the upper-forehead oracle in the image.
        render(face.withBounds(.14,.55,.22,.20,31),257,173);
        exif(face.withBounds(.5,.52,.15,.18,27));
        absentSemantic(face);
        System.out.println("PASS PortraitSemanticMaskTest "+checks+" checks");
    }
    private static void coverageAndExclusions(PhotoPortrait.Face face){
        int w=384,h=256;
        check(weight(face,SKIN,0,-1.85,w,h)==1,"semantic forehead above mesh and old ellipse is preserved");
        check(weight(face,COOL,0,-1.85,w,h)==1,"semantic forehead is not clipped a second time by sampled chroma");
        check(weight(face,SKIN,1.25,-.15,w,h)==1&&weight(face,SKIN,-1.25,-.15,w,h)==1,"semantic side cheeks are preserved");
        check(weight(face,SKIN,.88,0,w,h)==0,"semantic occluding-hand hole inside the mesh stays zero");
        check(weight(face.withSkinMask(null),SKIN,.88,0,w,h)>.9,"hand-hole oracle is genuinely inside the old geometric coverage");
        check(weight(face,SKIN,1.58,1.3,w,h)==0&&weight(face,SKIN,1.9,0,w,h)==0,"same-colour background is excluded by semantic field and its bounds");
        for(double[] p:new double[][]{{-.58,-.06},{.6,-.08},{-.55,-.27},{.58,-.30},{0,.78},{-.12,.4},{.12,.4}})
            check(weight(face,SKIN,p[0],p[1],w,h)==0,"actual eye/brow/lip/nostril remains protected under positive semantic coverage");
        check(weight(face,SKIN,-.526,-.407,w,h)>.9&&weight(face,SKIN,0,.55,w,h)>.9,"semantic branch does not reintroduce old misplaced feature holes");
        double[] p=world(face,0,-1.85,w,h);
        check(PortraitPreviewFilter.faceContains(face,p[0],p[1],w,h),"semantic forehead outside mesh is selectable");
        check(weight(face.withEnabled(false),SKIN,0,-1.85,w,h)==0&&PortraitPreviewFilter.faceContains(face.withEnabled(false),p[0],p[1],w,h),"disabled semantic face stays selectable but cannot affect pixels");
        check(PortraitPreviewFilter.mask(face,w,h).weight(SKIN&0xffffff,p[0],p[1])==0,"semantic confidence does not override alpha protection");
        PhotoPortrait.Face noMesh=face.withLandmarks(null);
        check(weight(noMesh,COOL,0,-1.85,w,h)==1,"semantic-only face does not inherit the legacy top gate");
        check(weight(noMesh,SKIN,-.526,-.407,w,h)==0&&weight(noMesh,SKIN,0,.55,w,h)==0,"semantic-only face keeps fallback feature protection");
        byte[] half=new byte[128*128];Arrays.fill(half,(byte)128);
        PhotoPortrait.Face confidence=face.withSkinMask(new PhotoPortrait.SkinMask(-1.65,-2.15,1.65,1.5,half));
        near(weight(confidence,COOL,0,-1.85,w,h),128/255.0,1e-12,"semantic soft confidence is retained without a binary cutoff");
    }
    private static void strokes(PhotoPortrait.Face face){
        int w=384,h=256;double[] hole=world(face,.88,0,w,h),forehead=world(face,0,-1.85,w,h),outside=world(face,1.85,0,w,h),eye=world(face,-.58,-.06,w,h);
        check(PortraitPreviewFilter.mask(face.addStroke(stroke(hole,false)),w,h).weight(SKIN,hole[0],hole[1])==1,"manual add can deliberately restore a semantic hole");
        PhotoPortrait.Face erased=face.addStroke(stroke(forehead,true));
        check(PortraitPreviewFilter.mask(erased,w,h).weight(SKIN,forehead[0],forehead[1])==0,"manual erase removes semantic forehead");
        check(PortraitPreviewFilter.mask(erased.addStroke(stroke(forehead,false)),w,h).weight(SKIN,forehead[0],forehead[1])==1,"later add restores semantic forehead in order");
        check(PortraitPreviewFilter.mask(face.addStroke(stroke(outside,false)),w,h).weight(COOL,outside[0],outside[1])==1,"explicit add extends beyond semantic bounds and chroma");
        check(PortraitPreviewFilter.mask(face.addStroke(stroke(eye,false)),w,h).weight(SKIN,eye[0],eye[1])==1,"explicit add follows feature protection");
    }
    private static void frames(PhotoPortrait.Face face){
        double[][] points={{0,-1.85},{1.25,-.15},{-1.25,-.15},{.88,0},{-.58,-.06},{0,.78},{-.526,-.407}};
        for(int[] size:new int[][]{{384,256},{480,287},{287,480}})for(int roll:new int[]{0,31,-47}){
            PhotoPortrait.Face transformed=face.withBounds(.5,.52,.14,.17,roll);
            for(double[] p:points)near(weight(transformed,SKIN,p[0],p[1],size[0],size[1]),weight(face,SKIN,p[0],p[1],384,256),1e-10,"semantic local probabilities survive aspect and roll");
            double[] top=world(transformed,0,-1.85,size[0],size[1]);check(PortraitPreviewFilter.faceContains(transformed,top[0],top[1],size[0],size[1]),"rotated semantic forehead remains selectable");
        }
    }
    private static void render(PhotoPortrait.Face face,int w,int h)throws Exception{
        Raster source=image(w,h),actual=source.copy();int[] expected=source.data.clone();PortraitPreviewFilter.Mask mask=PortraitPreviewFilter.mask(face,w,h);int expanded=0;
        for(int y=0;y<h;y++)for(int x=0;x<w;x++){
            double nx=(x+.5)/w,ny=(y+.5)/h,amount=mask.weight(source.at(x,y),nx,ny);expected[y*w+x]=lift(source.at(x,y),amount);
            double[] p=local(face,nx,ny,w,h);if(p[1]<-1.65&&amount>.5&&expected[y*w+x]!=source.at(x,y))expanded++;
        }
        PortraitPreviewFilter.apply(actual,new PhotoPortrait(List.of(face),List.of()),()->false,null);
        exact(expected,actual.data,"semantic full-render bounds cover forehead outside mesh and preserve every hole");
        check(expanded>30,"full-image oracle actually exercises above-mesh semantic pixels");
        double[] outside=world(face,1.85,0,w,h);if(outside[0]>.05&&outside[0]<.95&&outside[1]>.05&&outside[1]<.95){
            PhotoPortrait.Face painted=face.addStroke(stroke(outside,false));PortraitPreviewFilter.Mask added=PortraitPreviewFilter.mask(painted,w,h);Raster result=source.copy();
            for(int y=0;y<h;y++)for(int x=0;x<w;x++)expected[y*w+x]=lift(source.at(x,y),added.weight(source.at(x,y),(x+.5)/w,(y+.5)/h));
            PortraitPreviewFilter.apply(result,new PhotoPortrait(List.of(painted),List.of()),()->false,null);exact(expected,result.data,"manual add expands semantic processing bounds");
        }
    }
    private static void exif(PhotoPortrait.Face face)throws Exception{
        Raster canonical=image(211,149),expected=canonical.copy();PortraitPreviewFilter.apply(expected,new PhotoPortrait(List.of(face),List.of()),()->false,null);
        for(int exif=1;exif<=8;exif++){Raster raw=rawFromOriented(canonical,exif);PortraitPreviewFilter.apply(raw,new PhotoPortrait(List.of(face),List.of()),exif,()->false,null);exact(expected.data,oriented(raw,exif).data,"semantic mask follows integer EXIF mapping "+exif);}
    }
    private static void absentSemantic(PhotoPortrait.Face face)throws Exception{
        PhotoPortrait.Face mesh=face.withSkinMask(null);int w=384,h=256;
        check(weight(mesh,SKIN,0,-1.85,w,h)==0,"absent semantic data preserves mesh-only outer boundary");
        check(weight(mesh,COOL,1.15,-.15,w,h)==0,"mesh-only branch retains chroma acceptance");
        PhotoPortrait.Face legacy=mesh.withLandmarks(null);
        check(weight(legacy,SKIN,0,-1.3,w,h)==0&&weight(legacy,SKIN,1.15,-.15,w,h)==0,"absent semantic and mesh retain legacy geometry");
        PhotoPortrait.Face constructor=new PhotoPortrait.Face(legacy.cx,legacy.cy,legacy.rx,legacy.ry,legacy.roll,legacy.skinR,legacy.skinG,legacy.skinB,legacy.enabled,legacy.settings,legacy.strokes);
        Raster a=image(193,137),b=a.copy();PortraitPreviewFilter.apply(a,new PhotoPortrait(List.of(legacy),List.of()),()->false,null);PortraitPreviewFilter.apply(b,new PhotoPortrait(List.of(constructor),List.of()),()->false,null);exact(a.data,b.data,"cleared optional data and legacy constructor render the same pixels");
    }
    private static PhotoPortrait.SkinMask semantic(){
        double left=-1.65,top=-2.15,right=1.65,bottom=1.5;byte[] p=new byte[128*128];
        for(int y=0;y<128;y++)for(int x=0;x<128;x++){
            double u=left+(x+.5)/128*(right-left),v=top+(y+.5)/128*(bottom-top);
            boolean face=Math.pow(u/1.5,2)+Math.pow((v+.25)/1.75,2)<1,hand=Math.pow((u-.88)/.15,2)+Math.pow(v/.36,2)<1;
            if(face&&!hand)p[y*128+x]=(byte)255;
        }
        return new PhotoPortrait.SkinMask(left,top,right,bottom,p);
    }
    private static double weight(PhotoPortrait.Face f,int colour,double u,double v,int w,int h){double[] p=world(f,u,v,w,h);return PortraitPreviewFilter.mask(f,w,h).weight(colour,p[0],p[1]);}
    private static double[] world(PhotoPortrait.Face f,double u,double v,int w,int h){double a=Math.toRadians(f.roll),x=u*f.rx*w,y=v*f.ry*h;return new double[]{f.cx+(Math.cos(a)*x-Math.sin(a)*y)/w,f.cy+(Math.sin(a)*x+Math.cos(a)*y)/h};}
    private static double[] local(PhotoPortrait.Face f,double nx,double ny,int w,int h){double a=Math.toRadians(f.roll),x=(nx-f.cx)*w,y=(ny-f.cy)*h;return new double[]{(Math.cos(a)*x+Math.sin(a)*y)/(f.rx*w),(-Math.sin(a)*x+Math.cos(a)*y)/(f.ry*h)};}
    private static PhotoPortrait.Stroke stroke(double[] p,boolean erase){return new PhotoPortrait.Stroke(p,.025,.5,erase);}
    private static int lift(int source,double amount){int result=source&0xff000000;for(int shift:new int[]{16,8,0}){int value=(source>>>shift)&255,target=(int)Math.round(value+(255-value)*.066);result|=(int)Math.round(value+(target-value)*amount)<<shift;}return result;}
    private static Raster image(int w,int h){Raster r=new Raster(w,h);for(int y=0;y<h;y++)for(int x=0;x<w;x++)r.data[y*w+x]=0xff000000|(70+x%140)<<16|(80+y%100)<<8|(40+(x+y)%170);return r;}
    private static Raster rawFromOriented(Raster canonical,int exif){Raster raw=new Raster(exif>=5?canonical.h:canonical.w,exif>=5?canonical.w:canonical.h);for(int y=0;y<raw.h;y++)for(int x=0;x<raw.w;x++)raw.data[y*raw.w+x]=canonical.data[oy(x,y,raw.w,raw.h,exif)*canonical.w+ox(x,y,raw.w,raw.h,exif)];return raw;}
    private static Raster oriented(Raster raw,int exif){Raster result=new Raster(exif>=5?raw.h:raw.w,exif>=5?raw.w:raw.h);for(int y=0;y<raw.h;y++)for(int x=0;x<raw.w;x++)result.data[oy(x,y,raw.w,raw.h,exif)*result.w+ox(x,y,raw.w,raw.h,exif)]=raw.data[y*raw.w+x];return result;}
    private static int ox(int x,int y,int w,int h,int e){switch(e){case 2:case 3:return w-1-x;case 5:case 8:return y;case 6:case 7:return h-1-y;default:return x;}}
    private static int oy(int x,int y,int w,int h,int e){switch(e){case 3:case 4:return h-1-y;case 5:case 6:return x;case 7:case 8:return w-1-x;default:return y;}}
    private static final class Raster implements SpatialPreviewFilter.Pixels{
        final int w,h;final int[] data;Raster(int w,int h){this.w=w;this.h=h;data=new int[w*h];}Raster copy(){Raster r=new Raster(w,h);System.arraycopy(data,0,r.data,0,data.length);return r;}int at(int x,int y){return data[y*w+x];}public int width(){return w;}public int height(){return h;}public void read(int[] p,int row,int rows)throws IOException{System.arraycopy(data,row*w,p,0,rows*w);}public void write(int[] p,int row,int rows)throws IOException{System.arraycopy(p,0,data,row*w,rows*w);}
    }
    private static void exact(int[] a,int[] b,String name){checks++;if(!Arrays.equals(a,b)){int i=0;while(i<a.length&&a[i]==b[i])i++;throw new AssertionError(name+" at "+i+" expected="+Integer.toHexString(a[i])+" actual="+Integer.toHexString(b[i]));}}
    private static void near(double a,double b,double e,String name){checks++;if(!Double.isFinite(a)||Math.abs(a-b)>e)throw new AssertionError(name+" "+a+" != "+b);}
    private static void check(boolean ok,String name){checks++;if(!ok)throw new AssertionError(name);}
}
