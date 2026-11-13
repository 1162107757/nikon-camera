package cc.huevia.shared;

import cc.huevia.album.ConnectionTrace;
import java.io.IOException;

/** Backend-owned clock, independent of routes, Flutter frames and picker UI. */
final class SharedCameraMaintenance {
    static final long INTERVAL_MILLIS=3_000;
    private final SharedCamera camera;
    private final Object lock=new Object();
    private boolean allowed;
    private volatile boolean active;
    private long generation;

    SharedCameraMaintenance(SharedCamera camera){this.camera=camera;}
    boolean active(){return active;}
    boolean allowed(){synchronized(lock){return allowed;}}
    void setAllowed(boolean value){synchronized(lock){if(allowed==value)return;allowed=value;}reconcile();}
    private boolean current(long token){synchronized(lock){return allowed&&active&&generation==token;}}
    void reconcile(){reconcile(-1);}
    private void reconcile(long expectedGeneration){
        Thread start=null;boolean stop=false;String cancelJob="";
        synchronized(lock){
            if(expectedGeneration>=0&&generation!=expectedGeneration)return;
            boolean connected=camera.maintenanceConnection();
            boolean wanted=allowed&&(connected||camera.maintenancePreparing());
            if(wanted&&!active){active=true;long token=++generation;start=new Thread(()->loop(token),"camera-readonly-heartbeat");start.setDaemon(true);}
            else if(!wanted&&active){active=false;generation++;lock.notifyAll();stop=true;cancelJob=camera.maintenanceJob();}
        }
        // Never hold the clock lock across protocol close or a native observer.
        if(stop){camera.cancelMaintenance(cancelJob);ConnectionTrace.mark("CAMERA_HEARTBEAT_STOPPED");}
        if(start!=null){ConnectionTrace.mark("CAMERA_HEARTBEAT_STARTED");start.start();}
        camera.notifyMaintenanceObserver();
    }
    private void loop(long token){
        while(current(token)){
            synchronized(lock){
                if(!allowed||!active||generation!=token)return;
                try{lock.wait(INTERVAL_MILLIS);}catch(InterruptedException interrupted){Thread.currentThread().interrupt();return;}
            }
            if(!current(token))return;
            try{camera.maintain(()->!current(token));}catch(IOException|RuntimeException failure){ConnectionTrace.mark("CAMERA_HEARTBEAT_FAILED");}
            if(current(token))reconcile(token);
        }
    }
}
