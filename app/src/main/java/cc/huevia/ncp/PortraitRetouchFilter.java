package cc.huevia.ncp;
import java.io.*;
import java.util.*;
import java.util.function.*;
import static cc.huevia.ncp.PortraitRetouch.Parameter.*;

/** Masked chroma correction and landmark-local refinements, with original-neighbour row storage. */
public final class PortraitRetouchFilter {
    private PortraitRetouchFilter(){}
    private static final int[] LEFT={33,7,163,144,145,153,154,155,133,173,157,158,159,160,161,246},RIGHT={263,249,390,373,374,380,381,382,362,398,384,385,386,387,388,466};
    private static final int[] MOUTH={78,95,88,178,87,14,317,402,318,324,308,415,310,311,312,13,82,81,80,191};
    public static void apply(SpatialPreviewFilter.Pixels pixels,PhotoPortrait portrait,int exif,BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        int w=pixels.width(),h=pixels.height(),ow=exif>=5?h:w,oh=exif>=5?w:h;
        java.util.IdentityHashMap<PhotoPortrait.Face,double[]> references=new java.util.IdentityHashMap<>();for(PhotoPortrait.Face f:portrait.faces())references.put(f,new double[]{f.skinR,f.skinG,f.skinB,luma(f.skinR,f.skinG,f.skinB)});
        ArrayList<Face> faces=new ArrayList<>();int natural=portrait.retouch.get(NATURAL);
        for(PhotoPortrait.Face f:portrait.faces())if(f.enabled&&(f.retouch.hasFaceEffect()||natural>0))faces.add(new Face(f,ow,oh,natural));
        boolean skin=portrait.retouch.hasSkinEffect()&&portrait.globalSkinMask!=null;if(!skin&&faces.isEmpty()){if(progress!=null)progress.accept(1);return;}
        double[] reference=skin?reference(pixels,portrait.globalSkinMask,exif,cancel):null;
        double[][] referenceCells=new double[64*64][];for(int cy=0;cy<64;cy++)for(int cx=0;cx<64;cx++){double[] selected=reference;double nearest=Double.POSITIVE_INFINITY;for(PhotoPortrait.Face known:portrait.faces()){double d=Math.hypot(((cx+.5)/64-known.cx)/Math.max(.02,known.rx),((cy+.5)/64-known.cy)/Math.max(.02,known.ry));if(known.enabled&&d<nearest){nearest=d;selected=references.get(known);}}referenceCells[cy*64+cx]=selected;}
        int slots=Math.min(3,h),loaded=-1;int[][] rows=new int[slots][w];int[] out=new int[w];
        for(int y=0;y<h;y++){
            check(cancel);while(loaded<Math.min(h-1,y+1)){loaded++;pixels.read(rows[loaded%slots],loaded,1);}int[] original=rows[y%slots];System.arraycopy(original,0,out,0,w);
            for(int x=0;x<w;x++){
                if((x&127)==0)check(cancel);int argb=original[x];if((argb>>>24)==0)continue;double nx=LocalEditsPreviewProfile.orientedX((x+.5)/w,(y+.5)/h,exif),ny=LocalEditsPreviewProfile.orientedY((x+.5)/w,(y+.5)/h,exif);
                double r=(argb>>>16)&255,g=(argb>>>8)&255,b=argb&255;
                if(skin){double cover=portrait.globalSkinMask.weight(nx,ny);if(cover>0){double[] skinReference=referenceCells[Math.min(63,(int)(ny*64))*64+Math.min(63,(int)(nx*64))];double lum=luma(r,g,b),even=portrait.retouch.effective(EVENNESS)/100.0*cover*.55,ratio=lum/Math.max(12,skinReference[3]);r+=(skinReference[0]*ratio-r)*even;g+=(skinReference[1]*ratio-g)*even;b+=(skinReference[2]*ratio-b)*even;
                    double high=smooth(skinReference[3]+18,Math.min(254,skinReference[3]+85),lum),chroma=Math.max(r,Math.max(g,b))-Math.min(r,Math.min(g,b)),shine=portrait.retouch.effective(SHINE)/100.0*cover*high*(1-smooth(35,90,chroma));double lower=Math.min(38,Math.max(0,lum-skinReference[3])*.4)*shine;r-=lower;g-=lower;b-=lower;}}
                for(Face face:faces){if(!face.near(nx,ny))continue;double u=face.u(nx,ny),v=face.v(nx,ny),px=u*.95,py=v*1.35;double cover=face.skin.weight(argb,nx,ny);PortraitRetouch p=face.settings;
                    if(cover>0){double under=Math.max(face.left.under(px,py),face.right.under(px,py))*cover*p.effective(UNDER_EYE)/100.0;
                        double lum=luma(r,g,b),shadow=smooth(0,55,Math.max(0,face.reference-lum));double lift=under*shadow*16;r+=lift;g+=lift;b+=lift;double blueCast=Math.max(0,(b-g)-(face.source.skinB-face.source.skinG)),purple=Math.max(0,(r-g)-(face.source.skinR-face.source.skinG));g+=under*Math.min(10,(blueCast+purple)*.25);b-=under*Math.min(8,blueCast*.3);
                        double lx=p.get(LIGHT_X)/100.0,ly=p.get(LIGHT_Y)/100.0,norm=Math.sqrt(1+lx*lx+ly*ly),nz=Math.sqrt(Math.max(.08,1-.36*u*u-.36*v*v)),dot=(u*.6*lx+v*.6*ly+nz)/norm;
                        double exposure=p.effective(FILL)/100.0*cover*.48*(.35+.65*Math.max(0,dot));double gain=Math.pow(2,exposure);r=lift(r,gain);g=lift(g,gain);b=lift(b,gain);}
                    double authored=face.skin.authoredFeatureCoverage(nx,ny);
                    double eye=Math.max(face.left.weight(px,py),face.right.weight(px,py))*authored;
                    if(eye>0){double detail=p.get(EYE_DETAIL)/100.0*eye*.65;if(detail>0){double ar=0,ag=0,ab=0,total=0;for(int dy=-1;dy<=1;dy++){int[] row=rows[Math.max(0,Math.min(h-1,y+dy))%slots];for(int dx=-1;dx<=1;dx++){int q=row[Math.max(0,Math.min(w-1,x+dx))];if((q>>>24)==0)continue;ar+=(q>>>16)&255;ag+=(q>>>8)&255;ab+=q&255;total++;}}if(total>0){r+=clamp(r-ar/total,-18,18)*detail;g+=clamp(g-ag/total,-18,18)*detail;b+=clamp(b-ab/total,-18,18)*detail;}}
                        double lum=luma(r,g,b),chroma=Math.max(r,Math.max(g,b))-Math.min(r,Math.min(g,b)),white=eye*p.get(EYE_WHITE)/100.0*smooth(85,155,lum)*(1-smooth(25,75,chroma))*.6;r+=(lum-r)*white;g+=(lum-g)*white;b+=(lum-b)*white;double lift=white*6;r+=lift;g+=lift;b+=lift;}
                    double teeth=face.mouth.weight(px,py)*authored*p.get(TEETH)/100.0*smooth(90,165,luma(r,g,b))*(1-smooth(22,52,Math.max(0,r-g)));if(teeth>0){double lum=luma(r,g,b);r+=(lum-r)*teeth*.6;g+=(lum-g)*teeth*.6;b+=(Math.max(lum,g)-b)*teeth*.7;r+=teeth*8;g+=teeth*8;b+=teeth*8;}
                }
                out[x]=(argb&0xff000000)|(channel(r)<<16)|(channel(g)<<8)|channel(b);
            }
            check(cancel);pixels.write(out,y,1);if(progress!=null)progress.accept((y+1.0)/h);
        }
    }
    private static double[] reference(SpatialPreviewFilter.Pixels p,PhotoPortrait.BodySkinMask mask,int exif,BooleanSupplier cancel)throws IOException{
        int w=p.width(),h=p.height();int[] row=new int[w];long[] hist=new long[256];double[] sums=new double[4];
        for(int y=0;y<h;y+=Math.max(1,h/96)){check(cancel);p.read(row,y,1);for(int x=0;x<w;x+=Math.max(1,w/96)){int v=row[x];double nx=LocalEditsPreviewProfile.orientedX((x+.5)/w,(y+.5)/h,exif),ny=LocalEditsPreviewProfile.orientedY((x+.5)/w,(y+.5)/h,exif);if((v>>>24)==0||mask.weight(nx,ny)<.7)continue;double r=(v>>>16)&255,g=(v>>>8)&255,b=v&255;int lum=channel(luma(r,g,b));hist[lum]++;sums[0]+=r;sums[1]+=g;sums[2]+=b;sums[3]++;}}
        if(sums[3]==0)return new double[]{160,130,110,135};double n=sums[3],count=0;int median=128;for(int i=0;i<256;i++){count+=hist[i];if(count>=n*.5){median=i;break;}}return new double[]{sums[0]/n,sums[1]/n,sums[2]/n,median};
    }
    private static final class Face{
        final PhotoPortrait.Face source;final PortraitRetouch settings;final PortraitPreviewFilter.Mask skin;final Shape left,right,mouth;final double cos,sin,rx,ry,reference;final int w,h;
        Face(PhotoPortrait.Face f,int w,int h,int natural){source=f;this.w=w;this.h=h;settings=f.retouch.with(NATURAL,Math.max(natural,f.retouch.get(NATURAL)));skin=PortraitPreviewFilter.mask(f,w,h);double angle=Math.toRadians(f.roll);cos=Math.cos(angle);sin=Math.sin(angle);rx=f.rx*w;ry=f.ry*h;reference=luma(f.skinR,f.skinG,f.skinB);left=new Shape(f.landmarks,LEFT);right=new Shape(f.landmarks,RIGHT);mouth=new Shape(f.landmarks,MOUTH);}
        boolean near(double x,double y){return Math.abs(x-source.cx)<source.rx*1.8+source.ry*1.8&&Math.abs(y-source.cy)<source.ry*1.8+source.rx*1.8;}
        double u(double x,double y){return(cos*(x-source.cx)*w+sin*(y-source.cy)*h)/rx;}double v(double x,double y){return(-sin*(x-source.cx)*w+cos*(y-source.cy)*h)/ry;}
    }
    private static final class Shape{
        final double[] x,y;double l=8,t=8,r=-8,b=-8;
        Shape(PhotoPortrait.Landmarks p,int[] indices){x=new double[p==null?0:indices.length];y=new double[x.length];for(int i=0;i<x.length;i++){x[i]=p.x(indices[i]);y[i]=p.y(indices[i]);l=Math.min(l,x[i]);r=Math.max(r,x[i]);t=Math.min(t,y[i]);b=Math.max(b,y[i]);}}
        double weight(double px,double py){if(x.length==0||r-l<.01||b-t<.006||px<l||px>r||py<t||py>b)return 0;boolean inside=false;double distance=10;for(int i=0,j=x.length-1;i<x.length;j=i++){if((y[i]>py)!=(y[j]>py)&&px<(x[j]-x[i])*(py-y[i])/(y[j]-y[i])+x[i])inside=!inside;double dx=x[i]-x[j],dy=y[i]-y[j],den=dx*dx+dy*dy,part=den==0?0:clamp(((px-x[j])*dx+(py-y[j])*dy)/den,0,1);distance=Math.min(distance,Math.hypot(px-x[j]-part*dx,py-y[j]-part*dy));}return inside?smooth(0,.025,distance):0;}
        double under(double px,double py){if(x.length==0||px<l-.05||px>r+.05||py<b||py>b+.24)return 0;double u=(px-(l+r)*.5)/Math.max(.01,(r-l)*.7),v=(py-b-.09)/.14;return 1-smooth(.35,1,Math.hypot(u,v));}
    }
    private static double lift(double v,double gain){return Math.min(255,v+(255-v)*(gain-1)*.55);}
    private static int channel(double v){return(int)Math.round(clamp(v,0,255));}private static double clamp(double v,double lo,double hi){return Math.max(lo,Math.min(hi,v));}
    private static double luma(double r,double g,double b){return .2126*r+.7152*g+.0722*b;}private static double smooth(double lo,double hi,double v){double x=clamp((v-lo)/Math.max(1e-9,hi-lo),0,1);return x*x*(3-2*x);}
    private static void check(BooleanSupplier cancel)throws InterruptedIOException{if(Thread.currentThread().isInterrupted()||cancel!=null&&cancel.getAsBoolean())throw new InterruptedIOException("人像精修已取消。");}
}
