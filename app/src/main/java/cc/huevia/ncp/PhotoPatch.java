package cc.huevia.ncp;

import java.io.*;
import java.util.*;

/** Source-photo selection plus a frozen automatic or user-chosen clean donor translation. */
public final class PhotoPatch {
    public final AdjustmentRegion selection;
    public final double dx,dy,blend;
    public final boolean enabled,contextBlend;

    public PhotoPatch(AdjustmentRegion selection,double dx,double dy,double blend,boolean enabled){
        this(selection,dx,dy,blend,enabled,false);
    }
    private PhotoPatch(AdjustmentRegion selection,double dx,double dy,double blend,boolean enabled,boolean contextBlend){
        if(selection==null||!selection.adjustments.equals(PhotoAdjustments.NONE)||!selection.portrait.equals(PhotoPortrait.NONE)
                ||!selection.skinSettings.equals(PhotoPortrait.Settings.NONE)||selection.skinMask!=null||!selection.enabled||selection.amount!=1)
            throw new IllegalArgumentException("修补选区无效。");
        if(!Double.isFinite(dx)||!Double.isFinite(dy)||Math.abs(dx)>1||Math.abs(dy)>1||!Double.isFinite(blend)||blend<0||blend>1)
            throw new IllegalArgumentException("修补取样参数无效。");
        this.selection=selection;this.dx=dx==0?0:dx;this.dy=dy==0?0:dy;this.blend=blend==0?0:blend;this.enabled=enabled;this.contextBlend=contextBlend;
    }
    public static PhotoPatch create(AdjustmentRegion selection){return new PhotoPatch(selection,0,0,1,true);}
    public PhotoPatch sample(double x,double y){return new PhotoPatch(selection,x,y,blend,enabled,contextBlend);}
    public PhotoPatch blend(double value){return new PhotoPatch(selection,dx,dy,value,enabled,contextBlend);}
    public PhotoPatch selection(AdjustmentRegion value){return new PhotoPatch(value,dx,dy,blend,enabled,contextBlend);}
    public PhotoPatch enabled(boolean value){return new PhotoPatch(selection,dx,dy,blend,value,contextBlend);}
    public PhotoPatch contextBlend(boolean value){return new PhotoPatch(selection,dx,dy,blend,enabled,value);}
    public PhotoPatch feather(double value){
        ArrayList<PhotoPortrait.Stroke> strokes=new ArrayList<>();
        for(PhotoPortrait.Stroke s:selection.strokes)strokes.add(new PhotoPortrait.Stroke(s.points(),s.radius,value,s.erase));
        ArrayList<SelectionShape> shapes=new ArrayList<>();for(SelectionShape s:selection.shapes)shapes.add(s.feather(value));
        return selection(selection.withStrokes(strokes).withShapes(shapes));
    }
    public double feather(){return !selection.shapes.isEmpty()?selection.shapes.get(selection.shapes.size()-1).feather:!selection.strokes.isEmpty()?selection.strokes.get(selection.strokes.size()-1).feather:.2;}
    public boolean hasEffect(){return enabled&&selection.hasSelection()&&(dx!=0||dy!=0);}
    void write(DataOutput out)throws IOException{write(out,false);}
    void write(DataOutput out,boolean extended)throws IOException{if(contextBlend&&!extended)throw new IOException("局部背景融合需要新版修补格式。");selection.write(out,true,true,true);out.writeDouble(dx);out.writeDouble(dy);out.writeDouble(blend);out.writeBoolean(enabled);if(extended)out.writeBoolean(contextBlend);}
    static PhotoPatch read(DataInput in)throws IOException{return read(in,false);}
    static PhotoPatch read(DataInput in,boolean extended)throws IOException{AdjustmentRegion region=AdjustmentRegion.read(in,true,true,true);double dx=in.readDouble(),dy=in.readDouble(),blend=in.readDouble();boolean enabled=in.readBoolean();int mode=extended?in.readUnsignedByte():0;if(mode>1)throw new IOException("修补融合方式无效。");return new PhotoPatch(region,dx,dy,blend,enabled,mode==1);}
    @Override public boolean equals(Object o){if(!(o instanceof PhotoPatch))return false;PhotoPatch p=(PhotoPatch)o;return selection.equals(p.selection)&&dx==p.dx&&dy==p.dy&&blend==p.blend&&enabled==p.enabled&&contextBlend==p.contextBlend;}
    @Override public int hashCode(){return Objects.hash(selection,dx,dy,blend,enabled,contextBlend);}
}
