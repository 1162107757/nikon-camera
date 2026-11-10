package cc.huevia.ncp;

import java.io.*;
import java.util.*;
import java.util.function.*;

/** Feathered, boundary-colour-matched sampling. No generated or inferred content. */
public final class PhotoPatchRenderer {
    private PhotoPatchRenderer(){}
    private static final double[] LINEAR=new double[256];
    static{for(int i=0;i<256;i++){double v=i/255.0;LINEAR[i]=v<=.04045?v/12.92:Math.pow((v+.055)/1.055,2.4);}}

    public static void apply(SpatialPreviewFilter.Pixels pixels,List<PhotoPatch> patches,int exif,BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        if(pixels==null||patches==null||exif<1||exif>8||pixels.width()<1||pixels.height()<1||pixels.width()>65535||pixels.height()>65535)
            throw new IllegalArgumentException("修补照片无效。");
        for(int i=0;i<patches.size();i++){
            check(cancel);PhotoPatch patch=Objects.requireNonNull(patches.get(i));
            final int index=i;if(patch.hasEffect())apply(pixels,patch,exif,cancel,progress==null?null:v->progress.accept((index+v)/patches.size()));
            if(progress!=null)progress.accept((i+1.0)/patches.size());
        }
        if(progress!=null)progress.accept(1);
    }

    private static void apply(SpatialPreviewFilter.Pixels pixels,PhotoPatch patch,int exif,BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        int w=pixels.width(),h=pixels.height(),ow=exif>=5?h:w,oh=exif>=5?w:h;
        AdjustmentRegion.Brush mask=patch.selection.compileBrush(ow,oh);if(mask.right<=mask.left||mask.bottom<=mask.top)return;
        int[] bounds=bounds(mask,w,h,exif);
        // A per-patch immutable snapshot makes overlapping samples deterministic and repairs ordered.
        // The shared private-directory snapshot is disk-backed; no full-size int[] is allocated.
        try(AdjustmentRegionRenderer.Scratch snapshot=AdjustmentRegionRenderer.Scratch.copyOf(pixels,exif,cancel,progress==null?null:v->progress.accept(v*.3))){
            Rows source=new Rows(snapshot,w,h,cancel);
            ContextMatch context=patch.contextBlend&&patch.blend>0?context(source,mask,patch,w,h,ow,oh,exif,bounds,cancel):null;
            double[] correction=patch.blend==0||patch.contextBlend?new double[3]:correction(source,mask,patch,w,h,ow,oh,exif,bounds,cancel);
            int[] row=new int[w];
            for(int y=bounds[1];y<=bounds[3];y++){
                check(cancel);pixels.read(row,y,1);
                for(int x=bounds[0];x<=bounds[2];x++){
                    if((x&255)==0)check(cancel);
                    int target=row[x];if((target>>>24)==0)continue;
                    int ox=orientedX(x,y,w,h,exif),oy=orientedY(x,y,w,h,exif);
                    double amount=mask.weight((ox+.5)/ow,(oy+.5)/oh);if(amount<=0)continue;
                    int value=sample(source,ox,oy,patch,ow,oh,w,h,exif);if((value>>>24)==0)continue;
                    amount*=((value>>>24)&255)/255.0;
                    int result=target&0xff000000;
                    for(int c=0;c<3;c++){
                        int shift=16-8*c;double t=LINEAR[(target>>>shift)&255];
                        double delta=context==null?correction[c]:context.at((ox+.5)/ow,(oy+.5)/oh,c);
                        double s=Math.max(0,Math.min(1,LINEAR[(value>>>shift)&255]+delta*patch.blend));
                        result|=encode(t+(s-t)*amount)<<shift;
                    }
                    row[x]=result;
                }
                pixels.write(row,y,1);if(progress!=null)progress.accept(.3+.7*(y-bounds[1]+1.0)/(bounds[3]-bounds[1]+1));
            }
        }
    }

