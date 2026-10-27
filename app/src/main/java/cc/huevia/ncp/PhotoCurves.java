package cc.huevia.ncp;

import java.io.*;
import java.util.Arrays;

/** Immutable sRGB point curves. Shape-preserving cubic interpolation avoids overshoot. */
public final class PhotoCurves {
    public static final int CHANNELS=4, MAX_POINTS=12;
    public static final String MODEL="photo-point-curves-pchip-v1";
    public static final PhotoCurves NONE=new PhotoCurves(new int[][]{{0,0,255,255},{0,0,255,255},{0,0,255,255},{0,0,255,255}});
    private final int[][] points;
    private final int changed;
    private final double[][] lut=new double[CHANNELS][256];
    public PhotoCurves(int[][] source){
        if(source==null||source.length!=CHANNELS)throw new IllegalArgumentException("曲线通道不完整。");
        points=new int[CHANNELS][];
        int count=0;for(int c=0;c<CHANNELS;c++){
            int[] p=source[c];
            if(p==null||p.length<4||p.length>MAX_POINTS*2||p.length%2!=0||p[0]!=0||p[p.length-2]!=255)throw new IllegalArgumentException("曲线端点无效。");
            for(int i=0;i<p.length;i+=2)if(p[i]<0||p[i]>255||p[i+1]<0||p[i+1]>255||i>0&&p[i]<=p[i-2])throw new IllegalArgumentException("曲线控制点无效。");
            points[c]=p.clone();build(c);
            if(!channelNeutral(c))count++;
        }
        changed=count;
    }
    public int[] points(int channel){checkChannel(channel);return points[channel].clone();}
    public PhotoCurves withPoints(int channel,int[] next){checkChannel(channel);int[][] copy=points.clone();copy[channel]=next;return new PhotoCurves(copy);}
    public PhotoCurves reset(int channel){return withPoints(channel,NONE.points(channel));}
    public boolean channelNeutral(int channel){checkChannel(channel);int[] p=points[channel];for(int i=0;i<p.length;i+=2)if(p[i]!=p[i+1])return false;return true;}
    public int count(){return changed;}
    public boolean isNeutral(){return count()==0;}
    public double map(int channel,double value){checkChannel(channel);double x=Math.max(0,Math.min(1,value))*255;int a=(int)x;return (lut[channel][a]+(lut[channel][Math.min(255,a+1)]-lut[channel][a])*(x-a))/255;}
    public String identity(){StringBuilder s=new StringBuilder(MODEL);for(int[] p:points){s.append('/');for(int v:p)s.append(v).append(',');}return s.toString();}
    public void write(DataOutput out)throws IOException{out.writeUTF(MODEL);for(int[] p:points){out.writeInt(p.length);for(int v:p)out.writeInt(v);}}
    public static PhotoCurves read(DataInput in)throws IOException{if(!MODEL.equals(in.readUTF()))throw new IOException("曲线版本不支持。");int[][] p=new int[CHANNELS][];for(int c=0;c<CHANNELS;c++){int n=in.readInt();if(n<4||n>MAX_POINTS*2||n%2!=0)throw new IOException("曲线数据损坏。");p[c]=new int[n];for(int i=0;i<n;i++)p[c][i]=in.readInt();}try{return new PhotoCurves(p);}catch(IllegalArgumentException e){throw new IOException("曲线数据损坏。",e);}}
    private void build(int channel){
        int[] p=points[channel];int n=p.length/2;double[] d=new double[n-1],h=new double[n-1],m=new double[n];
        for(int i=0;i<n-1;i++){h[i]=p[(i+1)*2]-p[i*2];d[i]=(p[(i+1)*2+1]-p[i*2+1])/h[i];}
        m[0]=d[0];m[n-1]=d[n-2];
        for(int i=1;i<n-1;i++){if(d[i-1]*d[i]<=0)m[i]=0;else{double w1=2*h[i]+h[i-1],w2=h[i]+2*h[i-1];m[i]=(w1+w2)/(w1/d[i-1]+w2/d[i]);}}
        int part=0;
        for(int x=0;x<256;x++){
            while(part<n-2&&x>p[(part+1)*2])part++;
            double t=(x-p[part*2])/h[part],t2=t*t,t3=t2*t;
            double y=(2*t3-3*t2+1)*p[part*2+1]+(t3-2*t2+t)*h[part]*m[part]+(-2*t3+3*t2)*p[(part+1)*2+1]+(t3-t2)*h[part]*m[part+1];
            lut[channel][x]=Math.max(0,Math.min(255,y));
        }
    }
    private static void checkChannel(int c){if(c<0||c>=CHANNELS)throw new IllegalArgumentException("曲线通道无效。");}
    @Override public boolean equals(Object value){return value instanceof PhotoCurves&&Arrays.deepEquals(points,((PhotoCurves)value).points);}
    @Override public int hashCode(){return Arrays.deepHashCode(points);}
}
