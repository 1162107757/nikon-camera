package cc.huevia.shared;

import cc.huevia.ncp.*;
import cc.huevia.library.SharedJson;
import java.io.*;
import java.util.*;

/** Generates the Flutter coverage fixture directly from preserved original models. */
public final class LocalSelectionReferenceTest {
    private static PhotoPortrait.Stroke stroke(double radius,double feather,boolean erase,double... points){return new PhotoPortrait.Stroke(points,radius,feather,erase);}
    private static AdjustmentRegion region(String id,List<PhotoPortrait.Stroke> strokes,List<SelectionShape> shapes,boolean inverted){
        return new AdjustmentRegion(id,id,true,1,strokes,PhotoAdjustments.NONE,PhotoPortrait.NONE,PhotoPortrait.Settings.NONE,null,shapes,inverted);
    }
    public static void main(String[] args)throws Exception {
        List<AdjustmentRegion> regions=new ArrayList<>();
        regions.add(region("empty",Collections.emptyList(),Collections.emptyList(),false));
        regions.add(region("empty-inverted",Collections.emptyList(),Collections.emptyList(),true));
        regions.add(region("soft-dot",Collections.singletonList(stroke(.12,.35,false,.5,.5)),Collections.emptyList(),false));
        regions.add(region("polyline",Collections.singletonList(stroke(.055,.6,false,.05,.2,.8,.3,.4,.9)),Collections.emptyList(),false));
        List<PhotoPortrait.Stroke> strokes=Arrays.asList(stroke(.18,.55,false,.15,.3,.8,.65),stroke(.09,.4,true,.5,.5));
        regions.add(region("add-erase",strokes,Collections.emptyList(),false));
        List<SelectionShape> shapes=Arrays.asList(
            new SelectionShape(SelectionShape.Kind.ELLIPSE,.1,.15,.9,.85,.45,false,0),
            new SelectionShape(SelectionShape.Kind.RECTANGLE,.3,.2,.7,.6,.6,true,1),
            new SelectionShape(SelectionShape.Kind.ELLIPSE,.35,.3,.65,.75,.8,false,2));
        regions.add(region("ordered-shapes",strokes,shapes,false));
        regions.add(region("ordered-inverted",strokes,shapes,true));
        regions.add(region("subtract-only",Collections.singletonList(stroke(.2,.5,true,.5,.5)),Collections.singletonList(new SelectionShape(SelectionShape.Kind.RECTANGLE,.1,.1,.9,.9,.4,true,1)),true));
        regions.add(region("thin-edge",Collections.singletonList(stroke(.001,.4,false,0,0,1,1)),Collections.emptyList(),false));
        double[] longPath=new double[1024];for(int i=0;i<512;i++){longPath[i*2]=.05+.9*i/511;longPath[i*2+1]=.5+.35*Math.sin(i*.14);}
        regions.add(region("bounded-long-path",Collections.singletonList(new PhotoPortrait.Stroke(longPath,.04,.5,false)),Collections.emptyList(),false));
        List<Object> cases=new ArrayList<>();int columns=17,rows=13;
        for(int[] size:Arrays.asList(new int[]{6400,4000},new int[]{3200,6400}))for(AdjustmentRegion region:regions){
            ByteArrayOutputStream bytes=new ByteArrayOutputStream();new PhotoLocalEdits(Collections.emptyList(),Collections.emptyList(),PhotoPortrait.NONE,Collections.singletonList(region)).write(new DataOutputStream(bytes));
            Map<String,Object> description=SharedLocalEdits.request("local.describe",SharedRuntime.map("localData",Base64.getEncoder().encodeToString(bytes.toByteArray())),()->false);
            AdjustmentRegion.Brush brush=region.compileBrush(size[0],size[1]);List<Double> samples=new ArrayList<>();
            for(int y=0;y<rows;y++)for(int x=0;x<columns;x++)samples.add(brush.weight(x/(double)(columns-1),y/(double)(rows-1)));
            cases.add(SharedRuntime.map("name",region.name+"-"+size[0]+"x"+size[1],"width",size[0],"height",size[1],"columns",columns,"rows",rows,"region",((List<?>)description.get("regions")).get(0),"samples",samples));
        }
        System.out.println(SharedJson.encode(SharedRuntime.map("schema",1,"reference","Original AdjustmentRegion.compileBrush from preserved Android source","cases",cases)));
    }
}
