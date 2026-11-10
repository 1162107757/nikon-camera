package cc.huevia.ncp;

import java.io.DataInput;
import java.io.DataOutput;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Objects;
import java.util.UUID;

/** One independently painted adjustment, in the oriented source frame before composition. */
public final class AdjustmentRegion {
    public static final int MAX_STROKES=64, MAX_POINTS=8192;
    public final String id,name;
    public final boolean enabled;
    public final double amount;
    public final List<PhotoPortrait.Stroke> strokes;
    public final List<SelectionShape> shapes;
    public final boolean inverted;
    public final PhotoAdjustments adjustments;
    public final PhotoPortrait portrait;
    /** Whole exposed-skin colour/texture. Face light and under-eye settings belong to portrait. */
    public final PhotoPortrait.Settings skinSettings;
    public final PhotoPortrait.BodySkinMask skinMask;

    public AdjustmentRegion(String id,String name,boolean enabled,double amount,List<PhotoPortrait.Stroke> strokes,
            PhotoAdjustments adjustments,PhotoPortrait portrait,PhotoPortrait.Settings skinSettings,
            PhotoPortrait.BodySkinMask skinMask){
        this(id,name,enabled,amount,strokes,adjustments,portrait,skinSettings,skinMask,Collections.emptyList(),false);
    }
    public AdjustmentRegion(String id,String name,boolean enabled,double amount,List<PhotoPortrait.Stroke> strokes,
            PhotoAdjustments adjustments,PhotoPortrait portrait,PhotoPortrait.Settings skinSettings,
            PhotoPortrait.BodySkinMask skinMask,List<SelectionShape> shapes,boolean inverted){
        if(id==null||!id.matches("[A-Za-z0-9_-]{1,64}"))throw new IllegalArgumentException("局部调节标识无效。");
        if(name==null||name.trim().isEmpty()||name.length()>40)throw new IllegalArgumentException("局部调节名称无效。");
        for(int i=0;i<name.length();i++)if(Character.isISOControl(name.charAt(i)))throw new IllegalArgumentException("局部调节名称无效。");
        if(!Double.isFinite(amount)||amount<0||amount>1||strokes==null||strokes.size()>MAX_STROKES)throw new IllegalArgumentException("局部画笔数据超限。");
        this.id=id;this.name=name.trim();this.enabled=enabled;this.amount=amount==0?0:amount;
        ArrayList<PhotoPortrait.Stroke> copy=new ArrayList<>(strokes);int points=0;
        for(PhotoPortrait.Stroke stroke:copy){Objects.requireNonNull(stroke,"stroke");points+=stroke.points().length/2;}
        if(points>MAX_POINTS)throw new IllegalArgumentException("局部画笔轨迹总量超限。");
        if(shapes==null||strokes.size()+shapes.size()>MAX_STROKES)throw new IllegalArgumentException("选区元素数量超限。");
        ArrayList<SelectionShape> shapeCopy=new ArrayList<>(shapes);int last=0;
        for(SelectionShape shape:shapeCopy){Objects.requireNonNull(shape,"shape");if(shape.strokeIndex<last||shape.strokeIndex>strokes.size())throw new IllegalArgumentException("选区元素顺序无效。");last=shape.strokeIndex;}
        this.shapes=Collections.unmodifiableList(shapeCopy);this.inverted=inverted;
        this.strokes=Collections.unmodifiableList(copy);this.adjustments=Objects.requireNonNull(adjustments,"adjustments");
        this.portrait=Objects.requireNonNull(portrait,"portrait");this.skinSettings=Objects.requireNonNull(skinSettings,"skinSettings");this.skinMask=skinMask;
        if(skinSettings.light!=0||skinSettings.shadows!=0)throw new IllegalArgumentException("面部光影需要对应的人脸选区。");
    }
    public static AdjustmentRegion create(String name){return new AdjustmentRegion(UUID.randomUUID().toString(),name,true,1,Collections.emptyList(),PhotoAdjustments.NONE,PhotoPortrait.NONE,PhotoPortrait.Settings.NONE,null);}
    public AdjustmentRegion withName(String value){return copy(value,enabled,amount,strokes,adjustments,portrait,skinSettings,skinMask);}
    public AdjustmentRegion withEnabled(boolean value){return copy(name,value,amount,strokes,adjustments,portrait,skinSettings,skinMask);}
    public AdjustmentRegion withAmount(double value){return copy(name,enabled,value,strokes,adjustments,portrait,skinSettings,skinMask);}
    public AdjustmentRegion withStrokes(List<PhotoPortrait.Stroke> value){ArrayList<SelectionShape> retained=new ArrayList<>();for(SelectionShape shape:shapes)retained.add(shape.afterStroke(Math.min(shape.strokeIndex,value.size())));return new AdjustmentRegion(id,name,enabled,amount,value,adjustments,portrait,skinSettings,skinMask,retained,inverted);}
    public AdjustmentRegion addStroke(PhotoPortrait.Stroke value){ArrayList<PhotoPortrait.Stroke> next=new ArrayList<>(strokes);next.add(Objects.requireNonNull(value));return withStrokes(next);}
    public AdjustmentRegion withAdjustments(PhotoAdjustments value){return copy(name,enabled,amount,strokes,value,portrait,skinSettings,skinMask);}
    public AdjustmentRegion withPortrait(PhotoPortrait value){return copy(name,enabled,amount,strokes,adjustments,value,skinSettings,skinMask);}
    public AdjustmentRegion withSkinSettings(PhotoPortrait.Settings value){return copy(name,enabled,amount,strokes,adjustments,portrait,value,skinMask);}
    public AdjustmentRegion withSkinMask(PhotoPortrait.BodySkinMask value){return copy(name,enabled,amount,strokes,adjustments,portrait,skinSettings,value);}
    private AdjustmentRegion copy(String n,boolean e,double a,List<PhotoPortrait.Stroke> s,PhotoAdjustments v,PhotoPortrait p,PhotoPortrait.Settings k,PhotoPortrait.BodySkinMask m){return new AdjustmentRegion(id,n,e,a,s,v,p,k,m,shapes,inverted);}
    public AdjustmentRegion withShapes(List<SelectionShape> value){return new AdjustmentRegion(id,name,enabled,amount,strokes,adjustments,portrait,skinSettings,skinMask,value,inverted);}
    public AdjustmentRegion addShape(SelectionShape value){ArrayList<SelectionShape> next=new ArrayList<>(shapes);next.add(Objects.requireNonNull(value));return withShapes(next);}
    public AdjustmentRegion withInverted(boolean value){return new AdjustmentRegion(id,name,enabled,amount,strokes,adjustments,portrait,skinSettings,skinMask,shapes,value);}
    public AdjustmentRegion clearSelection(){return new AdjustmentRegion(id,name,enabled,amount,Collections.emptyList(),adjustments,portrait,skinSettings,skinMask,Collections.emptyList(),false);}
    public boolean hasSelection(){for(PhotoPortrait.Stroke s:strokes)if(!s.erase)return true;for(SelectionShape s:shapes)if(!s.subtract)return true;return false;}
    public boolean hasEffect(){return enabled&&amount>0&&(!adjustments.isNeutral()||!portrait.isNeutral()||!skinSettings.isNeutral()&&effectiveSkinMask()!=null)&&hasSelection();}
    public PhotoPortrait.BodySkinMask effectiveSkinMask(){return skinMask==null?portrait.globalSkinMask:skinMask;}
    public Brush compileBrush(int width,int height){return new Brush(strokes,shapes,inverted,width,height);}

