package cc.huevia.ncp;

import java.io.DataInput;
import java.io.DataOutput;
import java.io.IOException;
import java.util.Objects;

/** Independent, reversible body warps in the EXIF-oriented, uncropped source frame. */
public final class PhotoBodyShape {
    public static final int BODY=0, LEGS=1, LENGTH=2;
    public static final PhotoBodyShape NONE=new PhotoBodyShape(
            new Area(.25,.25,.75,.90,0),new Area(.30,.50,.70,.94,0),new Area(.23,.48,.77,.90,0),false);
    public final Area body,legs,length;
    public final boolean singleLeg;
    public final PhotoPortrait.BodySkinMask backgroundMask;
    public final int backgroundProtection;
    public PhotoBodyShape(Area body,Area legs,Area length,boolean singleLeg){this(body,legs,length,singleLeg,null,0);}
    public PhotoBodyShape(Area body,Area legs,Area length,boolean singleLeg,PhotoPortrait.BodySkinMask backgroundMask,int protection){
        if(protection<0||protection>100)throw new IllegalArgumentException("背景保护强度无效。");this.backgroundMask=backgroundMask;this.backgroundProtection=protection;
        this.body=Objects.requireNonNull(body);this.legs=Objects.requireNonNull(legs);this.length=Objects.requireNonNull(length);this.singleLeg=singleLeg;
        if(length.bottom>.97)throw new IllegalArgumentException("腿部拉长需要在脚下留出空间。");
    }
    public Area area(int tool){switch(tool){case BODY:return body;case LEGS:return legs;case LENGTH:return length;default:throw new IllegalArgumentException("塑形工具无效。");}}
    public PhotoBodyShape withArea(int tool,Area value){Objects.requireNonNull(value);return new PhotoBodyShape(tool==BODY?value:body,tool==LEGS?value:legs,tool==LENGTH?value:length,singleLeg,backgroundMask,backgroundProtection).validateTool(tool);}
    private PhotoBodyShape validateTool(int tool){area(tool);return this;}
    public PhotoBodyShape withSingleLeg(boolean value){return new PhotoBodyShape(body,legs,length,value,backgroundMask,backgroundProtection);}
    public PhotoBodyShape withBackgroundProtection(PhotoPortrait.BodySkinMask mask,int amount){return new PhotoBodyShape(body,legs,length,singleLeg,mask,amount);}
    public boolean hasProtectionState(){return backgroundMask!=null||backgroundProtection!=0;}
    public boolean isNeutral(){return body.amount==0&&legs.amount==0&&length.amount==0;}
    public boolean hasStoredState(){return !equals(NONE);}
    public void write(DataOutput out)throws IOException{for(Area a:new Area[]{body,legs,length}){out.writeDouble(a.left);out.writeDouble(a.top);out.writeDouble(a.right);out.writeDouble(a.bottom);out.writeInt(a.amount);}out.writeBoolean(singleLeg);}
    public static PhotoBodyShape read(DataInput in)throws IOException{
        try{Area[] a=new Area[3];for(int i=0;i<3;i++)a[i]=new Area(in.readDouble(),in.readDouble(),in.readDouble(),in.readDouble(),in.readInt());int single=in.readUnsignedByte();if(single>1)throw new IOException("塑形模式无效。");return new PhotoBodyShape(a[0],a[1],a[2],single==1);}catch(IllegalArgumentException|NullPointerException invalid){throw new IOException("塑形范围或强度无效。",invalid);}
    }
    @Override public boolean equals(Object o){if(!(o instanceof PhotoBodyShape))return false;PhotoBodyShape s=(PhotoBodyShape)o;return body.equals(s.body)&&legs.equals(s.legs)&&length.equals(s.length)&&singleLeg==s.singleLeg&&backgroundProtection==s.backgroundProtection&&Objects.equals(backgroundMask,s.backgroundMask);}
    @Override public int hashCode(){return hasProtectionState()?Objects.hash(body,legs,length,singleLeg,backgroundMask,backgroundProtection):Objects.hash(body,legs,length,singleLeg);}
    public static final class Area {
        public final double left,top,right,bottom;
        public final int amount;
        public Area(double left,double top,double right,double bottom,int amount){
            if(!Double.isFinite(left)||!Double.isFinite(top)||!Double.isFinite(right)||!Double.isFinite(bottom)||left<0||top<0||right>1||bottom>1||right-left<.06||bottom-top<.08||amount<0||amount>100)throw new IllegalArgumentException("塑形范围或强度无效。");
            this.left=left==0?0:left;this.top=top==0?0:top;this.right=right;this.bottom=bottom;this.amount=amount;
        }
        public Area withAmount(int value){return new Area(left,top,right,bottom,value);}
        @Override public boolean equals(Object o){if(!(o instanceof Area))return false;Area a=(Area)o;return left==a.left&&top==a.top&&right==a.right&&bottom==a.bottom&&amount==a.amount;}
        @Override public int hashCode(){return Objects.hash(left,top,right,bottom,amount);}
    }
}
