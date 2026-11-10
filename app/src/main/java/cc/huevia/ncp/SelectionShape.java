package cc.huevia.ncp;

import java.util.Objects;

/** Ordered geometric coverage in the oriented source frame; ellipse also represents a circle. */
public final class SelectionShape {
    public enum Kind { ELLIPSE, RECTANGLE }
    public final Kind kind;
    public final double left,top,right,bottom,feather;
    public final boolean subtract;
    /** Apply after this many brush strokes, before any later strokes. */
    public final int strokeIndex;

    public SelectionShape(Kind kind,double left,double top,double right,double bottom,double feather,boolean subtract,int strokeIndex){
        this.kind=Objects.requireNonNull(kind,"kind");
        if(!valid(left)||!valid(top)||!valid(right)||!valid(bottom)||right-left<.0001||bottom-top<.0001
                ||!valid(feather)||strokeIndex<0||strokeIndex>AdjustmentRegion.MAX_STROKES)
            throw new IllegalArgumentException("形状选区参数无效。");
        this.left=left==0?0:left;this.top=top==0?0:top;this.right=right;this.bottom=bottom;this.feather=feather==0?0:feather;
        this.subtract=subtract;this.strokeIndex=strokeIndex;
    }
    private static boolean valid(double value){return Double.isFinite(value)&&value>=0&&value<=1;}
    public SelectionShape bounds(double l,double t,double r,double b){return new SelectionShape(kind,l,t,r,b,feather,subtract,strokeIndex);}
    public SelectionShape feather(double value){return new SelectionShape(kind,left,top,right,bottom,value,subtract,strokeIndex);}
    public SelectionShape afterStroke(int value){return new SelectionShape(kind,left,top,right,bottom,feather,subtract,value);}
    public double weight(double x,double y){
        double dx=(x-(left+right)/2)/((right-left)/2),dy=(y-(top+bottom)/2)/((bottom-top)/2);
        return PhotoLocalEdits.Mask.falloff(kind==Kind.ELLIPSE?Math.hypot(dx,dy):Math.max(Math.abs(dx),Math.abs(dy)),feather);
    }
    @Override public boolean equals(Object other){if(!(other instanceof SelectionShape))return false;SelectionShape s=(SelectionShape)other;return kind==s.kind&&left==s.left&&top==s.top&&right==s.right&&bottom==s.bottom&&feather==s.feather&&subtract==s.subtract&&strokeIndex==s.strokeIndex;}
    @Override public int hashCode(){return Objects.hash(kind,left,top,right,bottom,feather,subtract,strokeIndex);}
}
