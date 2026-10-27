package cc.huevia.ui;
import java.util.*;
import java.util.concurrent.Executor;

public final class LatestPreviewQueueTest {
    private static int checks;
    private static final class Manual implements Executor{final Deque<Runnable> queue=new ArrayDeque<>();public void execute(Runnable r){queue.addLast(r);}void one(){queue.removeFirst().run();}}
    public static void main(String[] args){
        Manual worker=new Manual(),ui=new Manual();List<String> frames=new ArrayList<>();List<Integer> dropped=new ArrayList<>(),rendered=new ArrayList<>();List<Throwable> errors=new ArrayList<>();
        LatestPreviewQueue<Integer,Integer> queue=new LatestPreviewQueue<>(worker,ui,(value,live)->{rendered.add(value);if(value<0)throw new IllegalStateException("fixture");return value;},new LatestPreviewQueue.Listener<Integer,Integer>(){public void frame(Integer snapshot,Integer result,boolean live,boolean latest){frames.add(result+":"+live+":"+latest);}public void discard(Integer value){dropped.add(value);}public void error(Throwable error){errors.add(error);}});
        queue.offer(1,true);queue.offer(2,true);queue.offer(3,true);check(worker.queue.size()==1,"one in flight");worker.one();queue.offer(4,true);ui.one();check(frames.equals(List.of("1:true:false")),"completed older live frame remains visible during continuous movement");check(worker.queue.size()==1,"only latest pending admitted");worker.one();ui.one();check(rendered.equals(List.of(1,4)),"intermediate pending snapshots coalesced");check(frames.get(1).equals("4:true:true")&&queue.isIdle(),"latest live frame and idle notification");
        queue.offer(5,true);queue.offer(6,false);worker.one();ui.one();check(dropped.equals(List.of(5)),"obsolete low quality frame cannot overwrite release");worker.one();ui.one();check(frames.get(frames.size()-1).equals("6:false:true"),"release renders exact final snapshot");
        queue.offer(7,true);queue.reset();queue.offer(8,true);worker.one();ui.one();check(dropped.contains(7),"old photo frame rejected after source reset");worker.one();ui.one();check(frames.get(frames.size()-1).equals("8:true:true"),"new source continues after old in-flight work");
        queue.offer(-1,true);queue.offer(9,true);worker.one();ui.one();check(errors.isEmpty(),"superseded failure is quiet");worker.one();ui.one();check(frames.get(frames.size()-1).startsWith("9:"),"pending work continues after old failure");
        queue.offer(-2,false);worker.one();ui.one();check(errors.size()==1&&queue.isIdle(),"latest error delivered once and does not wedge queue");
        int before=rendered.size();for(int i=10;i<1010;i++)queue.offer(i,true);worker.one();ui.one();worker.one();ui.one();check(rendered.size()==before+2&&rendered.get(rendered.size()-1)==1009,"long drag keeps bounded first/latest work");
        int count=frames.size();queue.offer(1010,true);queue.close();worker.one();ui.one();check(frames.size()==count&&dropped.contains(1010),"close discards an in-flight image");queue.offer(1011,false);check(worker.queue.isEmpty(),"closed screen admits no work");
        System.out.println("PASS: "+checks+" interactive preview scheduling checks");
    }
    private static void check(boolean value,String text){if(!value)throw new AssertionError(text);checks++;}
}
