package cc.huevia.ncp;

import java.io.*;
import java.nio.file.*;
import java.util.*;

/** Independent canonical-pixel oracle for ordered repair sampling and immutable persistence. */
public final class PhotoPatchTest {
    private static int checks;
    public static void main(String[] args)throws Exception{
        Path temp=Files.createTempDirectory("huevia-patch-test-");
        try{
            serialization();pixelMatrix(temp.toFile());blend(temp.toFile());faults(temp.toFile());large(temp.toFile());
            try(var files=Files.list(temp)){check("scratch-cleaned",files.findAny().isEmpty());}
            System.out.println("PASS "+checks+" repair checks; independent EXIF1-8/alpha/overlap/order oracle, v7 persistence, tone match, failure cleanup, 24MP bounded stream.");
        }finally{try(var files=Files.list(temp)){for(Path p:files.toList())Files.deleteIfExists(p);}Files.delete(temp);}
    }
    private static AdjustmentRegion region(SelectionShape.Kind kind,double feather){return AdjustmentRegion.create("修补区域").addShape(new SelectionShape(kind,.1,.15,.4,.65,feather,false,0));}
    private static void serialization()throws Exception{
        PhotoPatch a=PhotoPatch.create(region(SelectionShape.Kind.ELLIPSE,.3)).sample(.35,.1).blend(.75);
        PhotoLocalEdits e=PhotoLocalEdits.NONE.addPatch(a);byte[] bytes=bytes(e);check("v7",new DataInputStream(new ByteArrayInputStream(bytes)).readInt()==7);
        PhotoLocalEdits read=PhotoLocalEdits.read(new DataInputStream(new ByteArrayInputStream(bytes)));check("roundtrip",e.equals(read)&&e.identity().equals(read.identity()));
        check("retain-portrait",e.withPortrait(PhotoPortrait.NONE).patches().equals(e.patches()));
        check("retain-region",e.addRegion(AdjustmentRegion.create("区域")).patches().equals(e.patches()));
        check("retain-legacy",e.add(PhotoLocalEdits.Mask.radial(.2,.2)).patches().equals(e.patches()));
        check("remove-immutable",e.removePatch(0).patches().isEmpty()&&e.patches().size()==1);
        check("hidden-disabled-stored",!e.withPatch(0,a.enabled(false)).isEmpty()&&e.withPatch(0,a.enabled(false)).isNeutral());
        check("neutral-old-format",new DataInputStream(new ByteArrayInputStream(bytes(PhotoLocalEdits.NONE))).readInt()==1);
        ArrayList<PhotoPatch> tooMany=new ArrayList<>();for(int i=0;i<=PhotoLocalEdits.MAX_PATCHES;i++)tooMany.add(a);
        reject(()->PhotoLocalEdits.NONE.withPatches(tooMany));reject(()->a.sample(Double.NaN,0));reject(()->a.blend(1.1));
        reject(()->new PhotoPatch(a.selection.withAmount(.5),.1,0,1,true));
        check("negative-zero-normalized",a.sample(-0.0,0).equals(a.sample(0,0)));
        PhotoPatch feather=a.feather(.8);check("feather-preserves-selection",feather.selection.shapes.get(0).feather==.8&&a.selection.shapes.get(0).feather==.3);
        ByteArrayOutputStream bad=new ByteArrayOutputStream();DataOutputStream out=new DataOutputStream(bad);out.writeInt(7);out.writeInt(0);out.writeInt(0);PhotoPortrait.NONE.write(out);out.writeInt(0);out.writeInt(17);
        try{PhotoLocalEdits.read(new DataInputStream(new ByteArrayInputStream(bad.toByteArray())));throw new AssertionError("patch-count");}catch(IOException expected){checks++;}
    }
    private static byte[] bytes(PhotoLocalEdits e)throws Exception{ByteArrayOutputStream b=new ByteArrayOutputStream();e.write(new DataOutputStream(b));return b.toByteArray();}
    private static void pixelMatrix(File temp)throws Exception{
        final int w=80,h=60;int[] canonical=new int[w*h];
        for(int y=0;y<h;y++)for(int x=0;x<w;x++){int alpha=(x+y)%17==0?0:(x+y)%7==0?128:255;canonical[y*w+x]=(alpha<<24)|(((x*7+y*3)&255)<<16)|(((x*3+y*11)&255)<<8)|((x*13+y*5)&255);}
        for(SelectionShape.Kind kind:SelectionShape.Kind.values())for(double feather:new double[]{0,.35})for(int exif=1;exif<=8;exif++){
            PhotoPatch patch=PhotoPatch.create(region(kind,feather)).sample(.35,.1).blend(0);PhotoPatch second=patch.sample(.1,.05);
            int[] expected=oracle(canonical,w,h,kind,feather,.35,.1);expected=oracle(expected,w,h,kind,feather,.1,.05);
            Pixels p=new Pixels(canonical,w,h,exif,temp);PhotoPatchRenderer.apply(p,List.of(patch,second),exif,null,null);
            int[] actual=p.canonical();for(int i=0;i<actual.length;i++)check("pixel-"+exif+"-"+kind+"-"+feather,actual[i]==expected[i]);
            check("neutral-no-read",neutral(p,patch.sample(0,0)));
        }
        PhotoLocalEdits full=PhotoLocalEdits.NONE.addPatch(PhotoPatch.create(region(SelectionShape.Kind.RECTANGLE,0)).sample(.35,.1).blend(0));Pixels p=new Pixels(canonical,w,h,1,temp);LocalEditsPreviewProfile.renderLocal(p,full,1,null,null);check("shared-render-pipeline",Arrays.equals(p.canonical(),oracle(canonical,w,h,SelectionShape.Kind.RECTANGLE,0,.35,.1)));
    }
    private static boolean neutral(Pixels p,PhotoPatch patch)throws Exception{int before=p.reads;PhotoPatchRenderer.apply(p,List.of(patch),p.exif,null,null);return before==p.reads;}
    private static int[] oracle(int[] before,int w,int h,SelectionShape.Kind kind,double feather,double dx,double dy){
        int[] result=before.clone();for(int y=0;y<h;y++)for(int x=0;x<w;x++){
            double nx=(x+.5)/w,ny=(y+.5)/h,cx=.25,cy=.4,rx=.15,ry=.25;
            double distance=kind==SelectionShape.Kind.ELLIPSE?Math.sqrt(Math.pow((nx-cx)/rx,2)+Math.pow((ny-cy)/ry,2)):Math.max(Math.abs((nx-cx)/rx),Math.abs((ny-cy)/ry));
            double weight=distance>=1?0:distance<=1-feather||feather==0?1:(1-distance)/feather;
            // Production selection uses a smoothstep feather, whose cubic is specified independently here.
            if(weight>0&&weight<1)weight=weight*weight*(3-2*weight);
            int target=before[y*w+x];if(weight<=0||(target>>>24)==0)continue;
            int sx=(int)Math.floor(x+dx*w+.5),sy=(int)Math.floor(y+dy*h+.5);if(sx<0||sy<0||sx>=w||sy>=h)continue;
            int source=before[sy*w+sx];if((source>>>24)==0)continue;weight*=((source>>>24)&255)/255.0;int output=target&0xff000000;
            for(int shift:new int[]{16,8,0}){double a=linear((target>>>shift)&255),b=linear((source>>>shift)&255);output|=encoded(a+(b-a)*weight)<<shift;}result[y*w+x]=output;
        }return result;
    }
    private static void blend(File temp)throws Exception{
        int w=160,h=100;int[] image=new int[w*h];for(int y=0;y<h;y++)for(int x=0;x<w;x++){int value=x<80?96:180+((x+y)%2==0?8:-8);if(x>25&&x<50&&y>25&&y<50)value=10;image[y*w+x]=0xff000000|(value<<16)|(value<<8)|value;}
        PhotoPatch patch=PhotoPatch.create(region(SelectionShape.Kind.RECTANGLE,.2)).sample(.5,0);
        Pixels direct=new Pixels(image,w,h,1,temp),matched=new Pixels(image,w,h,1,temp);PhotoPatchRenderer.apply(direct,List.of(patch.blend(0)),1,null,null);PhotoPatchRenderer.apply(matched,List.of(patch),1,null,null);
        int a=direct.data[35*w+35]&255,b=matched.data[35*w+35]&255;check("boundary-colour-match",Math.abs(b-96)<Math.abs(a-96)/2);check("object-replaced",b>65);check("texture-retained",(matched.data[35*w+35]&255)!=(matched.data[35*w+36]&255));check("outside-exact",matched.data[0]==image[0]);
    }
    private static void faults(File temp)throws Exception{
        int[] image=new int[80*60];Arrays.fill(image,0xff887766);PhotoPatch p=PhotoPatch.create(region(SelectionShape.Kind.RECTANGLE,.2)).sample(.3,0);
        Pixels cancelled=new Pixels(image,80,60,1,temp);try{PhotoPatchRenderer.apply(cancelled,List.of(p),1,()->cancelled.reads>10,null);throw new AssertionError("cancel");}catch(InterruptedIOException expected){checks++;}check("cancel-cleanup",temp.list().length==0);
        Pixels broken=new Pixels(image,80,60,1,temp){public void write(int[] row,int first,int count)throws IOException{throw new IOException("expected write failure");}};
        try{PhotoPatchRenderer.apply(broken,List.of(p),1,null,null);throw new AssertionError("write-failure");}catch(IOException expected){checks++;}check("failure-cleanup",temp.list().length==0);
    }
    private static void large(File temp)throws Exception{
        SpatialPreviewFilter.Pixels stream=new SpatialPreviewFilter.Pixels(){public int width(){return 6000;}public int height(){return 4000;}public File scratchDirectory(){return temp;}public void read(int[] row,int first,int count){for(int y=0;y<count;y++)for(int x=0;x<6000;x++)row[y*6000+x]=0xff000000|((x+(first+y)*3)&0xffffff);}public void write(int[] row,int first,int count){check("large-row-bound",row.length<=6000&&count==1);}};
        AdjustmentRegion small=AdjustmentRegion.create("小修补").addShape(new SelectionShape(SelectionShape.Kind.RECTANGLE,.1,.1,.12,.12,.2,false,0));PhotoPatchRenderer.apply(stream,List.of(PhotoPatch.create(small).sample(.1,.1).blend(0)),1,null,null);check("large-cleanup",temp.list().length==0);
    }
    private static class Pixels implements SpatialPreviewFilter.Pixels{
        final int w,h,ow,oh,exif;final int[] data;final File temp;int reads;
        Pixels(int[] canonical,int ow,int oh,int exif,File temp){this.ow=ow;this.oh=oh;this.exif=exif;this.temp=temp;w=exif>=5?oh:ow;h=exif>=5?ow:oh;data=new int[w*h];for(int y=0;y<oh;y++)for(int x=0;x<ow;x++)data[index(x,y)]=canonical[y*ow+x];}
        int index(int x,int y){switch(exif){case 2:return y*w+(w-1-x);case 3:return (h-1-y)*w+w-1-x;case 4:return (h-1-y)*w+x;case 5:return x*w+y;case 6:return (h-1-x)*w+y;case 7:return (h-1-x)*w+w-1-y;case 8:return x*w+w-1-y;default:return y*w+x;}}
        int[] canonical(){int[] result=new int[ow*oh];for(int y=0;y<oh;y++)for(int x=0;x<ow;x++)result[y*ow+x]=data[index(x,y)];return result;}
        public int width(){return w;}public int height(){return h;}public File scratchDirectory(){return temp;}public void read(int[] row,int first,int count){reads++;System.arraycopy(data,first*w,row,0,count*w);}public void write(int[] row,int first,int count)throws IOException{System.arraycopy(row,0,data,first*w,count*w);}
    }
    private static double linear(int value){double c=value/255.0;return c<=.04045?c/12.92:Math.pow((c+.055)/1.055,2.4);}
    private static int encoded(double x){double c=Math.max(0,Math.min(1,x));return (int)Math.round(255*(c<=.0031308?12.92*c:1.055*Math.pow(c,1/2.4)-.055));}
    private interface Work{void run()throws Exception;}
    private static void reject(Work w)throws Exception{try{w.run();throw new AssertionError("invalid accepted");}catch(IllegalArgumentException expected){checks++;}}
    private static void check(String label,boolean okay){checks++;if(!okay)throw new AssertionError(label);}
}
