package cc.huevia.ncp;

import java.util.Objects;

/** Immutable, source-independent crop in the oriented/rotated frame. No source pixels are changed. */
public final class PhotoGeometry {
    public static final int UNIT=1_000_000;
    public static final String MODEL="photo-composition-affine-v1";
    public static final String PERSPECTIVE_MODEL="photo-composition-projective-v2";
    public static final String MIRROR_MODEL="photo-composition-mirror-v3";
    public static final PhotoGeometry NONE=new PhotoGeometry(0,0,0,0,UNIT,UNIT);
    public final int turns,angle,left,top,right,bottom,horizontalPerspective,verticalPerspective;
    public final boolean mirrored;
    public PhotoGeometry(int turns,int angle,int left,int top,int right,int bottom){
        this(turns,angle,left,top,right,bottom,0,0);
    }
    public PhotoGeometry(int turns,int angle,int left,int top,int right,int bottom,int horizontalPerspective,int verticalPerspective){
        this(turns,angle,left,top,right,bottom,horizontalPerspective,verticalPerspective,false);
    }
    public PhotoGeometry(int turns,int angle,int left,int top,int right,int bottom,int horizontalPerspective,int verticalPerspective,boolean mirrored){
        if(turns<0||turns>3||angle< -450||angle>450||left<0||top<0||right>UNIT||bottom>UNIT||right<=left||bottom<=top||horizontalPerspective< -100||horizontalPerspective>100||verticalPerspective< -100||verticalPerspective>100)
            throw new IllegalArgumentException("构图参数无效。");
        this.turns=turns;this.angle=angle;this.left=left;this.top=top;this.right=right;this.bottom=bottom;this.horizontalPerspective=horizontalPerspective;this.verticalPerspective=verticalPerspective;this.mirrored=mirrored;
    }
    public boolean isNeutral(){return equals(NONE);}
    public PhotoGeometry fullFrame(){return new PhotoGeometry(turns,angle,0,0,UNIT,UNIT,horizontalPerspective,verticalPerspective,mirrored);}
    public PhotoGeometry rotate(){return new PhotoGeometry((turns+1)%4,angle,0,0,UNIT,UNIT,horizontalPerspective,verticalPerspective,mirrored);}
    public PhotoGeometry straighten(int value){return new PhotoGeometry(turns,value,left,top,right,bottom,horizontalPerspective,verticalPerspective,mirrored);}
    public PhotoGeometry perspective(int horizontal,int vertical){return new PhotoGeometry(turns,angle,left,top,right,bottom,horizontal,vertical,mirrored);}
    public PhotoGeometry crop(double l,double t,double r,double b){return new PhotoGeometry(turns,angle,quantize(l),quantize(t),quantize(r),quantize(b),horizontalPerspective,verticalPerspective,mirrored);}
    /** Reflect the selected photograph, preserving the same source region and reversibility. */
    public PhotoGeometry flipHorizontal(){return new PhotoGeometry(turns,angle,UNIT-right,top,UNIT-left,bottom,horizontalPerspective,verticalPerspective,!mirrored);}
    private static int quantize(double v){if(!Double.isFinite(v))throw new IllegalArgumentException("裁剪位置无效。");return (int)Math.round(v*UNIT);}
    public boolean hasPerspective(){return horizontalPerspective!=0||verticalPerspective!=0;}
    public String identity(){String value=(mirrored?MIRROR_MODEL:hasPerspective()?PERSPECTIVE_MODEL:MODEL)+":"+turns+":"+angle+":"+left+":"+top+":"+right+":"+bottom;return hasPerspective()||mirrored?value+":"+horizontalPerspective+":"+verticalPerspective:value;}
    public String label(){return isNeutral()?"未构图":"已构图"+(turns==0?"":" · 旋转 "+turns*90+"°")+(angle==0?"":" · 拉直 "+String.format(java.util.Locale.ROOT,"%.1f°",angle/10.0))+(hasPerspective()?" · 透视":"")+(mirrored?" · 水平翻转":"");}
    @Override public boolean equals(Object other){if(!(other instanceof PhotoGeometry))return false;PhotoGeometry g=(PhotoGeometry)other;return turns==g.turns&&angle==g.angle&&left==g.left&&top==g.top&&right==g.right&&bottom==g.bottom&&horizontalPerspective==g.horizontalPerspective&&verticalPerspective==g.verticalPerspective&&mirrored==g.mirrored;}
    @Override public int hashCode(){return Objects.hash(turns,angle,left,top,right,bottom,horizontalPerspective,verticalPerspective,mirrored);}
    /** Edge-coordinate map; caller filters pixels once, then applies this composition. */
    public Plan plan(int width,int height,int exif){
        if(width<1||height<1||width>65535||height>65535||exif<1||exif>8)throw new IllegalArgumentException("照片尺寸或方向无效。");
        int ow=exif>=5?height:width,oh=exif>=5?width:height;
        int bw=turns%2==0?ow:oh,bh=turns%2==0?oh:ow;
        int l=(int)Math.round(left/(double)UNIT*bw),t=(int)Math.round(top/(double)UNIT*bh);
        l=Math.min(l,bw-1);t=Math.min(t,bh-1);
        int r=Math.max(l+1,Math.min(bw,(int)Math.round(right/(double)UNIT*bw)));
        int b=Math.max(t+1,Math.min(bh,(int)Math.round(bottom/(double)UNIT*bh)));
        // Complement rounded source edges, rather than rounding their complements: half-pixel
        // crops must retain the identical selected source region when reflected twice.
        if(mirrored){l=Math.min(bw-1,bw-(int)Math.round((UNIT-left)/(double)UNIT*bw));r=Math.max(l+1,Math.min(bw,bw-(int)Math.round((UNIT-right)/(double)UNIT*bw)));}
        double[] p=point(0,0,width,height,exif,bw,bh),x=point(width,0,width,height,exif,bw,bh),y=point(0,height,width,height,exif,bw,bh);
        if(!hasPerspective())return mirrorPlan(new Plan(r-l,b-t,bw,bh,(x[0]-p[0])/width,(y[0]-p[0])/height,p[0]-l,(x[1]-p[1])/width,(y[1]-p[1])/height,p[1]-t),l);
        // A genuine homography after the affine frame. Its positive denominator never crosses
        // the frame; the uniform fill zoom keeps all destination corners inside the source.
        double hp=horizontalPerspective*.004,vp=verticalPerspective*.004,k=1-(hp+vp)/2,z=1+(Math.abs(hp)+Math.abs(vp))/2;
        double[] perspective={z+hp/2,bw*vp/(2.0*bh),bw*(k-z)/2,bh*hp/(2.0*bw),z+vp/2,bh*(k-z)/2,hp/bw,vp/bh,k};
        double[] affine={(x[0]-p[0])/width,(y[0]-p[0])/height,p[0],(x[1]-p[1])/width,(y[1]-p[1])/height,p[1],0,0,1};
        double[] m=multiply(perspective,affine);for(int i=0;i<3;i++){m[i]-=l*m[i+6];m[i+3]-=t*m[i+6];}
        return mirrorPlan(new Plan(r-l,b-t,bw,bh,m),l);
    }
    private Plan mirrorPlan(Plan plan,int cropLeft){if(!mirrored)return plan;double edge=plan.frameWidth-2.0*cropLeft;return new Plan(plan.width,plan.height,plan.frameWidth,plan.frameHeight,new double[]{edge*plan.g-plan.a,edge*plan.h-plan.b,edge-plan.c,plan.d,plan.e,plan.f,plan.g,plan.h,1});}
    private static double[] multiply(double[] a,double[] b){double[] out=new double[9];for(int row=0;row<3;row++)for(int col=0;col<3;col++)for(int i=0;i<3;i++)out[row*3+col]+=a[row*3+i]*b[i*3+col];return out;}
    private double[] point(double x,double y,int w,int h,int exif,int bw,int bh){
        double ox=x,oy=y;int ow=exif>=5?h:w,oh=exif>=5?w:h;
        switch(exif){case 2:ox=w-x;break;case 3:ox=w-x;oy=h-y;break;case 4:oy=h-y;break;case 5:ox=y;oy=x;break;case 6:ox=h-y;oy=x;break;case 7:ox=h-y;oy=w-x;break;case 8:ox=y;oy=w-x;break;}
        double tx=ox,ty=oy;
        switch(turns){case 1:tx=oh-oy;ty=ox;break;case 2:tx=ow-ox;ty=oh-oy;break;case 3:tx=oy;ty=ow-ox;break;}
        double radians=Math.toRadians(angle/10.0),c=Math.cos(radians),s=Math.sin(radians);
        // Rotate around centre and zoom just enough to cover all four frame corners.
        double zoom=c+Math.abs(s)*Math.max(bw/(double)bh,bh/(double)bw),dx=tx-bw/2.0,dy=ty-bh/2.0;
        return new double[]{bw/2.0+zoom*(c*dx-s*dy),bh/2.0+zoom*(s*dx+c*dy)};
    }
    public static final class Plan {
        public final int width,height,frameWidth,frameHeight;
        public final double a,b,c,d,e,f,g,h;
        Plan(int w,int h,int fw,int fh,double a,double b,double c,double d,double e,double f){this(w,h,fw,fh,new double[]{a,b,c,d,e,f,0,0,1});}
        Plan(int w,int h,int fw,int fh,double[] m){width=w;height=h;frameWidth=fw;frameHeight=fh;double k=m[8];if(!Double.isFinite(k)||Math.abs(k)<1e-12)throw new IllegalArgumentException("透视变换无效。");a=m[0]/k;b=m[1]/k;c=m[2]/k;d=m[3]/k;e=m[4]/k;f=m[5]/k;g=m[6]/k;this.h=m[7]/k;}
        public float[] matrix(){return new float[]{(float)a,(float)b,(float)c,(float)d,(float)e,(float)f,(float)g,(float)h,1};}
        public double[] map(double x,double y){double q=g*x+h*y+1;return new double[]{(a*x+b*y+c)/q,(d*x+e*y+f)/q};}
        public double[] inverse(double x,double y){if(g==0&&h==0){double det=a*e-b*d;return new double[]{(e*(x-c)-b*(y-f))/det,(-d*(x-c)+a*(y-f))/det};}double aa=a-x*g,bb=b-x*h,dd=d-y*g,ee=e-y*h,det=aa*ee-bb*dd;return new double[]{(ee*(x-c)-bb*(y-f))/det,(-dd*(x-c)+aa*(y-f))/det};}
    }
}
