package cc.huevia.album;

import java.io.File;
import java.nio.file.Files;
import java.util.*;

/** Date meaning, stable ties and arrival records, independently of Android UI layout. */
public final class PhotoSortHostTest {
    private static int checks;
    private record Row(String id,long taken,long added) { }
    public static void main(String[] args)throws Exception {
        List<Row> rows=List.of(new Row("A",100,900),new Row("B",900,100),new Row("C",0,500),new Row("D",0,0),new Row("E",900,700));
        order(rows,new PhotoSort(false,false),"B,E,C,A,D");order(rows,new PhotoSort(false,true),"A,C,B,E,D");
        order(rows,new PhotoSort(true,false),"A,E,C,B,D");order(rows,new PhotoSort(true,true),"B,C,E,A,D");
        for(boolean added:new boolean[]{false,true})for(boolean oldest:new boolean[]{false,true}){
            PhotoSort value=new PhotoSort(added,oldest);check(PhotoSort.parse(value.token()).equals(value),"token roundtrip");
            check(value.compare(1,1,"a",1,1,"b")<0,"stable tie independent of direction");
        }
        check(PhotoSort.parse("unknown").equals(PhotoSort.DEFAULT),"unknown preference defaults");
        check(PhotoSort.DEFAULT.date(-1,42)==42,"missing taken fallback");check(PhotoSort.DEFAULT.date(Long.MAX_VALUE,42)==42,"invalid taken fallback");
        check(PhotoSort.DEFAULT.date(0,Long.MAX_VALUE)==0,"invalid added remains unknown");
        List<Row> many=new ArrayList<>();for(int i=0;i<341;i++)many.add(new Row(String.format(Locale.ROOT,"%04d",i),i+1,341-i));
        List<Row> sorted=new ArrayList<>(many);sorted.sort((a,b)->PhotoSort.DEFAULT.compare(a.taken,a.added,a.id,b.taken,b.added,b.id));
        for(int offset=0;offset<341;offset+=80){List<Row> page=sorted.subList(offset,Math.min(341,offset+80));check(page.get(0).taken==341-offset,"full-sort page boundary");}
        File folder=Files.createTempDirectory("huevia-sort-").toFile(),photo=new File(folder,"original.jpg");Files.write(photo.toPath(),new byte[]{1,2,3,4});photo.setLastModified(123456789);
        byte[] before=Files.readAllBytes(photo.toPath());long modified=photo.lastModified();
        PhotoArrivalDates.write(photo,1000);check(PhotoArrivalDates.read(photo)==1000,"arrival roundtrip");PhotoArrivalDates.recordIfMissing(photo);check(PhotoArrivalDates.read(photo)==1000,"cache regeneration retains arrival");
        PhotoArrivalDates.record(photo);check(PhotoArrivalDates.read(photo)>1000,"fresh ingestion updates arrival");
        check(Arrays.equals(before,Files.readAllBytes(photo.toPath()))&&modified==photo.lastModified(),"metadata never changes photo bytes or mtime");
        PhotoArrivalDates.forget(photo);check(PhotoArrivalDates.read(photo)==0&&photo.isFile(),"forget only removes presentation record");
        PhotoArrivalDates.write(photo,Long.MAX_VALUE);check(PhotoArrivalDates.read(photo)==0,"invalid arrival rejected");
        PhotoArrivalDates.forget(photo);Files.delete(photo.toPath());for(File entry:Objects.requireNonNull(folder.listFiles())){if(entry.isDirectory())for(File child:Objects.requireNonNull(entry.listFiles()))Files.delete(child.toPath());Files.delete(entry.toPath());}Files.delete(folder.toPath());
        System.out.println("PhotoSortHostTest: "+checks+" checks passed");
    }
    private static void order(List<Row> rows,PhotoSort order,String expected){List<Row> copy=new ArrayList<>(rows);copy.sort((a,b)->order.compare(a.taken,a.added,a.id,b.taken,b.added,b.id));check(String.join(",",copy.stream().map(Row::id).toList()).equals(expected),order.token());}
    private static void check(boolean result,String message){checks++;if(!result)throw new AssertionError(message);}
}