    void write(DataOutput out)throws IOException{
        write(out,false);
    }
    void write(DataOutput out,boolean palette)throws IOException{
        write(out,palette,false);
    }
    void write(DataOutput out,boolean palette,boolean cleanup)throws IOException{
        write(out,palette,cleanup,false);
    }
    void write(DataOutput out,boolean palette,boolean cleanup,boolean selection)throws IOException{
        out.writeUTF(id);out.writeUTF(name);out.writeBoolean(enabled);out.writeDouble(amount);out.writeInt(strokes.size());
        for(PhotoPortrait.Stroke s:strokes){out.writeDouble(s.radius);out.writeDouble(s.feather);out.writeBoolean(s.erase);double[] p=s.points();out.writeInt(p.length);for(double v:p)out.writeDouble(v);}
        for(int v:adjustments.values())out.writeInt(v);adjustments.writeAdvanced(out);if(palette)adjustments.palette.write(out);if(cleanup)adjustments.cleanup.write(out);portrait.write(out);
        out.writeInt(skinSettings.brightness);out.writeInt(skinSettings.warmth);out.writeInt(skinSettings.redness);out.writeInt(skinSettings.smoothing);out.writeInt(skinSettings.texture);
        out.writeBoolean(skinMask!=null);if(skinMask!=null)out.write(skinMask.copyCoverage());
        if(selection){out.writeBoolean(inverted);out.writeInt(shapes.size());for(SelectionShape s:shapes){out.writeByte(s.kind.ordinal());out.writeDouble(s.left);out.writeDouble(s.top);out.writeDouble(s.right);out.writeDouble(s.bottom);out.writeDouble(s.feather);out.writeBoolean(s.subtract);out.writeInt(s.strokeIndex);}}
    }
    static AdjustmentRegion read(DataInput in)throws IOException{
        return read(in,false);
    }
    static AdjustmentRegion read(DataInput in,boolean palette)throws IOException{
        return read(in,palette,false);
    }
    static AdjustmentRegion read(DataInput in,boolean palette,boolean cleanup)throws IOException{
        return read(in,palette,cleanup,false);
    }
    static AdjustmentRegion read(DataInput in,boolean palette,boolean cleanup,boolean selection)throws IOException{
        String id=in.readUTF(),name=in.readUTF();boolean enabled=bool(in);double amount=in.readDouble();int count=count(in.readInt(),MAX_STROKES);ArrayList<PhotoPortrait.Stroke> strokes=new ArrayList<>(count);int total=0;
        for(int i=0;i<count;i++){double radius=in.readDouble(),feather=in.readDouble();boolean erase=bool(in);int n=count(in.readInt(),PhotoPortrait.MAX_STROKE_POINTS*2);if(n<2||(n&1)!=0)throw new IOException("局部画笔轨迹无效。");total+=n/2;if(total>MAX_POINTS)throw new IOException("局部画笔轨迹总量超限。");double[] points=new double[n];for(int j=0;j<n;j++)points[j]=in.readDouble();strokes.add(new PhotoPortrait.Stroke(points,radius,feather,erase));}
        int[] values=new int[PhotoAdjustments.Parameter.values().length];for(int i=0;i<values.length;i++)values[i]=in.readInt();PhotoAdjustments adjustments=new PhotoAdjustments(values).readAdvanced(in);if(palette)adjustments=adjustments.withPalette(PhotoColorPalette.read(in));if(cleanup)adjustments=adjustments.withCleanup(PhotoCleanup.read(in));PhotoPortrait portrait=PhotoPortrait.read(in);
        PhotoPortrait.Settings skin=new PhotoPortrait.Settings(in.readInt(),in.readInt(),in.readInt(),in.readInt(),in.readInt(),0,0);PhotoPortrait.BodySkinMask mask=null;
        if(bool(in)){byte[] bytes=new byte[PhotoPortrait.BodySkinMask.SIZE*PhotoPortrait.BodySkinMask.SIZE];in.readFully(bytes);mask=new PhotoPortrait.BodySkinMask(bytes);}
        boolean inverted=false;ArrayList<SelectionShape> shapes=new ArrayList<>();
        if(selection){inverted=bool(in);int n=count(in.readInt(),MAX_STROKES);for(int i=0;i<n;i++){int kind=in.readUnsignedByte();if(kind>=SelectionShape.Kind.values().length)throw new IOException("形状选区类型无效。");shapes.add(new SelectionShape(SelectionShape.Kind.values()[kind],in.readDouble(),in.readDouble(),in.readDouble(),in.readDouble(),in.readDouble(),bool(in),in.readInt()));}}
        return new AdjustmentRegion(id,name,enabled,amount,strokes,adjustments,portrait,skin,mask,shapes,inverted);
    }
    private static boolean bool(DataInput in)throws IOException{int value=in.readUnsignedByte();if(value>1)throw new IOException("局部调节开关无效。");return value==1;}
    private static int count(int n,int max)throws IOException{if(n<0||n>max)throw new IOException("局部画笔数量超限。");return n;}
    @Override public boolean equals(Object other){if(!(other instanceof AdjustmentRegion))return false;AdjustmentRegion r=(AdjustmentRegion)other;return id.equals(r.id)&&name.equals(r.name)&&enabled==r.enabled&&amount==r.amount&&strokes.equals(r.strokes)&&shapes.equals(r.shapes)&&inverted==r.inverted&&adjustments.equals(r.adjustments)&&portrait.equals(r.portrait)&&skinSettings.equals(r.skinSettings)&&Objects.equals(skinMask,r.skinMask);}
    @Override public int hashCode(){return Objects.hash(id,name,enabled,amount,strokes,shapes,inverted,adjustments,portrait,skinSettings,skinMask);}

