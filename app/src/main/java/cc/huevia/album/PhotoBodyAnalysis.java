package cc.huevia.album;
import android.content.Context;
import android.graphics.Bitmap;
import cc.huevia.ncp.*;
import java.io.*;
import java.util.*;
import java.util.function.BooleanSupplier;

/** Person-silhouette range suggestions and frozen long-background-edge protection. */
public final class PhotoBodyAnalysis {
    public static final class Person {public final double left,top,right,bottom,shoulder;public final boolean legsVisible;Person(int l,int t,int r,int b,int n,List<PhotoPortrait.Face> faces){left=l/(double)n;top=t/(double)n;right=(r+1.0)/n;bottom=(b+1.0)/n;PhotoPortrait.Face head=null;for(PhotoPortrait.Face f:faces)if(f.cx>=left&&f.cx<=right&&f.cy>=top&&f.cy<=bottom&&(head==null||f.rx*f.ry>head.rx*head.ry))head=f;shoulder=head==null?top+(bottom-top)*.22:Math.max(top+(bottom-top)*.18,head.cy+head.ry*1.15);legsVisible=head==null?(bottom-top)>(right-left)*1.7:bottom-top>head.ry*8;}}
    public static final class Result {public final List<Person> people;public final PhotoPortrait.BodySkinMask protection;Result(List<Person> p,PhotoPortrait.BodySkinMask mask){people=Collections.unmodifiableList(p);protection=mask;}}
    private PhotoBodyAnalysis(){}
    public static Result analyze(Context context,Bitmap image,BooleanSupplier cancel)throws IOException{
        PhotoPersonAnalysis.Result input=PhotoPersonAnalysis.analyze(context,image,cancel);int n=PhotoPortrait.BodySkinMask.SIZE;byte[] person=input.person.copyCoverage();boolean[] seen=new boolean[n*n];int[] queue=new int[n*n];ArrayList<Person> people=new ArrayList<>();
        for(int i=0;i<person.length;i++){check(cancel);if(seen[i]||(person[i]&255)<140)continue;int head=0,tail=0,l=n,t=n,r=0,b=0;queue[tail++]=i;seen[i]=true;while(head<tail){int p=queue[head++],x=p%n,y=p/n;l=Math.min(l,x);r=Math.max(r,x);t=Math.min(t,y);b=Math.max(b,y);for(int next:new int[]{x>0?p-1:-1,x+1<n?p+1:-1,y>0?p-n:-1,y+1<n?p+n:-1})if(next>=0&&!seen[next]&&(person[next]&255)>=140){seen[next]=true;queue[tail++]=next;}}if(tail>n*n*.008&&b-t>n*.12&&r-l>n*.04)people.add(new Person(l,t,r,b,n,input.faces));}
        people.sort((a,b)->Double.compare((b.right-b.left)*(b.bottom-b.top),(a.right-a.left)*(a.bottom-a.top)));if(people.size()>12)people.subList(12,people.size()).clear();
        int[] luma=new int[n*n];for(int y=0;y<n;y++){check(cancel);for(int x=0;x<n;x++){int q=image.getPixel(Math.min(image.getWidth()-1,(int)((x+.5)/n*image.getWidth())),Math.min(image.getHeight()-1,(int)((y+.5)/n*image.getHeight())));luma[y*n+x]=(int)(.2126*((q>>>16)&255)+.7152*((q>>>8)&255)+.0722*(q&255));}}
        byte[] edge=new byte[n*n];for(int y=2;y<n-2;y++){check(cancel);for(int x=2;x<n-2;x++){int i=y*n+x;if((person[i]&255)>60)continue;boolean vertical=Math.abs(luma[i+1]-luma[i-1])>34,horizontal=Math.abs(luma[i+n]-luma[i-n])>34;if(!vertical&&!horizontal)continue;int count=0;for(int k=-12;k<=12;k++){int xx=horizontal?Math.max(1,Math.min(n-2,x+k)):x,yy=vertical?Math.max(1,Math.min(n-2,y+k)):y,j=yy*n+xx;if((person[j]&255)<80&&(vertical?Math.abs(luma[j+1]-luma[j-1]):Math.abs(luma[j+n]-luma[j-n]))>24)count++;}if(count>=17)edge[i]=(byte)255;}}
        float[] expanded=new float[n*n];int radius=24;for(int y=0;y<n;y++){check(cancel);for(int x=0;x<n;x++){double best=0;for(int k=-radius;k<=radius;k++){int xx=x+k;if(xx>=0&&xx<n&&(edge[y*n+xx]&255)>0){double v=1-Math.abs(k)/(double)radius;best=Math.max(best,v*v*(3-2*v));}}expanded[y*n+x]=(float)best;}}
        byte[] protection=new byte[n*n];for(int y=0;y<n;y++){check(cancel);for(int x=0;x<n;x++){double best=expanded[y*n+x];for(int k=-radius;k<=radius;k++){int yy=y+k;if(yy<0||yy>=n)continue;double v=1-Math.abs(k)/(double)radius;best=Math.max(best,expanded[yy*n+x]*v*v*(3-2*v));}protection[y*n+x]=(byte)Math.round(255*best);}}
        return new Result(people,new PhotoPortrait.BodySkinMask(protection));
    }
    public static PhotoBodyShape locate(PhotoBodyShape current,Person p){double width=p.right-p.left,height=p.bottom-p.top;double l=Math.max(0,p.left-width*.04),r=Math.min(1,p.right+width*.04),upper=Math.min(p.bottom-.12,p.shoulder),waist=p.top+height*.58,feet=Math.min(.96,p.bottom);if(r-l<.08||feet-upper<.14)return current;PhotoBodyShape out=current.withArea(0,new PhotoBodyShape.Area(l,upper,r,Math.max(upper+.1,feet),current.body.amount));if(!p.legsVisible)return out;double legTop=Math.min(feet-.1,waist);out=out.withArea(1,new PhotoBodyShape.Area(l,legTop,r,feet,current.legs.amount));return out.withArea(2,new PhotoBodyShape.Area(l,legTop,r,feet,current.length.amount));}
    private static void check(BooleanSupplier c)throws InterruptedIOException{if(Thread.currentThread().isInterrupted()||c.getAsBoolean())throw new InterruptedIOException("人体定位已取消。");}
}
