package cc.huevia.ui;

import java.util.concurrent.Executor;

/** One render in flight, one latest pending snapshot. Superseded live frames still show while dragging. */
public final class LatestPreviewQueue<S,R> {
    public interface Renderer<S,R>{R render(S snapshot,boolean interactive)throws Exception;}
    public interface Listener<S,R>{
        void frame(S snapshot,R result,boolean interactive,boolean latest);
        void discard(R result);
        void error(Throwable error);
    }
    private final Executor worker,ui;
    private final Renderer<S,R> renderer;
    private final Listener<S,R> listener;
    private long epoch,sequence;
    private boolean running,closed;
    private Job pending,latest;
    private final class Job {
        final S snapshot;final boolean interactive;final long generation,id;
        Job(S snapshot,boolean interactive){this.snapshot=snapshot;this.interactive=interactive;generation=epoch;id=++sequence;}
    }
    public LatestPreviewQueue(Executor worker,Executor ui,Renderer<S,R> renderer,Listener<S,R> listener){this.worker=worker;this.ui=ui;this.renderer=renderer;this.listener=listener;}
    public void offer(S snapshot,boolean interactive){
        Job start=null;synchronized(this){if(closed)return;latest=pending=new Job(snapshot,interactive);if(!running){running=true;start=pending;pending=null;}}
        if(start!=null)launch(start);
    }
    public synchronized void reset(){epoch++;pending=latest=null;}
    public synchronized void close(){closed=true;reset();}
    public synchronized boolean isIdle(){return !running&&pending==null;}
    private void launch(Job job){
        try{worker.execute(()->{R result=null;Throwable failure=null;try{result=renderer.render(job.snapshot,job.interactive);}catch(Exception|OutOfMemoryError error){failure=error;}final R value=result;final Throwable error=failure;ui.execute(()->complete(job,value,error));});}
        catch(RuntimeException unavailable){ui.execute(()->complete(job,null,unavailable));}
    }
    private void complete(Job job,R result,Throwable error){
        boolean publish,isLatest;
        synchronized(this){isLatest=latest!=null&&latest.id==job.id;publish=!closed&&job.generation==epoch&&(isLatest||job.interactive&&latest!=null&&latest.interactive);}
        try{if(error!=null){if(publish&&isLatest)listener.error(error);}else if(publish)listener.frame(job.snapshot,result,job.interactive,isLatest);else if(result!=null)listener.discard(result);}
        finally{Job next=null;synchronized(this){running=false;if(!closed&&pending!=null){next=pending;pending=null;running=true;}}if(next!=null)launch(next);}
    }
}