    /** Starts completely empty. Add/erase are ordered coverage operations, never face-selection edits. */
    public static final class Brush {
        private final SegmentStroke[] strokes;
        private final SelectionShape[] shapes;
        private final boolean inverted,hasSelection;
        public final double left,top,right,bottom;
        public final long workingBytes;
        Brush(List<PhotoPortrait.Stroke> values,List<SelectionShape> shapes,boolean inverted,int width,int height){
            if(width<1||height<1||width>65535||height>65535)throw new IllegalArgumentException("局部画笔照片尺寸无效。");
            strokes=new SegmentStroke[values.size()];double l=1,t=1,r=0,b=0;long memory=0;
            for(int i=0;i<strokes.length;i++){SegmentStroke s=new SegmentStroke(values.get(i),width,height);strokes[i]=s;memory+=s.workingBytes;if(!s.erase){l=Math.min(l,s.left);t=Math.min(t,s.top);r=Math.max(r,s.right);b=Math.max(b,s.bottom);}}
            this.shapes=shapes.toArray(new SelectionShape[0]);this.inverted=inverted;
            for(SelectionShape s:this.shapes)if(!s.subtract){l=Math.min(l,s.left);t=Math.min(t,s.top);r=Math.max(r,s.right);b=Math.max(b,s.bottom);}
            hasSelection=r>l&&b>t;if(inverted&&hasSelection){l=t=0;r=b=1;}memory+=64L*this.shapes.length;
            left=Math.max(0,l);top=Math.max(0,t);right=Math.min(1,r);bottom=Math.min(1,b);workingBytes=memory;
        }
        public double weight(double nx,double ny){
            if(!Double.isFinite(nx)||!Double.isFinite(ny)||nx<left||nx>right||ny<top||ny>bottom)return 0;
            double amount=0;int shape=0;for(int i=0;i<=strokes.length;i++){while(shape<shapes.length&&shapes[shape].strokeIndex==i){SelectionShape s=shapes[shape++];double w=s.weight(nx,ny);amount=s.subtract?amount*(1-w):amount+(1-amount)*w;}if(i<strokes.length){SegmentStroke s=strokes[i];double w=s.weight(nx,ny);amount=s.erase?amount*(1-w):amount+(1-amount)*w;}}
            return Math.max(0,Math.min(1,inverted&&hasSelection?1-amount:amount));
        }
    }
    private static final class SegmentStroke {
        private static final int GRID=16;
        final double[] ax,ay,vx,vy,length;
        final int[] starts,segments;
        final int width,height;
        final double radius,feather,left,top,right,bottom;
        final boolean erase;
        final long workingBytes;
        SegmentStroke(PhotoPortrait.Stroke stroke,int width,int height){
            this.width=width;this.height=height;radius=stroke.radius*Math.min(width,height);feather=stroke.feather;erase=stroke.erase;double[] p=stroke.points();int n=p.length/2;
            ax=new double[n];ay=new double[n];vx=new double[n];vy=new double[n];length=new double[n];int[] ls=new int[n],rs=new int[n],ts=new int[n],bs=new int[n],counts=new int[GRID*GRID];double l=1,t=1,r=0,b=0;
            for(int i=0;i<n;i++){int j=i*2,k=Math.min(j+2,p.length-2);l=Math.min(l,p[j]);t=Math.min(t,p[j+1]);r=Math.max(r,p[j]);b=Math.max(b,p[j+1]);ax[i]=p[j]*width;ay[i]=p[j+1]*height;vx[i]=p[k]*width-ax[i];vy[i]=p[k+1]*height-ay[i];length[i]=vx[i]*vx[i]+vy[i]*vy[i];ls[i]=cell((Math.min(ax[i],ax[i]+vx[i])-radius)/width);rs[i]=cell((Math.max(ax[i],ax[i]+vx[i])+radius)/width);ts[i]=cell((Math.min(ay[i],ay[i]+vy[i])-radius)/height);bs[i]=cell((Math.max(ay[i],ay[i]+vy[i])+radius)/height);for(int y=ts[i];y<=bs[i];y++)for(int x=ls[i];x<=rs[i];x++)counts[y*GRID+x]++;}
            left=l-radius/width;top=t-radius/height;right=r+radius/width;bottom=b+radius/height;starts=new int[GRID*GRID+1];for(int i=0;i<counts.length;i++)starts[i+1]=starts[i]+counts[i];segments=new int[starts[GRID*GRID]];int[] cursor=starts.clone();
            for(int i=0;i<n;i++)for(int y=ts[i];y<=bs[i];y++)for(int x=ls[i];x<=rs[i];x++)segments[cursor[y*GRID+x]++]=i;
            workingBytes=40L*n+4L*(starts.length+segments.length)+512;
        }
        double weight(double nx,double ny){if(nx<left||nx>right||ny<top||ny>bottom)return 0;double x=nx*width,y=ny*height,distance=Double.POSITIVE_INFINITY;int cell=cell(ny)*GRID+cell(nx);for(int j=starts[cell];j<starts[cell+1];j++){int i=segments[j];double t=length[i]==0?0:Math.max(0,Math.min(1,((x-ax[i])*vx[i]+(y-ay[i])*vy[i])/length[i]));double dx=x-ax[i]-t*vx[i],dy=y-ay[i]-t*vy[i];distance=Math.min(distance,dx*dx+dy*dy);}return PhotoLocalEdits.Mask.falloff(Math.sqrt(distance)/radius,feather);}
        private static int cell(double v){return Math.max(0,Math.min(GRID-1,(int)Math.floor(v*GRID)));}
    }
}
