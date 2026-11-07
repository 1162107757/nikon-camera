package cc.huevia.ncp;

import java.io.*;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.*;

/** Immutable edits bound to one photograph, in its EXIF-oriented, pre-composition frame. */
public final class PhotoLocalEdits {
    public static final String MODEL="photo-local-linear-v1";
    public static final int MAX_MASKS=16,MAX_CLONES=64,MAX_BRUSH_POINTS=512,MAX_REGIONS=16;
    public static final int MAX_REGION_STROKES=256,MAX_REGION_POINTS=32768;
    public static final int MAX_REGION_RECIPE_BYTES=1_000_000;
    public static final PhotoLocalEdits NONE=new PhotoLocalEdits(Collections.emptyList(),Collections.emptyList());
    private final List<Mask> masks;
    private final List<Clone> clones;
    private final List<AdjustmentRegion> regions;
    public final PhotoPortrait portrait;
    public enum Kind { BRUSH,RADIAL,LINEAR }
    public PhotoLocalEdits(List<Mask> masks,List<Clone> clones){
        this(masks,clones,PhotoPortrait.NONE);
    }
    public PhotoLocalEdits(List<Mask> masks,List<Clone> clones,PhotoPortrait portrait){
        this(masks,clones,portrait,Collections.emptyList());
    }
    public PhotoLocalEdits(List<Mask> masks,List<Clone> clones,PhotoPortrait portrait,List<AdjustmentRegion> regions){
        if(masks==null||clones==null||portrait==null||regions==null||masks.size()>MAX_MASKS||clones.size()>MAX_CLONES||regions.size()>MAX_REGIONS)throw new IllegalArgumentException("局部编辑数量超出范围。");
        ArrayList<Mask> m=new ArrayList<>(masks);ArrayList<Clone> c=new ArrayList<>(clones);
        if(m.contains(null)||c.contains(null))throw new IllegalArgumentException("局部编辑无效。");
        ArrayList<AdjustmentRegion> r=new ArrayList<>(regions);Set<String> ids=new HashSet<>();int strokes=0,points=0;
        for(AdjustmentRegion region:r){if(region==null||!ids.add(region.id))throw new IllegalArgumentException("局部调节区域无效。");strokes+=region.strokes.size();for(PhotoPortrait.Stroke stroke:region.strokes)points+=stroke.points().length/2;}
        if(strokes>MAX_REGION_STROKES||points>MAX_REGION_POINTS)throw new IllegalArgumentException("局部调节轨迹总量超限。");
        this.masks=Collections.unmodifiableList(m);this.clones=Collections.unmodifiableList(c);this.portrait=portrait;this.regions=Collections.unmodifiableList(r);
        if(!r.isEmpty())try{write(new DataOutputStream(new OutputStream(){int bytes;public void write(int value)throws IOException{reserve(1);}public void write(byte[] value,int offset,int length)throws IOException{reserve(length);}private void reserve(int count)throws IOException{if(count<0||bytes>MAX_REGION_RECIPE_BYTES-count)throw new IOException("局部调节数据已达容量上限，请删除不再使用的区域。");bytes+=count;}}));}catch(IOException tooLarge){throw new IllegalArgumentException(tooLarge.getMessage(),tooLarge);}
    }
    public List<Mask> masks(){return masks;}
    public List<Clone> clones(){return clones;}
    public List<AdjustmentRegion> regions(){return regions;}
    public boolean isEmpty(){return masks.isEmpty()&&clones.isEmpty()&&portrait.isEmpty()&&regions.isEmpty();}
    public boolean hasLocalEffects(){for(Mask m:masks)if(m.hasEffect())return true;for(Clone c:clones)if(c.hasEffect())return true;for(AdjustmentRegion r:regions)if(r.hasEffect())return true;return false;}
    public boolean isNeutral(){return !hasLocalEffects()&&portrait.isNeutral();}
    /** Keep a frozen zero-intensity regional analysis in draft/version comparisons. */
    public boolean hasStoredSkinSmoothingState(){if(portrait.skinSmoothing>0||portrait.hasRetouchState())return true;for(AdjustmentRegion region:regions)if(region.portrait.skinSmoothing>0||region.portrait.hasRetouchState())return true;return false;}
    public boolean hasStoredBodyState(){if(portrait.bodyShape.hasStoredState())return true;for(AdjustmentRegion region:regions)if(region.portrait.bodyShape.hasStoredState())return true;return false;}
    public boolean hasStoredCleanupState(){for(AdjustmentRegion region:regions)if(region.adjustments.cleanup.hasStoredState())return true;return false;}
    public PhotoLocalEdits withPortrait(PhotoPortrait value){return new PhotoLocalEdits(masks,clones,value,regions);}
    public PhotoLocalEdits add(Mask value){ArrayList<Mask> m=new ArrayList<>(masks);m.add(value);return new PhotoLocalEdits(m,clones,portrait,regions);}
    public PhotoLocalEdits withMask(int index,Mask value){ArrayList<Mask> m=new ArrayList<>(masks);m.set(index,value);return new PhotoLocalEdits(m,clones,portrait,regions);}
    public PhotoLocalEdits removeMask(int index){ArrayList<Mask> m=new ArrayList<>(masks);m.remove(index);return new PhotoLocalEdits(m,clones,portrait,regions);}
    public PhotoLocalEdits add(Clone value){ArrayList<Clone> c=new ArrayList<>(clones);c.add(value);return new PhotoLocalEdits(masks,c,portrait,regions);}
    public PhotoLocalEdits withClone(int index,Clone value){ArrayList<Clone> c=new ArrayList<>(clones);c.set(index,value);return new PhotoLocalEdits(masks,c,portrait,regions);}
    public PhotoLocalEdits removeClone(int index){ArrayList<Clone> c=new ArrayList<>(clones);c.remove(index);return new PhotoLocalEdits(masks,c,portrait,regions);}
    public PhotoLocalEdits withRegions(List<AdjustmentRegion> values){return new PhotoLocalEdits(masks,clones,portrait,values);}
    public PhotoLocalEdits addRegion(AdjustmentRegion value){ArrayList<AdjustmentRegion> r=new ArrayList<>(regions);r.add(Objects.requireNonNull(value));return withRegions(r);}
    public PhotoLocalEdits withRegion(int index,AdjustmentRegion value){ArrayList<AdjustmentRegion> r=new ArrayList<>(regions);r.set(index,Objects.requireNonNull(value));return withRegions(r);}
    public PhotoLocalEdits removeRegion(int index){ArrayList<AdjustmentRegion> r=new ArrayList<>(regions);r.remove(index);return withRegions(r);}
    public String identity(){try{ByteArrayOutputStream bytes=new ByteArrayOutputStream();write(new DataOutputStream(bytes));byte[] hash=MessageDigest.getInstance("SHA-256").digest(bytes.toByteArray());StringBuilder s=new StringBuilder(MODEL+":");for(byte b:hash)s.append(Character.forDigit((b>>>4)&15,16)).append(Character.forDigit(b&15,16));return s.toString();}catch(IOException impossible){throw new AssertionError(impossible);}catch(NoSuchAlgorithmException impossible){throw new AssertionError(impossible);}}
    public void write(DataOutput out)throws IOException{int version=regions.isEmpty()?(portrait.isEmpty()?1:2):3;for(AdjustmentRegion region:regions)if(region.adjustments.cleanup.hasStoredState()){version=5;break;}else if(region.adjustments.palette.hasStoredState())version=4;out.writeInt(version);out.writeInt(masks.size());for(Mask m:masks)m.write(out);out.writeInt(clones.size());for(Clone c:clones)c.write(out);if(version>=2)portrait.write(out);if(version>=3){out.writeInt(regions.size());for(AdjustmentRegion region:regions)region.write(out,version>=4,version>=5);}}
    public static PhotoLocalEdits read(DataInput in)throws IOException{
        int version=in.readInt();if(version<1||version>5)throw new IOException("局部编辑版本不支持。");
        try{int n=count(in.readInt(),MAX_MASKS);ArrayList<Mask> masks=new ArrayList<>(n);for(int i=0;i<n;i++)masks.add(Mask.read(in));n=count(in.readInt(),MAX_CLONES);ArrayList<Clone> clones=new ArrayList<>(n);for(int i=0;i<n;i++)clones.add(Clone.read(in));PhotoPortrait portrait=version>=2?PhotoPortrait.read(in):PhotoPortrait.NONE;ArrayList<AdjustmentRegion> regions=new ArrayList<>();if(version>=3){n=count(in.readInt(),MAX_REGIONS);for(int i=0;i<n;i++)regions.add(AdjustmentRegion.read(in,version>=4,version>=5));}return masks.isEmpty()&&clones.isEmpty()&&portrait.isEmpty()&&regions.isEmpty()?NONE:new PhotoLocalEdits(masks,clones,portrait,regions);}catch(IllegalArgumentException bad){throw new IOException("局部编辑数据无效。",bad);}
    }
    private static int count(int value,int max)throws IOException{if(value<0||value>max)throw new IOException("局部编辑数量无效。");return value;}
    @Override public boolean equals(Object other){return other instanceof PhotoLocalEdits&&masks.equals(((PhotoLocalEdits)other).masks)&&clones.equals(((PhotoLocalEdits)other).clones)&&portrait.equals(((PhotoLocalEdits)other).portrait)&&regions.equals(((PhotoLocalEdits)other).regions);}
    @Override public int hashCode(){return Objects.hash(masks,clones,portrait,regions);}
    private static double value(double n,double min,double max){if(!Double.isFinite(n)||n<min||n>max)throw new IllegalArgumentException("局部编辑参数超出范围。");return n==0?0:n;}
    private static int integer(int n,int min,int max){if(n<min||n>max)throw new IllegalArgumentException("局部调节数值超出范围。");return n;}
    static double smooth(double x){x=Math.max(0,Math.min(1,x));return x*x*(3-2*x);}

