package cc.huevia.ncp;

import java.io.IOException;
import java.util.*;

/** Independent synthetic geometry/pixel oracles, not a photographic segmentation benchmark. */
public final class PortraitLandmarkMaskTest {
    private static final int SKIN=0xffb48269;
    private static final PhotoPortrait.Settings BRIGHT=new PhotoPortrait.Settings(30,0,0,0,70,0,0);
    private static final int[] OVAL={10,338,297,332,284,251,389,356,454,323,361,288,397,365,379,378,400,377,152,148,176,149,150,136,172,58,132,93,234,127,162,21,54,103,67,109};
    private static final int[] LE={33,7,163,144,145,153,154,155,133,173,157,158,159,160,161,246},RE={263,249,390,373,374,380,381,382,362,398,384,385,386,387,388,466};
    private static final int[] LB={46,53,52,65,55,107,66,105,63,70},RB={276,283,282,295,285,336,296,334,293,300};
    private static final int[] LIPS={61,146,91,181,84,17,314,405,321,375,291,409,270,269,267,0,37,39,40,185};
    private static int checks;
    public static void main(String[] args)throws Exception{
        PhotoPortrait.Face face=face(0);
        coverageAndFeatures(face);
        strokes(face);
        coordinateFrames(face);
        renderConsistency(face,401,277);
        renderConsistency(face.withBounds(.14,.25,.24,.27,-33),257,173);
        orientation(face.withBounds(.5,.52,.18,.24,29));
        eyeShadowFollowsMesh(face.withBounds(.5,.52,.18,.24,31));
        legacyNull(face);
        System.out.println("PASS PortraitLandmarkMaskTest "+checks+" checks");
    }
    private static void coverageAndFeatures(PhotoPortrait.Face face){
        int w=384,h=256;
        check(weight(face,0,-1.30,w,h)>.95,"visible forehead above old ellipse is fully usable");
        check(weight(face,-1.15,-.15,w,h)>.95&&weight(face,1.15,-.15,w,h)>.95,"both cheeks beyond old ellipse are usable");
        check(weight(face,1.60,-.1,w,h)==0&&weight(face,0,-1.85,w,h)==0&&weight(face,0,1.45,w,h)==0,"same-colour background outside actual outline is excluded");
        for(double[] p:new double[][]{{-.58,-.06},{.60,-.08},{-.55,-.27},{.58,-.30},{0,.78}})
            check(weight(face,p[0],p[1],w,h)==0,"actual eye/brow/lip centre is protected");
        check(weight(face,-.526,-.407,w,h)>.9,"old eye location no longer creates a false hole");
        check(weight(face,0,.55,w,h)>.9,"old mouth location no longer creates a false hole");
        double[] forehead=world(face,0,-1.30,w,h),outside=world(face,1.60,-.1,w,h),eye=world(face,-.58,-.06,w,h);
        check(PortraitPreviewFilter.faceContains(face,forehead[0],forehead[1],w,h),"expanded forehead can select the face");
        check(!PortraitPreviewFilter.faceContains(face,outside[0],outside[1],w,h),"outline hit test excludes background");
        check(PortraitPreviewFilter.faceContains(face,eye[0],eye[1],w,h),"protected facial feature remains selectable");
        PhotoPortrait.Face disabled=face.withEnabled(false);
        check(weight(disabled,0,-1.30,w,h)==0&&PortraitPreviewFilter.faceContains(disabled,forehead[0],forehead[1],w,h),"disabled face cannot affect pixels but remains selectable");
        check(PortraitPreviewFilter.mask(face,w,h).weight(SKIN&0xffffff,forehead[0],forehead[1])==0,"transparent pixels remain protected");
        check(!PortraitPreviewFilter.faceContains(face,Double.NaN,.5,w,h)&&!PortraitPreviewFilter.faceContains(face,.5,.5,0,h),"invalid hit-test input is rejected");
        PhotoPortrait.Face narrow=face.withLandmarks(mesh(.8));
        check(weight(face,1.05,-.15,w,h)>.95&&weight(narrow,1.05,-.15,w,h)==0,"distinct immutable meshes do not reuse another face's cached coverage");
    }
    private static void strokes(PhotoPortrait.Face face){
        int w=384,h=256;double[] outside=world(face,1.60,-.1,w,h),forehead=world(face,0,-1.30,w,h),eye=world(face,-.58,-.06,w,h);
        PhotoPortrait.Face added=face.addStroke(stroke(outside,false));
        check(PortraitPreviewFilter.mask(added,w,h).weight(SKIN,outside[0],outside[1])==1,"manual add can extend beyond detected boundary");
        check(PortraitPreviewFilter.mask(added,w,h).weight(0xff20d020,outside[0],outside[1])==1,"explicit add overrides automatic skin colour acceptance");
        PhotoPortrait.Face erased=face.addStroke(stroke(forehead,true));
        check(PortraitPreviewFilter.mask(erased,w,h).weight(SKIN,forehead[0],forehead[1])==0,"manual erase removes expanded forehead coverage");
        check(PortraitPreviewFilter.mask(erased.addStroke(stroke(forehead,false)),w,h).weight(SKIN,forehead[0],forehead[1])==1,"later add restores erased coverage");
        check(PortraitPreviewFilter.mask(face.addStroke(stroke(eye,false)),w,h).weight(SKIN,eye[0],eye[1])==1,"explicit painting follows automatic feature protection");
    }
    private static void coordinateFrames(PhotoPortrait.Face face){
        double[][] points={{0,-1.30},{-1.15,-.15},{1.15,-.15},{-.58,-.06},{0,.78},{0,.55},{1.60,-.1}};
        for(int[] size:new int[][]{{384,256},{480,287},{287,480}})for(int roll:new int[]{0,31,-47}){
            PhotoPortrait.Face transformed=face.withBounds(.5,.52,.18,.24,roll);
            for(double[] p:points){
                double expected=weight(face,p[0],p[1],384,256),actual=weight(transformed,p[0],p[1],size[0],size[1]);
                near(expected,actual,1e-10,"non-square frame and roll preserve local semantic coverage");
            }
            double[] forehead=world(transformed,0,-1.30,size[0],size[1]);
            check(PortraitPreviewFilter.faceContains(transformed,forehead[0],forehead[1],size[0],size[1]),"rotated non-square forehead remains selectable");
        }
    }
    private static void renderConsistency(PhotoPortrait.Face face,int w,int h)throws Exception{
        Raster source=image(w,h),actual=source.copy();
        PortraitPreviewFilter.Mask mask=PortraitPreviewFilter.mask(face,w,h);
        int[] expected=source.data.clone();int expanded=0,protectedCount=0;
        for(int y=0;y<h;y++)for(int x=0;x<w;x++){
            double nx=(x+.5)/w,ny=(y+.5)/h,amount=mask.weight(source.at(x,y),nx,ny);
            expected[y*w+x]=lift(source.at(x,y),amount);
            double[] local=local(face,nx,ny,w,h);
            if(Math.hypot(local[0],local[1])>1&&amount>.5&&expected[y*w+x]!=source.at(x,y))expanded++;
            if(amount==0)protectedCount++;
        }
        PortraitPreviewFilter.apply(actual,new PhotoPortrait(List.of(face),List.of()),()->false,null);
        exact(expected,actual.data,"full renderer agrees with the complete mask, including expanded bounds");
        check(expanded>100&&protectedCount>w*h/2,"oracle exercises new pixels outside old bounds and excludes background");
        double[] outside=world(face,1.60,-.1,w,h);
        if(outside[0]>.05&&outside[0]<.95&&outside[1]>.05&&outside[1]<.95){
            PhotoPortrait.Face extended=face.addStroke(stroke(outside,false));Raster painted=source.copy();PortraitPreviewFilter.Mask added=PortraitPreviewFilter.mask(extended,w,h);
            for(int y=0;y<h;y++)for(int x=0;x<w;x++)expected[y*w+x]=lift(source.at(x,y),added.weight(source.at(x,y),(x+.5)/w,(y+.5)/h));
            PortraitPreviewFilter.apply(painted,new PhotoPortrait(List.of(extended),List.of()),()->false,null);
            exact(expected,painted.data,"manual add also extends the full-render bounds");
        }
    }
    private static void orientation(PhotoPortrait.Face face)throws Exception{
        Raster canonical=image(211,149),expected=canonical.copy();PortraitPreviewFilter.apply(expected,new PhotoPortrait(List.of(face),List.of()),()->false,null);
        for(int exif=1;exif<=8;exif++){
            Raster raw=rawFromOriented(canonical,exif);PortraitPreviewFilter.apply(raw,new PhotoPortrait(List.of(face),List.of()),exif,()->false,null);
            exact(expected.data,oriented(raw,exif).data,"mesh follows independent integer EXIF mapping "+exif);
        }
    }
    private static void legacyNull(PhotoPortrait.Face face)throws Exception{
        PhotoPortrait.Face legacy=face.withLandmarks(null);int w=384,h=256;
        check(weight(legacy,0,-1.3,w,h)==0&&weight(legacy,1.15,-.15,w,h)==0,"null mesh keeps authored legacy ellipse bounds");
        check(weight(legacy,-.526,-.407,w,h)==0&&weight(legacy,0,.55,w,h)==0,"null mesh retains legacy feature protection");
        check(weight(legacy,.3,0,w,h)>.95,"null mesh retains legacy mid-face skin coverage");
        PhotoPortrait.Face oldConstructor=new PhotoPortrait.Face(legacy.cx,legacy.cy,legacy.rx,legacy.ry,legacy.roll,legacy.skinR,legacy.skinG,legacy.skinB,legacy.enabled,legacy.settings,legacy.strokes);
        Raster a=image(211,149),b=a.copy();PortraitPreviewFilter.apply(a,new PhotoPortrait(List.of(legacy),List.of()),()->false,null);PortraitPreviewFilter.apply(b,new PhotoPortrait(List.of(oldConstructor),List.of()),()->false,null);
        exact(a.data,b.data,"explicitly absent mesh and old constructor preserve identical legacy pixels");
    }
    private static void eyeShadowFollowsMesh(PhotoPortrait.Face face)throws Exception{
        int w=384,h=256;Raster image=new Raster(w,h);Arrays.fill(image.data,SKIN);
        PhotoPortrait.Face shadows=face.withSettings(new PhotoPortrait.Settings(0,0,0,0,70,0,80));
        PortraitPreviewFilter.apply(image,new PhotoPortrait(List.of(shadows),List.of()),()->false,null);
        check(colourDistance(SKIN,atLocal(image,face,-.58,.15))>3,"eye-shadow lift follows the actual relocated eye contour");
        check(atLocal(image,face,-.526,-.19)==SKIN,"old fixed under-eye location no longer receives a misplaced lift");
        check(atLocal(image,face,-.58,-.06)==SKIN,"actual eye remains protected during under-eye correction");
    }
    private static int atLocal(Raster image,PhotoPortrait.Face face,double u,double v){double[] p=world(face,u,v,image.w,image.h);return image.at(Math.max(0,Math.min(image.w-1,(int)(p[0]*image.w))),Math.max(0,Math.min(image.h-1,(int)(p[1]*image.h))));}
    private static int colourDistance(int a,int b){int sum=0;for(int shift:new int[]{0,8,16})sum+=Math.abs(((a>>>shift)&255)-((b>>>shift)&255));return sum;}
    static PhotoPortrait.Landmarks mesh(double horizontalRadius){
        double[] p=new double[936];ellipse(p,OVAL,0,-.2,horizontalRadius,1.4);
        ellipse(p,LE,-.58,-.06,.24,.08);ellipse(p,RE,.60,-.08,.24,.08);
        ellipse(p,LB,-.55,-.27,.28,.055);ellipse(p,RB,.58,-.30,.28,.055);ellipse(p,LIPS,0,.78,.30,.08);
        p[98*2]=-.12;p[98*2+1]=.4;p[327*2]=.12;p[327*2+1]=.4;
        return new PhotoPortrait.Landmarks(p);
    }
    private static void ellipse(double[] points,int[] indices,double x,double y,double rx,double ry){for(int i=0;i<indices.length;i++){double a=-Math.PI/2+i*Math.PI*2/indices.length;points[indices[i]*2]=x+rx*Math.cos(a);points[indices[i]*2+1]=y+ry*Math.sin(a);}}
    static PhotoPortrait.Face face(double roll){return new PhotoPortrait.Face(.5,.52,.18,.24,roll,180,130,105,true,BRIGHT,List.of(),mesh(1.4));}
    private static double weight(PhotoPortrait.Face face,double u,double v,int w,int h){double[] p=world(face,u,v,w,h);return PortraitPreviewFilter.mask(face,w,h).weight(SKIN,p[0],p[1]);}
    private static double[] world(PhotoPortrait.Face f,double u,double v,int w,int h){double a=Math.toRadians(f.roll),x=u*f.rx*w,y=v*f.ry*h;return new double[]{f.cx+(Math.cos(a)*x-Math.sin(a)*y)/w,f.cy+(Math.sin(a)*x+Math.cos(a)*y)/h};}
    private static double[] local(PhotoPortrait.Face f,double nx,double ny,int w,int h){double a=Math.toRadians(f.roll),x=(nx-f.cx)*w,y=(ny-f.cy)*h;return new double[]{(Math.cos(a)*x+Math.sin(a)*y)/(f.rx*w),(-Math.sin(a)*x+Math.cos(a)*y)/(f.ry*h)};}
    private static PhotoPortrait.Stroke stroke(double[] p,boolean erase){return new PhotoPortrait.Stroke(p,.025,.5,erase);}
    /** Analytic positive brightness and integer channel blending; deliberately no raster/polygon implementation. */
    private static int lift(int source,double amount){int result=source&0xff000000;for(int shift:new int[]{16,8,0}){int value=(source>>>shift)&255,target=(int)Math.round(value+(255-value)*.066);result|=(int)Math.round(value+(target-value)*amount)<<shift;}return result;}
    private static Raster image(int w,int h){Raster image=new Raster(w,h);for(int y=0;y<h;y++)for(int x=0;x<w;x++){int noise=(x*17+y*31+x*y)%5-2;image.data[y*w+x]=0xff000000|(180+noise)<<16|(130+noise)<<8|(105+noise);}return image;}
    private static Raster rawFromOriented(Raster canonical,int exif){Raster raw=new Raster(exif>=5?canonical.h:canonical.w,exif>=5?canonical.w:canonical.h);for(int y=0;y<raw.h;y++)for(int x=0;x<raw.w;x++)raw.data[y*raw.w+x]=canonical.data[oy(x,y,raw.w,raw.h,exif)*canonical.w+ox(x,y,raw.w,raw.h,exif)];return raw;}
    private static Raster oriented(Raster raw,int exif){Raster image=new Raster(exif>=5?raw.h:raw.w,exif>=5?raw.w:raw.h);for(int y=0;y<raw.h;y++)for(int x=0;x<raw.w;x++)image.data[oy(x,y,raw.w,raw.h,exif)*image.w+ox(x,y,raw.w,raw.h,exif)]=raw.data[y*raw.w+x];return image;}
    private static int ox(int x,int y,int w,int h,int e){switch(e){case 2:case 3:return w-1-x;case 5:case 8:return y;case 6:case 7:return h-1-y;default:return x;}}
    private static int oy(int x,int y,int w,int h,int e){switch(e){case 3:case 4:return h-1-y;case 5:case 6:return x;case 7:case 8:return w-1-x;default:return y;}}
    private static final class Raster implements SpatialPreviewFilter.Pixels{
        final int w,h;final int[] data;Raster(int w,int h){this.w=w;this.h=h;data=new int[w*h];}
        Raster copy(){Raster r=new Raster(w,h);System.arraycopy(data,0,r.data,0,data.length);return r;}
        int at(int x,int y){return data[y*w+x];}public int width(){return w;}public int height(){return h;}
        public void read(int[] pixels,int row,int rows)throws IOException{System.arraycopy(data,row*w,pixels,0,rows*w);}
        public void write(int[] pixels,int row,int rows)throws IOException{System.arraycopy(pixels,0,data,row*w,rows*w);}
    }
    private static void exact(int[] a,int[] b,String name){checks++;if(!Arrays.equals(a,b)){int i=0;while(i<a.length&&a[i]==b[i])i++;throw new AssertionError(name+" at "+i+" expected="+Integer.toHexString(a[i])+" actual="+Integer.toHexString(b[i]));}}
    private static void near(double a,double b,double tolerance,String name){checks++;if(Math.abs(a-b)>tolerance)throw new AssertionError(name+" "+a+" != "+b);}
    private static void check(boolean ok,String name){checks++;if(!ok)throw new AssertionError(name);}
}
