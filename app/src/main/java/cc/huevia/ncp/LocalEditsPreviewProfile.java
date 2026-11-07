package cc.huevia.ncp;

import java.io.IOException;
import java.io.InterruptedIOException;
import java.util.*;
import java.util.function.BooleanSupplier;
import java.util.function.DoubleConsumer;

/** Global colour -> local masks/clone patches -> frozen portrait skin, light and healing. */
public final class LocalEditsPreviewProfile implements PresetPreviewProfile {
    private static final int MAX_PATCH_PIXELS=8*1024*1024;
    private static final double[] LINEAR=new double[256];
    private static final int[] ENCODE=new int[65536];
    static {for(int i=0;i<256;i++){double v=i/255.0;LINEAR[i]=v<=.04045?v/12.92:Math.pow((v+.055)/1.055,2.4);}for(int i=0;i<ENCODE.length;i++){double v=i/(double)(ENCODE.length-1);ENCODE[i]=(int)Math.round(255*(v<=.0031308?v*12.92:1.055*Math.pow(v,1/2.4)-.055));}}
    public final PresetPreviewProfile colour;
    public final PhotoLocalEdits edits;
    public final int exifOrientation;
    private LocalEditsPreviewProfile(PresetPreviewProfile colour,PhotoLocalEdits edits,int exif){if(colour==null||edits==null||exif<0||exif>8)throw new IllegalArgumentException("局部编辑方向无效。");this.colour=colour;this.edits=edits;this.exifOrientation=exif;}
    /** The default inherits the storage orientation exposed by Pixels; oriented previews expose 1. */
    public static PresetPreviewProfile of(PresetPreviewProfile colour,PhotoLocalEdits edits){if(colour==null||edits==null)throw new IllegalArgumentException("局部编辑设置无效。");return edits.isNeutral()?colour:new LocalEditsPreviewProfile(colour,edits,0);}
    public static PresetPreviewProfile of(PresetPreviewProfile colour,PhotoLocalEdits edits,int exif){if(colour==null||edits==null||exif<1||exif>8)throw new IllegalArgumentException("局部编辑方向无效。");return edits.isNeutral()?colour:new LocalEditsPreviewProfile(colour,edits,exif);}
    public LocalEditsPreviewProfile withExifOrientation(int exif){if(exif<1||exif>8)throw new IllegalArgumentException("局部编辑方向无效。");return new LocalEditsPreviewProfile(colour,edits,exif);}
    public String registrationName(){return colour.registrationName();}
    public String modelVersion(){return colour.modelVersion()+":"+edits.identity();}
    public double mapTone(double value){return colour.mapTone(value);}
    /** A point-only caller cannot position local edits; image renderPixels is authoritative. */
    public int applyArgb(int argb){return colour.applyArgb(argb);}
    public SpatialPreviewFilter.Settings spatialSettings(){return colour.spatialSettings();}
    @Override public void renderPixels(SpatialPreviewFilter.Pixels pixels,BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        check(cancel);colour.renderPixels(pixels,cancel,progress==null?null:v->progress.accept(v*.6));
        renderLocal(pixels,edits,exifOrientation==0?pixels.exifOrientation():exifOrientation,cancel,progress==null?null:v->progress.accept(.6+.4*v));
    }
    public static void renderLocal(SpatialPreviewFilter.Pixels pixels,PhotoLocalEdits edits,int exif,BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        if(pixels==null||edits==null||exif<1||exif>8)throw new IllegalArgumentException("局部编辑照片无效。");
        if(!edits.portrait.bodyShape.isNeutral()){
            PhotoLocalEdits beforeWarp=edits.withPortrait(edits.portrait.withBodyShape(PhotoBodyShape.NONE));
            renderLocal(pixels,beforeWarp,exif,cancel,progress==null?null:v->progress.accept(v*.6));
            PhotoBodyWarp.apply(pixels,edits.portrait.bodyShape,exif,cancel,progress==null?null:v->progress.accept(.6+.4*v));return;
        }
        if(edits.regions().isEmpty()){renderLegacy(pixels,edits,exif,cancel,progress);return;}
        renderLegacy(pixels,edits,exif,cancel,progress==null?null:v->progress.accept(v*.35));
        AdjustmentRegionRenderer.apply(pixels,edits.regions(),exif,cancel,progress==null?null:v->progress.accept(.35+.65*v));
    }
    private static void renderLegacy(SpatialPreviewFilter.Pixels pixels,PhotoLocalEdits edits,int exif,BooleanSupplier cancel,DoubleConsumer progress)throws IOException{
        if(pixels==null||edits==null||exif<1||exif>8)throw new IllegalArgumentException("局部编辑照片无效。");
        int width=pixels.width(),height=pixels.height();if(width<1||height<1||width>65535||height>65535)throw new IllegalArgumentException("照片尺寸无效。");
        if(edits.isNeutral()){check(cancel);if(progress!=null)progress.accept(1);return;}
        int orientedWidth=exif>=5?height:width,orientedHeight=exif>=5?width:height;
        ArrayList<CompiledMask> masks=new ArrayList<>();for(PhotoLocalEdits.Mask mask:edits.masks())if(mask.hasEffect())masks.add(new CompiledMask(mask,orientedWidth,orientedHeight));
        if(!masks.isEmpty()){
            int[] row=new int[width];
            for(int y=0;y<height;y++){check(cancel);pixels.read(row,y,1);for(int x=0;x<width;x++){if((x&255)==0)check(cancel);double nx=(x+.5)/width,ny=(y+.5)/height,ox=orientedX(nx,ny,exif),oy=orientedY(nx,ny,exif);int value=row[x];if((value>>>24)==0)continue;for(CompiledMask mask:masks)value=mask.apply(value,ox,oy);row[x]=value;}pixels.write(row,y,1);if(progress!=null)progress.accept((edits.portrait.isNeutral()?.65:.26)*(y+1)/(double)height);}
        }else if(progress!=null)progress.accept(edits.portrait.isNeutral()?.65:.26);
        List<PhotoLocalEdits.Clone> patches=edits.clones();for(int i=0;i<patches.size();i++){check(cancel);PhotoLocalEdits.Clone clone=patches.get(i);if(clone.hasEffect())clone(pixels,clone,exif,cancel);if(progress!=null)progress.accept(edits.portrait.isNeutral()?.65+.35*(i+1)/(double)patches.size():.26+.14*(i+1)/(double)patches.size());}
        if(!edits.portrait.isNeutral())PortraitPreviewFilter.apply(pixels,edits.portrait,exif,cancel,progress==null?null:v->progress.accept(.4+.6*v));
        if(progress!=null)progress.accept(1);
    }
    public static double orientedX(double x,double y,int exif){switch(exif){case 2:case 3:return 1-x;case 5:case 8:return y;case 6:case 7:return 1-y;default:return x;}}
    public static double orientedY(double x,double y,int exif){switch(exif){case 3:case 4:return 1-y;case 5:case 6:return x;case 7:case 8:return 1-x;default:return y;}}
    public static double rawX(double x,double y,int exif){switch(exif){case 2:case 3:return 1-x;case 5:case 6:return y;case 7:case 8:return 1-y;default:return x;}}
    public static double rawY(double x,double y,int exif){switch(exif){case 3:case 4:return 1-y;case 5:case 8:return x;case 6:case 7:return 1-x;default:return y;}}
    private static final class CompiledMask {
        final PhotoLocalEdits.Mask mask;final int width,height;final double rGain,gGain,bGain,saturation,left,top,right,bottom;final BrushIndex brush;
        CompiledMask(PhotoLocalEdits.Mask m,int width,int height){mask=m;this.width=width;this.height=height;double t=m.temperature/100.0,exposure=Math.pow(2,m.exposure/10.0),r=Math.exp(.35*t),b=Math.exp(-.35*t),normal=.2126*r+.7152+.0722*b;rGain=exposure*r/normal;gGain=exposure/normal;bGain=exposure*b/normal;saturation=1+m.saturation/100.0;
            if(m.kind==PhotoLocalEdits.Kind.RADIAL){left=m.x0-m.x1;right=m.x0+m.x1;top=m.y0-m.y1;bottom=m.y0+m.y1;}
            else if(m.kind==PhotoLocalEdits.Kind.BRUSH){double[] p=m.points();double l=1,t0=1,r0=0,b0=0;for(int i=0;i<p.length;i+=2){l=Math.min(l,p[i]);r0=Math.max(r0,p[i]);t0=Math.min(t0,p[i+1]);b0=Math.max(b0,p[i+1]);}double shortSide=Math.min(width,height);left=l-m.radius*shortSide/width;right=r0+m.radius*shortSide/width;top=t0-m.radius*shortSide/height;bottom=b0+m.radius*shortSide/height;}
            else{left=top=Double.NEGATIVE_INFINITY;right=bottom=Double.POSITIVE_INFINITY;}brush=m.kind==PhotoLocalEdits.Kind.BRUSH?new BrushIndex(m,width,height):null;}
        int apply(int argb,double x,double y){boolean outside=x<left||x>right||y<top||y>bottom;double amount=outside?(mask.inverted?1:0):brush==null?mask.weight(x,y,width,height):brush.weight(x,y);if(amount<=0)return argb;double r=LINEAR[(argb>>>16)&255],g=LINEAR[(argb>>>8)&255],b=LINEAR[argb&255];double rr=r*rGain,gg=g*gGain,bb=b*bGain,l=.2126*rr+.7152*gg+.0722*bb;rr=l+(rr-l)*saturation;gg=l+(gg-l)*saturation;bb=l+(bb-l)*saturation;return(argb&0xff000000)|(encode(r+(rr-r)*amount)<<16)|(encode(g+(gg-g)*amount)<<8)|encode(b+(bb-b)*amount);}
    }
    /** Fixed 16x16 segment index: at most 512*256 indices per mask, independent of photo size. */
    private static final class BrushIndex {
        private static final int GRID=16;
        final PhotoLocalEdits.Mask mask;final int width,height;final double radius;final double[] ax,ay,vx,vy,length;
        final int[] starts,segments;
        BrushIndex(PhotoLocalEdits.Mask mask,int width,int height){this.mask=mask;this.width=width;this.height=height;radius=mask.radius*Math.min(width,height);double[] points=mask.points();int n=Math.max(1,points.length/2-1);ax=new double[n];ay=new double[n];vx=new double[n];vy=new double[n];length=new double[n];int[] left=new int[n],right=new int[n],top=new int[n],bottom=new int[n],counts=new int[GRID*GRID];
            for(int i=0;i<n;i++){int j=i*2,k=Math.min(j+2,points.length-2);ax[i]=points[j]*width;ay[i]=points[j+1]*height;vx[i]=points[k]*width-ax[i];vy[i]=points[k+1]*height-ay[i];length[i]=vx[i]*vx[i]+vy[i]*vy[i];left[i]=cell((Math.min(ax[i],ax[i]+vx[i])-radius)/width);right[i]=cell((Math.max(ax[i],ax[i]+vx[i])+radius)/width);top[i]=cell((Math.min(ay[i],ay[i]+vy[i])-radius)/height);bottom[i]=cell((Math.max(ay[i],ay[i]+vy[i])+radius)/height);for(int y=top[i];y<=bottom[i];y++)for(int x=left[i];x<=right[i];x++)counts[y*GRID+x]++;}
            starts=new int[counts.length+1];for(int i=0;i<counts.length;i++)starts[i+1]=starts[i]+counts[i];segments=new int[starts[counts.length]];int[] cursor=starts.clone();for(int i=0;i<n;i++)for(int y=top[i];y<=bottom[i];y++)for(int x=left[i];x<=right[i];x++){int c=y*GRID+x;segments[cursor[c]++]=i;}}
        double weight(double x,double y){int cell=cell(y)*GRID+cell(x);double px=x*width,py=y*height,best=Double.POSITIVE_INFINITY;for(int j=starts[cell];j<starts[cell+1];j++){int i=segments[j];double t=length[i]==0?0:Math.max(0,Math.min(1,((px-ax[i])*vx[i]+(py-ay[i])*vy[i])/length[i]));best=Math.min(best,Math.hypot(px-ax[i]-t*vx[i],py-ay[i]-t*vy[i]));}double value=PhotoLocalEdits.Mask.falloff(best/radius,mask.feather);return mask.inverted?1-value:value;}
        private static int cell(double value){return Math.max(0,Math.min(GRID-1,(int)Math.floor(value*GRID)));}
    }
    private static void clone(SpatialPreviewFilter.Pixels pixels,PhotoLocalEdits.Clone c,int exif,BooleanSupplier cancel)throws IOException{
        int width=pixels.width(),height=pixels.height(),ow=exif>=5?height:width,oh=exif>=5?width:height;double radius=c.radius*Math.min(ow,oh);
        double canonicalTargetX=c.targetX*ow-.5,canonicalTargetY=c.targetY*oh-.5,canonicalDX=(c.sourceX-c.targetX)*ow,canonicalDY=(c.sourceY-c.targetY)*oh;
        double tx=rawX(c.targetX,c.targetY,exif)*width-.5,ty=rawY(c.targetX,c.targetY,exif)*height-.5,sx=rawX(c.sourceX,c.sourceY,exif)*width-.5,sy=rawY(c.sourceX,c.sourceY,exif)*height-.5,dx=sx-tx,dy=sy-ty;
        int left=Math.max(0,(int)Math.floor(tx-radius)),right=Math.min(width-1,(int)Math.ceil(tx+radius)),top=Math.max(0,(int)Math.floor(ty-radius)),bottom=Math.min(height-1,(int)Math.ceil(ty+radius));
        int sourceLeft=Math.max(0,(int)Math.floor(left+dx)),sourceRight=Math.min(width-1,(int)Math.ceil(right+dx)),sourceTop=Math.max(0,(int)Math.floor(top+dy)),sourceBottom=Math.min(height-1,(int)Math.ceil(bottom+dy));
        if(right<left||bottom<top||sourceRight<sourceLeft||sourceBottom<sourceTop)return;
        int patchWidth=sourceRight-sourceLeft+1,patchHeight=sourceBottom-sourceTop+1;long patchPixels=(long)patchWidth*patchHeight;if(patchPixels>MAX_PATCH_PIXELS)throw new IOException("修复区域过大，请缩小修复半径。");
        int[] patch=new int[(int)patchPixels],row=new int[width];
        for(int y=sourceTop;y<=sourceBottom;y++){check(cancel);pixels.read(row,y,1);System.arraycopy(row,sourceLeft,patch,(y-sourceTop)*patchWidth,patchWidth);}
        // Snapshot the source patch before writing any destination row; overlap is safe and ordered.
        for(int y=top;y<=bottom;y++){check(cancel);pixels.read(row,y,1);for(int x=left;x<=right;x++){if((x&255)==0)check(cancel);int ox=orientedPixelX(x,y,width,height,exif),oy=orientedPixelY(x,y,width,height,exif);double distance=Math.hypot(ox-canonicalTargetX,oy-canonicalTargetY)/radius,amount=PhotoLocalEdits.Mask.falloff(distance,c.feather);if(amount<=0)continue;double px=ox+canonicalDX,py=oy+canonicalDY;if(px<-.5||py<-.5||px>ow-.5||py>oh-.5)continue;int sampleX=Math.max(0,Math.min(ow-1,(int)Math.round(px))),sampleY=Math.max(0,Math.min(oh-1,(int)Math.round(py))),ix=rawPixelX(sampleX,sampleY,width,height,exif),iy=rawPixelY(sampleX,sampleY,width,height,exif);int source=patch[(iy-sourceTop)*patchWidth+ix-sourceLeft],target=row[x];if((source>>>24)==0||(target>>>24)==0)continue;amount*=((source>>>24)&255)/255.0;double r=LINEAR[(target>>>16)&255],g=LINEAR[(target>>>8)&255],b=LINEAR[target&255];row[x]=(target&0xff000000)|(encode(r+(LINEAR[(source>>>16)&255]-r)*amount)<<16)|(encode(g+(LINEAR[(source>>>8)&255]-g)*amount)<<8)|encode(b+(LINEAR[source&255]-b)*amount);}pixels.write(row,y,1);}
    }
    // Resolve nearest-neighbour ties in the canonical oriented frame, then permute exact indices.
    // Rounding a reflected raw coordinate instead would pick the opposite pixel at exact halves.
    private static int orientedPixelX(int x,int y,int w,int h,int exif){switch(exif){case 2:case 3:return w-1-x;case 5:case 8:return y;case 6:case 7:return h-1-y;default:return x;}}
    private static int orientedPixelY(int x,int y,int w,int h,int exif){switch(exif){case 3:case 4:return h-1-y;case 5:case 6:return x;case 7:case 8:return w-1-x;default:return y;}}
    private static int rawPixelX(int x,int y,int w,int h,int exif){switch(exif){case 2:case 3:return w-1-x;case 5:case 6:return y;case 7:case 8:return w-1-y;default:return x;}}
    private static int rawPixelY(int x,int y,int w,int h,int exif){switch(exif){case 3:case 4:return h-1-y;case 5:case 8:return x;case 6:case 7:return h-1-x;default:return y;}}
    private static int encode(double value){return ENCODE[(int)Math.round(Math.max(0,Math.min(1,value))*(ENCODE.length-1))];}
    private static void check(BooleanSupplier cancel)throws InterruptedIOException{if(Thread.currentThread().isInterrupted()||cancel!=null&&cancel.getAsBoolean())throw new InterruptedIOException("局部编辑已取消。");}
}