    /** Fit only clean exterior context: marked blemish pixels must not tint their own repair. */
    private static ContextMatch context(Rows source,AdjustmentRegion.Brush mask,PhotoPatch patch,int w,int h,int ow,int oh,int exif,int[] bounds,BooleanSupplier cancel)throws IOException{
        int halo=Math.max(2,Math.min(24,(int)Math.round(Math.min(bounds[2]-bounds[0]+1,bounds[3]-bounds[1]+1)*.15)));
        int left=Math.max(0,bounds[0]-halo),right=Math.min(w-1,bounds[2]+halo),top=Math.max(0,bounds[1]-halo),bottom=Math.min(h-1,bounds[3]+halo);
        int sx=Math.max(1,(right-left+64)/64),sy=Math.max(1,(bottom-top+64)/64);
        double cx=(mask.left+mask.right)/2,cy=(mask.top+mask.bottom)/2,rx=Math.max(1.0/ow,(mask.right-mask.left)/2),ry=Math.max(1.0/oh,(mask.bottom-mask.top)/2);
        double nearX=(halo+1.0)/ow,nearY=(halo+1.0)/oh;
        ArrayList<double[]> points=new ArrayList<>();
        for(int y=top;y<=bottom;y+=sy){check(cancel);for(int x=left;x<=right;x+=sx){
            int ox=orientedX(x,y,w,h,exif),oy=orientedY(x,y,w,h,exif);double nx=(ox+.5)/ow,ny=(oy+.5)/oh;
            if(mask.weight(nx,ny)>.001)continue;
            if(mask.weight(nx-nearX,ny)<.01&&mask.weight(nx+nearX,ny)<.01&&mask.weight(nx,ny-nearY)<.01&&mask.weight(nx,ny+nearY)<.01
                    &&mask.weight(nx-nearX,ny-nearY)<.01&&mask.weight(nx+nearX,ny-nearY)<.01&&mask.weight(nx-nearX,ny+nearY)<.01&&mask.weight(nx+nearX,ny+nearY)<.01)continue;
            int target=source.get(x,y),donor=sample(source,ox,oy,patch,ow,oh,w,h,exif);
            int alpha=Math.min(target>>>24,donor>>>24);if(alpha<128)continue;
            points.add(new double[]{1,(nx-cx)/rx,(ny-cy)/ry,LINEAR[(target>>>16)&255]-LINEAR[(donor>>>16)&255],LINEAR[(target>>>8)&255]-LINEAR[(donor>>>8)&255],LINEAR[target&255]-LINEAR[donor&255],alpha/255.0});
        }}
        double[][] coefficients=fit(points,null);
        if(points.size()>=8){
            double[] errors=new double[points.size()];for(int i=0;i<errors.length;i++){double[] p=points.get(i);double e=0;for(int c=0;c<3;c++){double d=p[3+c]-dot(coefficients[c],p);e+=d*d;}errors[i]=Math.sqrt(e/3);}
            double[] sorted=errors.clone();Arrays.sort(sorted);double cutoff=Math.max(.015,sorted[sorted.length/2]*2.5);
            double[] robust=new double[errors.length];for(int i=0;i<robust.length;i++)robust[i]=errors[i]<=cutoff?1:cutoff/errors[i];coefficients=fit(points,robust);
        }
        return new ContextMatch(cx,cy,rx,ry,coefficients);
    }
    private static double dot(double[] a,double[] b){return a[0]*b[0]+a[1]*b[1]+a[2]*b[2];}
    private static double[][] fit(List<double[]> points,double[] robust){
        double[][] result=new double[3][3];if(points.isEmpty())return result;
        double[][] normal=new double[3][3],rhs=new double[3][3];double total=0;
        for(int n=0;n<points.size();n++){double[] p=points.get(n);double weight=p[6]*(robust==null?1:robust[n]);total+=weight;for(int i=0;i<3;i++){for(int j=0;j<3;j++)normal[i][j]+=weight*p[i]*p[j];for(int c=0;c<3;c++)rhs[c][i]+=weight*p[i]*p[3+c];}}
        normal[0][0]+=1e-8;normal[1][1]+=total*.002+1e-8;normal[2][2]+=total*.002+1e-8;
        for(int c=0;c<3;c++){
            double[][] a=new double[3][4];for(int i=0;i<3;i++){System.arraycopy(normal[i],0,a[i],0,3);a[i][3]=rhs[c][i];}
            for(int i=0;i<3;i++){int pivot=i;for(int j=i+1;j<3;j++)if(Math.abs(a[j][i])>Math.abs(a[pivot][i]))pivot=j;double[] swap=a[i];a[i]=a[pivot];a[pivot]=swap;double d=a[i][i];if(Math.abs(d)<1e-10)continue;for(int k=i;k<4;k++)a[i][k]/=d;for(int j=0;j<3;j++)if(j!=i){double factor=a[j][i];for(int k=i;k<4;k++)a[j][k]-=factor*a[i][k];}}
            for(int i=0;i<3;i++)result[c][i]=Double.isFinite(a[i][3])?a[i][3]:0;
        }return result;
    }
    private static final class ContextMatch{
        final double cx,cy,rx,ry;final double[][] coefficients;
        ContextMatch(double cx,double cy,double rx,double ry,double[][] coefficients){this.cx=cx;this.cy=cy;this.rx=rx;this.ry=ry;this.coefficients=coefficients;}
        double at(double x,double y,int c){double[] a=coefficients[c];return Math.max(-.3,Math.min(.3,a[0]+a[1]*(x-cx)/rx+a[2]*(y-cy)/ry));}
    }

