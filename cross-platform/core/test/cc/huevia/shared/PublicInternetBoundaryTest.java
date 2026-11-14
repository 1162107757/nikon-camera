package cc.huevia.shared;

import cc.huevia.account.*;
import cc.huevia.library.SharedJson;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

/** Public network waits cannot own the runtime monitor or resurrect a superseded account. */
final class PublicInternetBoundaryTest {
    private static final String OWNER="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
    private static final String INSTALL="bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
    private static int checks;
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Public network boundary "+checks);}
    private static final class Store implements AccountRepository.Store {
        byte[] bytes;
        public synchronized byte[] read(){return bytes==null?null:bytes.clone();}
        public synchronized void write(byte[] value){bytes=value.clone();}
        public synchronized void clear(){bytes=null;}
    }
    private static final class Server implements AccountRepository.Transport {
        volatile boolean hold=true;
        final CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1);
        final AtomicInteger cleanup=new AtomicInteger();
        public AccountRepository.Response request(String method,String path,String token,byte[] body)throws IOException {
            if("/auth/logout".equals(path)){cleanup.incrementAndGet();return response(200,SharedRuntime.map("ok",true));}
            if(!"/auth/qq".equals(path))throw new AssertionError("Unexpected account endpoint");
            if(hold){entered.countDown();try{if(!release.await(4,TimeUnit.SECONDS))throw new IOException("Fixture timeout");}
                catch(InterruptedException failure){Thread.currentThread().interrupt();throw new InterruptedIOException();}}
            return response(200,SharedRuntime.map("tokenType","Bearer","accessToken","A".repeat(43),"expiresAt","2099-01-01T00:00:00Z","user",
                    SharedRuntime.map("id",OWNER,"username","","nickname","Fixture","avatarUrl","","avatarSource","default","provider","qq","status","active",
                            "createdAt","2026-01-01T00:00:00Z","lastLoginAt","2026-01-01T00:00:00Z","updatedAt","2026-01-01T00:00:00Z","loginCount",1)));
        }
    }
    private static AccountRepository.Response response(int status,Map<String,Object> value){return new AccountRepository.Response(status,SharedJson.encode(value).getBytes(StandardCharsets.UTF_8));}
    static int run(Path temporary)throws Exception {
        checks=0;Store store=new Store();Server server=new Server();
        SharedRuntime runtime=new SharedRuntime(Files.createDirectory(temporary.resolve("public-network")).toString(),store,server,INSTALL);
        ExecutorService publicIo=Executors.newSingleThreadExecutor(),cameraQueue=Executors.newSingleThreadExecutor();
        try {
            Future<String> login=publicIo.submit(()->runtime.requestPublic("account.qq",SharedJson.encode(SharedRuntime.map("owner","","accessToken","synthetic-qq-provider-token")),()->false));
            yes(server.entered.await(2,TimeUnit.SECONDS));
            Future<Boolean> cameraCommand=cameraQueue.submit(()->{
                runtime.guardOwner("");
                Map<String,Object> library=SharedJson.object(runtime.request("library.list","{}"));
                return library.get("items") instanceof List;
            });
            yes(cameraCommand.get(750,TimeUnit.MILLISECONDS)); // Would time out if the HTTP wait held runtime's monitor.
            Map<String,Object> logout=SharedJson.object(runtime.requestPublic("account.logout","{}",()->false));
            yes(Boolean.TRUE.equals(logout.get("loggedOut")));
            server.release.countDown();
            try{login.get(2,TimeUnit.SECONDS);throw new AssertionError("Late login replaced logout");}
            catch(ExecutionException failure){yes(failure.getCause() instanceof AccountException);yes("SESSION_CHANGED".equals(((AccountException)failure.getCause()).code));}
            yes(server.cleanup.get()==1);yes(store.bytes==null);
            yes(!SharedJson.object(runtime.request("account.current","{}")).containsKey("user"));
            runtime.guardOwner("");yes(true);
            server.hold=false;
            Map<String,Object> signedIn=SharedJson.object(runtime.requestPublic("account.qq",SharedJson.encode(SharedRuntime.map("owner","","accessToken","synthetic-qq-provider-token")),()->false));
            yes(OWNER.equals(((Map<?,?>)signedIn.get("user")).get("id")));yes(!signedIn.containsKey("accessToken"));
            runtime.guardOwner(OWNER);yes(true);
            try{runtime.guardOwner("");throw new AssertionError("Old owner accepted");}catch(IOException expected){yes(true);}
            try{runtime.requestPublic("camera.disconnect","{}",()->false);throw new AssertionError("Camera operation reached public queue");}catch(IOException expected){yes(true);}
            try{runtime.requestPublic("account.qq","{}",()->true);throw new AssertionError("Cancelled call performed work");}catch(InterruptedIOException expected){yes(true);}
            yes(SharedRuntime.accountNetworkOperation("account.qq")&&SharedRuntime.accountNetworkOperation("account.logout"));
            yes(SharedRuntime.publicNetworkOperation("online.page")&&SharedRuntime.publicNetworkOperation("online.preview")&&SharedRuntime.publicNetworkOperation("community.get"));
            yes(!SharedRuntime.publicNetworkOperation("online.download")&&!SharedRuntime.publicNetworkOperation("community.write")&&!SharedRuntime.accountNetworkOperation("camera.connect"));
            System.out.println("PASS "+checks+" public network dispatch checks; runtime monitor stays free, logout generation and owner guards stay authoritative");
            return checks;
        } finally {server.release.countDown();publicIo.shutdownNow();cameraQueue.shutdownNow();}
    }
}
