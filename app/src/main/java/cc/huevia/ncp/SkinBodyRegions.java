package cc.huevia.ncp;

import java.io.IOException;
import java.util.Arrays;
import java.util.function.BooleanSupplier;

/** Assigns connected person foreground to face seeds; unseeded people stay untouched. */
public final class SkinBodyRegions {
    private SkinBodyRegions(){}
    public static int[] owners(byte[] categories,int size,double[] seedXY,BooleanSupplier cancel)throws IOException{
        if(size<1||size>512||categories==null||categories.length!=size*size||seedXY==null
                ||(seedXY.length&1)!=0||seedXY.length>PhotoPortrait.MAX_FACES*2||cancel==null)
            throw new IllegalArgumentException("身体皮肤选区参数无效。");
        for(byte c:categories)if(c<0||c>5)throw new IllegalArgumentException("皮肤分类无效。");
        for(double n:seedXY)if(!Double.isFinite(n)||n<0||n>1)throw new IllegalArgumentException("人物位置无效。");
        int[] owner=new int[categories.length],queue=new int[categories.length];Arrays.fill(owner,-1);int tail=0;
        int radius=Math.max(2,(int)Math.ceil(size*.047));
        for(int face=0;face<seedXY.length/2;face++){
            check(cancel);double sx=seedXY[face*2]*size-.5,sy=seedXY[face*2+1]*size-.5;
            int cx=(int)Math.round(sx),cy=(int)Math.round(sy),best=-1;double distance=Double.POSITIVE_INFINITY;
            for(int y=Math.max(0,cy-radius);y<=Math.min(size-1,cy+radius);y++)for(int x=Math.max(0,cx-radius);x<=Math.min(size-1,cx+radius);x++){
                int i=y*size+x;double d=(x-sx)*(x-sx)+(y-sy)*(y-sy);
                if(owner[i]<0&&person(categories[i])&&d<distance){best=i;distance=d;}
            }
            if(best>=0){owner[best]=face;queue[tail++]=best;}
        }
        for(int head=0;head<tail;head++){
            if((head&255)==0)check(cancel);int i=queue[head],x=i%size,y=i/size;
            if(x>0)tail=visit(i-1,owner[i],categories,owner,queue,tail);
            if(x+1<size)tail=visit(i+1,owner[i],categories,owner,queue,tail);
            if(y>0)tail=visit(i-size,owner[i],categories,owner,queue,tail);
            if(y+1<size)tail=visit(i+size,owner[i],categories,owner,queue,tail);
        }
        check(cancel);return owner;
    }
    private static int visit(int i,int face,byte[] categories,int[] owner,int[] queue,int tail){
        if(owner[i]<0&&person(categories[i])){owner[i]=face;queue[tail++]=i;}return tail;
    }
    private static boolean person(byte category){return category>=1&&category<=4;}
    private static void check(BooleanSupplier cancel)throws IOException{
        if(cancel.getAsBoolean()||Thread.currentThread().isInterrupted())throw new IOException("身体皮肤识别已取消。");
    }
}