    private static double[] correction(Rows source,AdjustmentRegion.Brush mask,PhotoPatch patch,int w,int h,int ow,int oh,int exif,int[] bounds,BooleanSupplier cancel)throws IOException{
        double[] sum=new double[3];double samples=0;
        int stepX=Math.max(1,(bounds[2]-bounds[0]+1)/64),stepY=Math.max(1,(bounds[3]-bounds[1]+1)/64);
        double rx=Math.max(2.0/ow,(mask.right-mask.left)/64),ry=Math.max(2.0/oh,(mask.bottom-mask.top)/64);
        for(int y=bounds[1];y<=bounds[3];y+=stepY){check(cancel);for(int x=bounds[0];x<=bounds[2];x+=stepX){
            int ox=orientedX(x,y,w,h,exif),oy=orientedY(x,y,w,h,exif);double nx=(ox+.5)/ow,ny=(oy+.5)/oh,a=mask.weight(nx,ny);
            if(a<=.01)continue;
            boolean edge=a<.65||mask.weight(nx-rx,ny)<.01||mask.weight(nx+rx,ny)<.01||mask.weight(nx,ny-ry)<.01||mask.weight(nx,ny+ry)<.01;
            if(!edge)continue;
            int target=source.get(x,y),sample=sample(source,ox,oy,patch,ow,oh,w,h,exif);
            if((target>>>24)==0||(sample>>>24)==0)continue;
            double weight=Math.min((target>>>24)&255,(sample>>>24)&255)/255.0;
            for(int c=0;c<3;c++){int shift=16-8*c;sum[c]+=(LINEAR[(target>>>shift)&255]-LINEAR[(sample>>>shift)&255])*weight;}
            samples+=weight;
        }}
        if(samples>0)for(int c=0;c<3;c++)sum[c]=Math.max(-.3,Math.min(.3,sum[c]/samples));
        return sum;
    }

