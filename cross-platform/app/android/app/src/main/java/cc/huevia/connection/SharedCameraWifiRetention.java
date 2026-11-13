package cc.huevia.connection;

import android.content.Context;
import cc.huevia.album.CameraWifiNetwork;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;

/** Android-only bridge to the unchanged legacy local-Wi-Fi network demand. */
public final class SharedCameraWifiRetention implements AutoCloseable {
    private final CameraWifiRetention retained;
    private final CameraWifiNetwork network;
    private final ExecutorService worker=Executors.newSingleThreadExecutor(task->{Thread thread=new Thread(task,"camera-wifi-demand");thread.setDaemon(true);return thread;});
    private final AtomicBoolean pending=new AtomicBoolean(),closed=new AtomicBoolean();
    private final AtomicLong revision=new AtomicLong();
    private volatile boolean required;

    public SharedCameraWifiRetention(Context context){Context app=context.getApplicationContext();retained=new CameraWifiRetention(app);network=new CameraWifiNetwork(app);}

    /** Never chooses the Internet default route; actual open camera sockets own it. */
    public void refresh(boolean required){
        if(closed.get())return;
        this.required=required;revision.incrementAndGet();drain();
    }

    private void drain(){
        if(closed.get()||!pending.compareAndSet(false,true))return;
        try{worker.execute(()->{
            long applied=-1;
            try{
                do{
                    applied=revision.get();
                    // The unchanged selector uses the exact physical socket network when present,
                    // otherwise a single physical Wi-Fi (including one without Internet).
                    retained.setRequired(!closed.get()&&required?network.connectedWifiNetwork():null);
                }while(!closed.get()&&applied!=revision.get());
            }finally{
                pending.set(false);
                if(!closed.get()&&applied!=revision.get())drain();
            }
        });}catch(RejectedExecutionException stopped){pending.set(false);if(!closed.get())throw stopped;}
    }

    @Override public void close(){
        if(!closed.compareAndSet(false,true))return;
        required=false;revision.incrementAndGet();
        worker.execute(retained::close);worker.shutdown();
    }
}