    public static final class Mask {
        public final Kind kind;public final double x0,y0,x1,y1,radius,feather;public final boolean inverted,enabled;
        public final int exposure,temperature,saturation;
        private final double[] points;
        /** Radial x0/y0=center, x1/y1=axis radii. Linear x0/y0=start, x1/y1=end. */
        public Mask(Kind kind,double x0,double y0,double x1,double y1,double radius,double feather,boolean inverted,boolean enabled,int exposure,int temperature,int saturation,double[] points){
            if(kind==null)throw new IllegalArgumentException("蒙版类型无效。");this.kind=kind;
            this.x0=value(x0,0,1);this.y0=value(y0,0,1);this.x1=value(x1,0,1);this.y1=value(y1,0,1);
            this.radius=value(radius,.001,.5);this.feather=value(feather,0,1);this.inverted=inverted;this.enabled=enabled;
            this.exposure=integer(exposure,-30,30);this.temperature=integer(temperature,-100,100);this.saturation=integer(saturation,-100,100);
            if(kind==Kind.RADIAL&&(x1<.001||y1<.001)||kind==Kind.LINEAR&&Math.hypot(x1-x0,y1-y0)<.001)throw new IllegalArgumentException("蒙版区域过小。");
            if(points==null||points.length%2!=0||points.length>MAX_BRUSH_POINTS*2||kind==Kind.BRUSH&&points.length<2||kind!=Kind.BRUSH&&points.length!=0)throw new IllegalArgumentException("画笔轨迹无效。");
            this.points=points.clone();for(int i=0;i<this.points.length;i++)this.points[i]=value(this.points[i],0,1);
        }
        public static Mask radial(double x,double y){return new Mask(Kind.RADIAL,x,y,.22,.22,.08,.6,false,true,0,0,0,new double[0]);}
        public static Mask linear(double x0,double y0,double x1,double y1){return new Mask(Kind.LINEAR,x0,y0,x1,y1,.08,.7,false,true,0,0,0,new double[0]);}
        public static Mask brush(double[] points,double radius,double feather){return new Mask(Kind.BRUSH,0,0,0,0,radius,feather,false,true,0,0,0,points);}
        public double[] points(){return points.clone();}
        public Mask parameters(int exposure,int temperature,int saturation){return new Mask(kind,x0,y0,x1,y1,radius,feather,inverted,enabled,exposure,temperature,saturation,points);}
        public Mask shape(double x0,double y0,double x1,double y1,double radius,double feather){return new Mask(kind,x0,y0,x1,y1,radius,feather,inverted,enabled,exposure,temperature,saturation,points);}
        public Mask inverted(boolean value){return new Mask(kind,x0,y0,x1,y1,radius,feather,value,enabled,exposure,temperature,saturation,points);}
        public Mask enabled(boolean value){return new Mask(kind,x0,y0,x1,y1,radius,feather,inverted,value,exposure,temperature,saturation,points);}
        public boolean hasEffect(){return enabled&&(exposure!=0||temperature!=0||saturation!=0);}
        /** Coordinates are normalized to each oriented axis; brush radius uses the shorter side. */
        public double weight(double x,double y,int width,int height){
            if(!enabled)return 0;double amount;
            if(kind==Kind.RADIAL){double distance=Math.hypot((x-x0)/x1,(y-y0)/y1);amount=falloff(distance,feather);}
            else if(kind==Kind.LINEAR){double dx=(x1-x0)*width,dy=(y1-y0)*height;double t=(((x-x0)*width)*dx+((y-y0)*height)*dy)/(dx*dx+dy*dy);double span=Math.max(.001,feather);amount=smooth((t-(.5-span*.5))/span);}
            else{double unit=Math.min(width,height),px=x*width,py=y*height,best=Double.POSITIVE_INFINITY;for(int i=0;i<points.length;i+=2){double ax=points[i]*width,ay=points[i+1]*height,bx=i+2<points.length?points[i+2]*width:ax,by=i+3<points.length?points[i+3]*height:ay;double vx=bx-ax,vy=by-ay,t=vx*vx+vy*vy==0?0:Math.max(0,Math.min(1,((px-ax)*vx+(py-ay)*vy)/(vx*vx+vy*vy)));best=Math.min(best,Math.hypot(px-ax-t*vx,py-ay-t*vy));}amount=falloff(best/(radius*unit),feather);}
            return inverted?1-amount:amount;
        }
        static double falloff(double distance,double feather){if(distance>=1)return 0;if(feather<=0||distance<=1-feather)return 1;return 1-smooth((distance-(1-feather))/feather);}
        private void write(DataOutput out)throws IOException{out.writeByte(kind.ordinal());out.writeDouble(x0);out.writeDouble(y0);out.writeDouble(x1);out.writeDouble(y1);out.writeDouble(radius);out.writeDouble(feather);out.writeBoolean(inverted);out.writeBoolean(enabled);out.writeInt(exposure);out.writeInt(temperature);out.writeInt(saturation);out.writeInt(points.length);for(double point:points)out.writeDouble(point);}
        private static Mask read(DataInput in)throws IOException{int kind=in.readUnsignedByte();if(kind>=Kind.values().length)throw new IOException("蒙版类型无效。");double x0=in.readDouble(),y0=in.readDouble(),x1=in.readDouble(),y1=in.readDouble(),r=in.readDouble(),f=in.readDouble();boolean inverted=in.readBoolean(),enabled=in.readBoolean();int exposure=in.readInt(),temperature=in.readInt(),saturation=in.readInt();int count=count(in.readInt(),MAX_BRUSH_POINTS*2);double[] p=new double[count];for(int i=0;i<count;i++)p[i]=in.readDouble();return new Mask(Kind.values()[kind],x0,y0,x1,y1,r,f,inverted,enabled,exposure,temperature,saturation,p);}
        @Override public boolean equals(Object other){if(!(other instanceof Mask))return false;Mask m=(Mask)other;return kind==m.kind&&x0==m.x0&&y0==m.y0&&x1==m.x1&&y1==m.y1&&radius==m.radius&&feather==m.feather&&inverted==m.inverted&&enabled==m.enabled&&exposure==m.exposure&&temperature==m.temperature&&saturation==m.saturation&&Arrays.equals(points,m.points);}
        @Override public int hashCode(){return Objects.hash(kind,x0,y0,x1,y1,radius,feather,inverted,enabled,exposure,temperature,saturation,Arrays.hashCode(points));}
    }