    private static int sample(Rows source,int ox,int oy,PhotoPatch patch,int ow,int oh,int w,int h,int exif)throws IOException{
        double x=ox+patch.dx*ow,y=oy+patch.dy*oh;
        if(x<-.5||y<-.5||x>ow-.5||y>oh-.5)return 0;
        if(patch.contextBlend){
            x=Math.max(0,Math.min(ow-1,x));y=Math.max(0,Math.min(oh-1,y));int x0=(int)Math.floor(x),y0=(int)Math.floor(y),x1=Math.min(ow-1,x0+1),y1=Math.min(oh-1,y0+1);
            double tx=x-x0,ty=y-y0,alpha=0,red=0,green=0,blue=0;
            for(int yy=0;yy<2;yy++)for(int xx=0;xx<2;xx++){int px=xx==0?x0:x1,py=yy==0?y0:y1;double weight=(xx==0?1-tx:tx)*(yy==0?1-ty:ty);if(weight==0)continue;int p=source.get(rawX(px,py,w,h,exif),rawY(px,py,w,h,exif));weight*=(p>>>24)/255.0;alpha+=weight;red+=LINEAR[(p>>>16)&255]*weight;green+=LINEAR[(p>>>8)&255]*weight;blue+=LINEAR[p&255]*weight;}
            if(alpha<=0)return 0;return ((int)Math.round(alpha*255))<<24|encode(red/alpha)<<16|encode(green/alpha)<<8|encode(blue/alpha);
        }
        int ix=Math.max(0,Math.min(ow-1,(int)Math.round(x))),iy=Math.max(0,Math.min(oh-1,(int)Math.round(y)));
        return source.get(rawX(ix,iy,w,h,exif),rawY(ix,iy,w,h,exif));
    }
    private static int[] bounds(AdjustmentRegion.Brush mask,int w,int h,int exif){
        double minX=1,minY=1,maxX=0,maxY=0;
        for(double x:new double[]{mask.left,mask.right})for(double y:new double[]{mask.top,mask.bottom}){
            double rx=LocalEditsPreviewProfile.rawX(x,y,exif),ry=LocalEditsPreviewProfile.rawY(x,y,exif);minX=Math.min(minX,rx);minY=Math.min(minY,ry);maxX=Math.max(maxX,rx);maxY=Math.max(maxY,ry);
        }
        return new int[]{Math.max(0,(int)Math.floor(minX*w-.5)),Math.max(0,(int)Math.floor(minY*h-.5)),Math.min(w-1,(int)Math.ceil(maxX*w-.5)),Math.min(h-1,(int)Math.ceil(maxY*h-.5))};
    }
    private static final class Rows{
        final SpatialPreviewFilter.Pixels pixels;final int[][] rows;final int[] keys;final int w;final BooleanSupplier cancel;
        Rows(SpatialPreviewFilter.Pixels p,int w,int h,BooleanSupplier c){pixels=p;this.w=w;cancel=c;int n=Math.max(2,Math.min(h,(int)Math.max(2,2_097_152L/(4*w))));rows=new int[n][];keys=new int[n];Arrays.fill(keys,-1);}
        int get(int x,int y)throws IOException{int slot=y%rows.length;if(keys[slot]!=y){check(cancel);if(rows[slot]==null)rows[slot]=new int[w];pixels.read(rows[slot],y,1);keys[slot]=y;}return rows[slot][x];}
    }
    private static int orientedX(int x,int y,int w,int h,int e){switch(e){case 2:case 3:return w-1-x;case 5:case 8:return y;case 6:case 7:return h-1-y;default:return x;}}
    private static int orientedY(int x,int y,int w,int h,int e){switch(e){case 3:case 4:return h-1-y;case 5:case 6:return x;case 7:case 8:return w-1-x;default:return y;}}
    private static int rawX(int x,int y,int w,int h,int e){switch(e){case 2:case 3:return w-1-x;case 5:case 6:return y;case 7:case 8:return w-1-y;default:return x;}}
    private static int rawY(int x,int y,int w,int h,int e){switch(e){case 3:case 4:return h-1-y;case 5:case 8:return x;case 6:case 7:return h-1-x;default:return y;}}
    private static int encode(double value){double v=Math.max(0,Math.min(1,value));return (int)Math.round(255*(v<=.0031308?12.92*v:1.055*Math.pow(v,1/2.4)-.055));}
    private static void check(BooleanSupplier c)throws InterruptedIOException{if(Thread.currentThread().isInterrupted()||c!=null&&c.getAsBoolean())throw new InterruptedIOException("修补已取消。");}
}
