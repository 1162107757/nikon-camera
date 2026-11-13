package cc.huevia.shared;

import cc.huevia.library.SharedJson;
import cc.huevia.ncp.*;
import java.io.*;
import java.util.*;
import java.util.function.BooleanSupplier;

/** Platform-neutral pre/postprocessing of the original 256px mesh and semantic models. */
public final class SharedPortraitInference {
    private static final int N=256,S=128,C=6;
    private static final int[] SEEDS={1,4,50,101,205,280,330,425,151,9,199};
    private SharedPortraitInference(){}
    public static String heal(String json,int[] pixels,int width,int height,BooleanSupplier cancel)throws IOException {
        validate(pixels,width,height);Map<String,Object> p=SharedJson.object(json);double tx=value(p,"x"),ty=value(p,"y"),radius=value(p,"radius");if(tx<0||tx>1||ty<0||ty>1||radius<.002||radius>.12)throw new IOException("祛痘范围无效。");double shortSide=Math.min(width,height),rx=radius*shortSide/width,ry=radius*shortSide/height,best=Double.POSITIVE_INFINITY,sx=tx,sy=ty;
        for(int ring=0;ring<3;ring++)for(int angle=0;angle<16;angle++){check(cancel);double a=2*Math.PI*angle/16,distance=2.6+ring*1.3,x=tx+Math.cos(a)*rx*distance,y=ty+Math.sin(a)*ry*distance;if(x-rx<0||x+rx>1||y-ry<0||y+ry>1)continue;double score=0;for(int j=0;j<16;j++){double b=2*Math.PI*j/16,ox=Math.cos(b)*rx*.9,oy=Math.sin(b)*ry*.9;int source=pixel(pixels,width,height,x+ox,y+oy),target=pixel(pixels,width,height,tx+ox,ty+oy);double dr=((source>>>16)&255)-((target>>>16)&255),dg=((source>>>8)&255)-((target>>>8)&255),db=(source&255)-(target&255);score+=dr*dr*.25+dg*dg*.5+db*db*.25;}score+=distance*distance*2;if(score<best){best=score;sx=x;sy=y;}}
        if(!Double.isFinite(best))throw new IOException("瑕疵太靠近边缘，请缩小修复范围。");PhotoLocalEdits local=SharedRetouch.local(p);return SharedRetouch.result(local.withPortrait(local.portrait.addHeal(new PhotoPortrait.Heal(sx,sy,tx,ty,radius,.7,true))),cancel);
    }
    private static double value(Map<String,Object> p,String key)throws IOException{Object v=p.get(key);if(!(v instanceof Number)||!Double.isFinite(((Number)v).doubleValue()))throw new IOException("祛痘参数无效。");return ((Number)v).doubleValue();}
    private static int pixel(int[] p,int w,int h,double x,double y){return p[Math.max(0,Math.min(h-1,(int)(y*h)))*w+Math.max(0,Math.min(w-1,(int)(x*w)))];}
    public static int sampleSkin(int[] pixels,int width,int height,String json)throws IOException {
        validate(pixels,width,height);PhotoPortrait.Face face=SharedRetouch.readFace(SharedJson.object(json));double[][] centers={{-.43,.03},{.43,.03},{0,-.69}};int[] red=new int[75],green=new int[75],blue=new int[75];int count=0;double cosine=Math.cos(Math.toRadians(face.roll)),sine=Math.sin(Math.toRadians(face.roll)),aspect=width/(double)height;
        for(double[] center:centers)for(int y=-2;y<=2;y++)for(int x=-2;x<=2;x++){double px=(center[0]+x*.035)*face.rx,py=(center[1]+y*.035)*face.ry,nx=face.cx+cosine*px-sine*py/aspect,ny=face.cy+sine*px*aspect+cosine*py;int rgb=pixels[Math.max(0,Math.min(height-1,(int)(ny*height)))*width+Math.max(0,Math.min(width-1,(int)(nx*width)))],r=(rgb>>>16)&255,g=(rgb>>>8)&255,b=rgb&255,l=(r*54+g*183+b*19)/256;if(l<12||l>248)continue;red[count]=r;green[count]=g;blue[count]=b;count++;}
        if(count==0)return pixels[Math.max(0,Math.min(height-1,(int)(face.cy*height)))*width+Math.max(0,Math.min(width-1,(int)(face.cx*width)))];Arrays.sort(red,0,count);Arrays.sort(green,0,count);Arrays.sort(blue,0,count);return 0xff000000|(red[count/2]<<16)|(green[count/2]<<8)|blue[count/2];
    }
    private static final class Crop {
        final double rx,ry,side,shift,cx,cy,cos,sin;
        Crop(PhotoPortrait.Face f,int w,int h){rx=f.rx*w;ry=f.ry*h;side=3.5*Math.max(rx,ry);shift=-.30*rx/.95;cos=Math.cos(Math.toRadians(f.roll));sin=Math.sin(Math.toRadians(f.roll));cx=f.cx*w-sin*shift;cy=f.cy*h+cos*shift;}
        double u(double x){return (x/N-.5)*side/rx;}double v(double y){return ((y/N-.5)*side+shift)/ry;}
    }
    public static float[] input(int[] pixels,int width,int height,String face,boolean semantic,BooleanSupplier cancel)throws IOException {
        validate(pixels,width,height);float[] out=new float[N*N*3];Crop crop=face==null||face.isEmpty()?null:new Crop(SharedRetouch.readFace(SharedJson.object(face)),width,height);
        double scale=Math.min(N/(double)width,N/(double)height),left=(N-width*scale)/2,top=(N-height*scale)/2;
        for(int y=0;y<N;y++){check(cancel);for(int x=0;x<N;x++){
            double sx,sy;if(crop==null){sx=(x+.5-left)/scale-.5;sy=(y+.5-top)/scale-.5;}else{double dx=(x+.5-N*.5)*crop.side/N,dy=(y+.5-N*.5)*crop.side/N;sx=crop.cx+crop.cos*dx-crop.sin*dy-.5;sy=crop.cy+crop.sin*dx+crop.cos*dy-.5;}
            int at=(y*N+x)*3;for(int channel=0;channel<3;channel++){double value=sample(pixels,width,height,sx,sy,16-channel*8);out[at+channel]=(float)(semantic?value/127.5-1:value/255);}
        }}return out;
    }
    public static String face(String json,int width,int height,float[] mesh,float presence,float[] semantic,BooleanSupplier cancel)throws IOException {
        if(mesh==null||mesh.length<468*3||!Float.isFinite(presence))throw new IOException("面部模型输出无效。");if(presence<0)return "";
        Map<String,Object> row=SharedJson.object(json);PhotoPortrait.Face face=SharedRetouch.readFace(row);Crop crop=new Crop(face,width,height);double[] points=new double[936];List<Object> encoded=new ArrayList<>();double minX=8,minY=8,maxX=-8,maxY=-8;
        for(int i=0;i<468;i++){check(cancel);double x=crop.u(mesh[i*3]),y=crop.v(mesh[i*3+1]);if(!Double.isFinite(x)||!Double.isFinite(y)||x< -8||x>8||y< -8||y>8)throw new IOException("面部关键点未能可靠定位。");points[i*2]=x;points[i*2+1]=y;encoded.add(x);encoded.add(y);minX=Math.min(minX,x);maxX=Math.max(maxX,x);minY=Math.min(minY,y);maxY=Math.max(maxY,y);}
        if(maxX-minX<.1||maxY-minY<.1)throw new IOException("面部关键点范围无效。");row.put("landmarks",encoded);
        if(semantic!=null){logits(semantic);float[] weights=new float[S*S];boolean[] candidate=new boolean[S*S],keep=new boolean[S*S];double[] score=new double[C];
            for(int y=0;y<S;y++){check(cancel);for(int x=0;x<S;x++){double amount=0;for(int dy=0;dy<2;dy++)for(int dx=0;dx<2;dx++){softmax(semantic,((2*y+dy)*N+2*x+dx)*C,score);double other=0;for(int k=0;k<C;k++)if(k!=3)other=Math.max(other,score[k]);if(score[3]>other){double margin=Math.min(1,(score[3]-other)/.25);amount+=margin*margin*(3-2*margin);}}int i=y*S+x;weights[i]=(float)(amount/4);candidate[i]=weights[i]>.01;}}
            double left=crop.u(0),top=crop.v(0),right=crop.u(N),bottom=crop.v(N);int[] queue=new int[S*S];int tail=0;
            for(int point:SEEDS){int cx=(int)((points[point*2]-left)/(right-left)*S),cy=(int)((points[point*2+1]-top)/(bottom-top)*S),chosen=-1,best=Integer.MAX_VALUE;for(int y=Math.max(0,cy-3);y<=Math.min(S-1,cy+3);y++)for(int x=Math.max(0,cx-3);x<=Math.min(S-1,cx+3);x++){int i=y*S+x,d=(x-cx)*(x-cx)+(y-cy)*(y-cy);if(candidate[i]&&d<best){chosen=i;best=d;}}if(chosen>=0&&!keep[chosen]){keep[chosen]=true;queue[tail++]=chosen;}}
            for(int head=0;head<tail;head++){check(cancel);int i=queue[head],cx=i%S,cy=i/S;for(int y=Math.max(0,cy-1);y<=Math.min(S-1,cy+1);y++)for(int x=Math.max(0,cx-1);x<=Math.min(S-1,cx+1);x++){int next=y*S+x;if(candidate[next]&&!keep[next]){keep[next]=true;queue[tail++]=next;}}}
            byte[] coverage=new byte[S*S];int covered=0;for(int i=0;i<coverage.length;i++)if(keep[i]){coverage[i]=(byte)Math.round(weights[i]*255);if((coverage[i]&255)>16)covered++;}
            if(covered<32)throw new IOException("未能确认面部皮肤，请重新识别。");row.put("skinMask",SharedRuntime.map("left",left,"top",top,"right",right,"bottom",bottom,"data",Base64.getEncoder().encodeToString(coverage)));
        }check(cancel);return SharedJson.encode(row);
    }
    public static String person(int[] pixels,int width,int height,float[] output,String facesJson,BooleanSupplier cancel)throws IOException {
        validate(pixels,width,height);logits(output);double scale=Math.min(N/(double)width,N/(double)height),w=width*scale,h=height*scale,left=(N-w)/2,top=(N-h)/2;float[] skin=new float[N*N],person=new float[N*N];double[] score=new double[C];
        for(int y=0;y<N;y++){check(cancel);for(int x=0;x<N;x++){if(x+.5<left||x+.5>=left+w||y+.5<top||y+.5>=top+h)continue;int i=y*N+x;softmax(output,i*C,score);person[i]=(float)(score[1]+score[2]+score[3]+score[4]);double p=score[2]+score[3],other=0;for(int c=0;c<C;c++)if(c!=2&&c!=3)other=Math.max(other,score[c]);if(p>other){double margin=Math.min(1,(p-other)/.25);skin[i]=(float)(margin*margin*(3-2*margin));}}}
        byte[] coverage=new byte[S*S],foreground=new byte[S*S];List<PhotoPortrait.Face> faces=new ArrayList<>();if(facesJson!=null&&!facesJson.isEmpty())for(Object row:(List<?>)SharedJson.object("{\"faces\":"+facesJson+"}").get("faces"))faces.add(SharedRetouch.readFace(SharedRuntime.object(row)));
        for(int y=0;y<S;y++){check(cancel);for(int x=0;x<S;x++){double gx=left+(x+.5)/S*w-.5,gy=top+(y+.5)/S*h-.5;int ix=(int)Math.floor(gx),iy=(int)Math.floor(gy);double tx=gx-ix,ty=gy-iy,weight=0,body=0;for(int dy=0;dy<2;dy++)for(int dx=0;dx<2;dx++){int sx=Math.max(0,Math.min(N-1,ix+dx)),sy=Math.max(0,Math.min(N-1,iy+dy));double k=(dx==0?1-tx:tx)*(dy==0?1-ty:ty);weight+=skin[sy*N+sx]*k;body+=person[sy*N+sx]*k;}double protection=1;for(PhotoPortrait.Face f:faces)protection=Math.min(protection,PortraitPreviewFilter.featureProtection(f,(x+.5)/S,(y+.5)/S,width,height));coverage[y*S+x]=(byte)Math.round(Math.min(1,weight)*protection*255);foreground[y*S+x]=(byte)Math.round(Math.min(1,Math.max(0,(body-.25)/.6))*255);}}
        for(PhotoPortrait.Face face:faces)if(face.skinMask!=null){PortraitPreviewFilter.Mask faceMask=PortraitPreviewFilter.mask(face,width,height);for(int y=0;y<S;y++){check(cancel);for(int x=0;x<S;x++){double nx=(x+.5)/S,ny=(y+.5)/S;if(!PortraitPreviewFilter.faceContains(face,nx,ny,width,height))continue;coverage[y*S+x]=(byte)Math.round(255*faceMask.weight(pixel(pixels,width,height,nx,ny),nx,ny));}}}
        // Original person component thresholds and head-relative body bounds.
        boolean[] seen=new boolean[S*S];int[] queue=new int[S*S];List<Map<String,Object>> people=new ArrayList<>();
        for(int i=0;i<foreground.length;i++){check(cancel);if(seen[i]||(foreground[i]&255)<140)continue;int head=0,tail=0,l=S,t=S,r=0,b=0;queue[tail++]=i;seen[i]=true;while(head<tail){int at=queue[head++],x=at%S,y=at/S;l=Math.min(l,x);r=Math.max(r,x);t=Math.min(t,y);b=Math.max(b,y);for(int next:new int[]{x>0?at-1:-1,x+1<S?at+1:-1,y>0?at-S:-1,y+1<S?at+S:-1})if(next>=0&&!seen[next]&&(foreground[next]&255)>=140){seen[next]=true;queue[tail++]=next;}}if(tail>S*S*.008&&b-t>S*.12&&r-l>S*.04){double bl=l/(double)S,bt=t/(double)S,br=(r+1.0)/S,bb=(b+1.0)/S,shoulder=bt+(bb-bt)*.22;PhotoPortrait.Face headFace=null;for(PhotoPortrait.Face f:faces)if(f.cx>=bl&&f.cx<=br&&f.cy>=bt&&f.cy<=bb&&(headFace==null||f.rx*f.ry>headFace.rx*headFace.ry))headFace=f;if(headFace!=null)shoulder=Math.max(bt+(bb-bt)*.18,headFace.cy+headFace.ry*1.15);Map<String,Object> candidate=SharedRuntime.map("left",Math.max(0,bl-(br-bl)*.04),"right",Math.min(1,br+(br-bl)*.04),"top",Math.min(bb-.12,shoulder),"bottom",Math.min(.96,bb),"legTop",Math.min(bb-.1,bt+(bb-bt)*.58),"legsVisible",headFace==null?(bb-bt)>(br-bl)*1.7:(bb-bt)>headFace.ry*8);people.add(candidate);}}
        people.sort((a,b)->Double.compare(area(b),area(a)));if(people.size()>12)people.subList(12,people.size()).clear();Map<String,Object> body=people.isEmpty()?null:people.get(0);
        return SharedJson.encode(SharedRuntime.map("skin",Base64.getEncoder().encodeToString(coverage),"foreground",Base64.getEncoder().encodeToString(foreground),"protection",Base64.getEncoder().encodeToString(protection(pixels,width,height,foreground,cancel)),"body",body,"people",people));
    }
    public static String isolate(String json,String allFaces,int width,int height,BooleanSupplier cancel)throws IOException {
        Map<String,Object> row=SharedJson.object(json);PhotoPortrait.Face face=SharedRetouch.readFace(row);if(face.skinMask==null)return json;List<PhotoPortrait.Face> others=new ArrayList<>();for(Object value:(List<?>)SharedJson.object("{\"faces\":"+allFaces+"}").get("faces"))others.add(SharedRetouch.readFace(SharedRuntime.object(value)));
        byte[] coverage=face.skinMask.copyCoverage();Crop frame=new Crop(face,width,height);PhotoPortrait.SkinMask m=face.skinMask;int covered=0;
        for(int y=0;y<S;y++){check(cancel);for(int x=0;x<S;x++){int i=y*S+x;if((coverage[i]&255)==0)continue;double u=m.left+(x+.5)/S*(m.right-m.left),v=m.top+(y+.5)/S*(m.bottom-m.top),px=face.cx*width+frame.cos*u*frame.rx-frame.sin*v*frame.ry,py=face.cy*height+frame.sin*u*frame.rx+frame.cos*v*frame.ry;
            for(PhotoPortrait.Face other:others){if(other.cx==face.cx&&other.cy==face.cy&&other.rx==face.rx&&other.ry==face.ry)continue;if(PortraitPreviewFilter.faceContains(other,px/width,py/height,width,height)){coverage[i]=0;break;}}if((coverage[i]&255)>16)covered++;}}
        if(covered<32)throw new IOException("未能确认独立面部皮肤，请重新识别。");row.put("skinMask",SharedRuntime.map("left",m.left,"top",m.top,"right",m.right,"bottom",m.bottom,"data",Base64.getEncoder().encodeToString(coverage)));return SharedJson.encode(row);
    }
    private static double area(Map<String,Object> p){return (((Number)p.get("right")).doubleValue()-((Number)p.get("left")).doubleValue())*(((Number)p.get("bottom")).doubleValue()-((Number)p.get("top")).doubleValue());}
    private static byte[] protection(int[] pixels,int width,int height,byte[] person,BooleanSupplier cancel)throws IOException {
        int[] luma=new int[S*S];for(int y=0;y<S;y++)for(int x=0;x<S;x++){int q=pixels[Math.min(height-1,(int)((y+.5)/S*height))*width+Math.min(width-1,(int)((x+.5)/S*width))];luma[y*S+x]=(int)(.2126*((q>>>16)&255)+.7152*((q>>>8)&255)+.0722*(q&255));}
        byte[] edge=new byte[S*S];for(int y=2;y<S-2;y++){check(cancel);for(int x=2;x<S-2;x++){int i=y*S+x;if((person[i]&255)>60)continue;boolean vertical=Math.abs(luma[i+1]-luma[i-1])>34,horizontal=Math.abs(luma[i+S]-luma[i-S])>34;if(!vertical&&!horizontal)continue;int count=0;for(int k=-12;k<=12;k++){int xx=horizontal?Math.max(1,Math.min(S-2,x+k)):x,yy=vertical?Math.max(1,Math.min(S-2,y+k)):y,j=yy*S+xx;if((person[j]&255)<80&&(vertical?Math.abs(luma[j+1]-luma[j-1]):Math.abs(luma[j+S]-luma[j-S]))>24)count++;}if(count>=17)edge[i]=(byte)255;}}
        float[] expanded=new float[S*S];int radius=24;for(int y=0;y<S;y++){check(cancel);for(int x=0;x<S;x++){double best=0;for(int k=-radius;k<=radius;k++){int xx=x+k;if(xx>=0&&xx<S&&(edge[y*S+xx]&255)>0){double v=1-Math.abs(k)/(double)radius;best=Math.max(best,v*v*(3-2*v));}}expanded[y*S+x]=(float)best;}}
        byte[] out=new byte[S*S];for(int y=0;y<S;y++){check(cancel);for(int x=0;x<S;x++){double best=expanded[y*S+x];for(int k=-radius;k<=radius;k++){int yy=y+k;if(yy<0||yy>=S)continue;double v=1-Math.abs(k)/(double)radius;best=Math.max(best,expanded[yy*S+x]*v*v*(3-2*v));}out[y*S+x]=(byte)Math.round(255*best);}}return out;
    }
    public static String background(int[] pixels,int width,int height,String encoded,BooleanSupplier cancel)throws IOException{validate(pixels,width,height);byte[] person;try{person=Base64.getDecoder().decode(encoded);}catch(IllegalArgumentException bad){throw new IOException("人物保护蒙版编码无效。",bad);}if(person.length!=S*S)throw new IOException("人物保护蒙版尺寸无效。");return Base64.getEncoder().encodeToString(protection(pixels,width,height,person,cancel));}
    private static void validate(int[] p,int w,int h)throws IOException{if(p==null||w<2||h<2||w>1280||h>1280||p.length!=w*h)throw new IOException("人物分析像素无效。");}
    private static double sample(int[] p,int w,int h,double x,double y,int shift){int ix=(int)Math.floor(x),iy=(int)Math.floor(y);double tx=x-ix,ty=y-iy,sum=0;for(int dy=0;dy<2;dy++)for(int dx=0;dx<2;dx++){int sx=ix+dx,sy=iy+dy;if(sx>=0&&sx<w&&sy>=0&&sy<h)sum+=((p[sy*w+sx]>>>shift)&255)*(dx==0?1-tx:tx)*(dy==0?1-ty:ty);}return sum;}
    private static void logits(float[] output)throws IOException{if(output==null||output.length!=N*N*C)throw new IOException("语义皮肤模型输出形状无效。");for(float v:output)if(!Float.isFinite(v))throw new IOException("语义皮肤模型输出无效。");}
    private static void softmax(float[] output,int at,double[] out){double max=Double.NEGATIVE_INFINITY,sum=0;for(int c=0;c<C;c++)max=Math.max(max,output[at+c]);for(int c=0;c<C;c++){out[c]=Math.exp(output[at+c]-max);sum+=out[c];}for(int c=0;c<C;c++)out[c]/=sum;}
    private static void check(BooleanSupplier cancel)throws InterruptedIOException{if(cancel.getAsBoolean()||Thread.currentThread().isInterrupted())throw new InterruptedIOException("人物推理已停止。");}
}