    /** A feathered clone patch. The UI exposes source and destination; no inferred/AI content. */
    public static final class Clone {
        public final double sourceX,sourceY,targetX,targetY,radius,feather;public final boolean enabled;
        public Clone(double sourceX,double sourceY,double targetX,double targetY,double radius,double feather,boolean enabled){this.sourceX=value(sourceX,0,1);this.sourceY=value(sourceY,0,1);this.targetX=value(targetX,0,1);this.targetY=value(targetY,0,1);this.radius=value(radius,.001,.25);this.feather=value(feather,0,1);this.enabled=enabled;}
        public Clone enabled(boolean value){return new Clone(sourceX,sourceY,targetX,targetY,radius,feather,value);}
        public Clone size(double radius,double feather){return new Clone(sourceX,sourceY,targetX,targetY,radius,feather,enabled);}
        public boolean hasEffect(){return enabled&&(sourceX!=targetX||sourceY!=targetY);}
        private void write(DataOutput out)throws IOException{out.writeDouble(sourceX);out.writeDouble(sourceY);out.writeDouble(targetX);out.writeDouble(targetY);out.writeDouble(radius);out.writeDouble(feather);out.writeBoolean(enabled);}
        private static Clone read(DataInput in)throws IOException{return new Clone(in.readDouble(),in.readDouble(),in.readDouble(),in.readDouble(),in.readDouble(),in.readDouble(),in.readBoolean());}
        @Override public boolean equals(Object other){if(!(other instanceof Clone))return false;Clone c=(Clone)other;return sourceX==c.sourceX&&sourceY==c.sourceY&&targetX==c.targetX&&targetY==c.targetY&&radius==c.radius&&feather==c.feather&&enabled==c.enabled;}
        @Override public int hashCode(){return Objects.hash(sourceX,sourceY,targetX,targetY,radius,feather,enabled);}
    }
}
