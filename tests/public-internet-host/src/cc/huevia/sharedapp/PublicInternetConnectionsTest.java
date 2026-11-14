package cc.huevia.sharedapp;

import android.content.Context;
import android.net.*;
import cc.huevia.account.*;
import cc.huevia.community.CommunityHttpTransport;
import cc.huevia.library.PublicLibraryHttpProbe;
import java.io.*;
import java.net.*;
import java.security.cert.Certificate;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.*;
import javax.net.ssl.HttpsURLConnection;

/** Offline network objects plus a live loopback camera socket/heartbeat, without Android or a camera. */
public final class PublicInternetConnectionsTest {
    private static int checks;
    private static NetworkCapabilities caps(int transport,boolean validated) {
        NetworkCapabilities caps=new NetworkCapabilities().transport(transport);
        if(validated)caps.capability(NetworkCapabilities.NET_CAPABILITY_INTERNET).capability(NetworkCapabilities.NET_CAPABILITY_VALIDATED);
        return caps;
    }
    private static void check(boolean value,String message) { if(!value)throw new AssertionError(message); checks++; }
    public static void main(String[] args)throws Exception {
        ConnectivityManager cm=new ConnectivityManager();
        Network camera=new Network("camera-wifi",caps(NetworkCapabilities.TRANSPORT_WIFI,false));
        Network cellular=new Network("cellular",caps(NetworkCapabilities.TRANSPORT_CELLULAR,true));
        cm.active=camera;cm.networks=new Network[]{camera};cm.requested=cellular;cm.delayMillis=250;
        AtomicInteger disconnected=new AtomicInteger();
        AtomicBoolean retainedDuringDisconnect=new AtomicBoolean();
        AtomicInteger responseStatus=new AtomicInteger(200);
        cellular.connections=url->new Reply(url,responseStatus.get(),()->{
            disconnected.incrementAndGet();retainedDuringDisconnect.set(cm.callbacks.size()>1);
        });
        camera.connections=url->{throw new AssertionError("Public HTTP must not use camera Wi-Fi");};
        PublicInternetConnections opener=new PublicInternetConnections(new Context(cm));
        AtomicInteger heartbeat=new AtomicInteger();AtomicReference<Throwable> heartbeatFailure=new AtomicReference<>();
        AtomicBoolean stop=new AtomicBoolean();
        try(ServerSocket receiver=new ServerSocket(0,1,InetAddress.getLoopbackAddress());
            Socket cameraSocket=camera.getSocketFactory().createSocket(InetAddress.getLoopbackAddress(),receiver.getLocalPort());
            Socket peer=receiver.accept()) {
            cameraSocket.setSoTimeout(1500);peer.setSoTimeout(1500);
            Thread echo=new Thread(()->{try{while(!stop.get()){int value=peer.getInputStream().read();if(value<0)return;peer.getOutputStream().write(value);}}catch(IOException failure){if(!stop.get())heartbeatFailure.set(failure);}},"camera-echo");
            Thread beats=new Thread(()->{try{while(!stop.get()){cameraSocket.getOutputStream().write(17);if(cameraSocket.getInputStream().read()!=17)throw new IOException("Camera heartbeat changed");heartbeat.incrementAndGet();Thread.sleep(10);}}catch(Exception failure){if(!stop.get())heartbeatFailure.set(failure);}},"camera-heartbeat");
            echo.start();beats.start();
            try {
                int before=heartbeat.get();
                AccountHttpTransport.OpenedConnection opened=opener.open(new URL(AccountHttpTransport.BASE_URL+"/health"));
                check(heartbeat.get()>=before+5,"Camera heartbeat continues while cellular selection waits");
                check(cm.callbacks.size()==2,"HTTP retains only its own additional cellular lease");
                check(opened.connection.getResponseCode()==200,"HTTPS uses cellular network");
                opened.close();opened.close();
                check(cm.unregisters==1&&retainedDuringDisconnect.get(),"Disconnect closes HTTP before releasing its own callback exactly once");
                int after=heartbeat.get();Thread.sleep(70);
                check(heartbeat.get()>after&&!cameraSocket.isClosed()&&heartbeatFailure.get()==null,"Camera socket and heartbeat survive HTTP lease release");
                check(cm.callbacks.size()==1&&cm.callbacks.contains(cm.cameraLease)&&cm.active==camera,"Camera network/lease remains selected and retained");

                cm.networks=new Network[]{camera,cellular};
                int requests=cm.requests;
                try(AccountHttpTransport.OpenedConnection existing=opener.open(new URL(AccountHttpTransport.BASE_URL+"/health"))){check(existing.connection!=null,"Already validated cellular connection opens immediately");}
                check(cm.requests==requests,"Existing Internet network does not request or switch networks");

                AccountHttpTransport.setPublicConnectionOpener(opener);
                check(new AccountHttpTransport().request("GET","/auth/me","A".repeat(43),null).status==200,"Account HTTP uses the platform connection opener");
                check(new CommunityHttpTransport().request("GET","/community/feed",null,null).status==200,"Community HTTP uses the same platform connection opener");
                check(new String(PublicLibraryHttpProbe.read(AccountHttpTransport.BASE_URL+"/catalog.json"),StandardCharsets.UTF_8).equals("{}"),"Catalog/image HTTP client uses the same platform connection opener");
                responseStatus.set(503);
                AccountRepository.Response unavailable=new AccountHttpTransport().request("GET","/auth/me","A".repeat(43),null);
                check(unavailable.status==503&&unavailable.body.length==0,"HTML gateway error retains authoritative HTTP service status");
                responseStatus.set(200);

                Network vpn=new Network("user-vpn",caps(NetworkCapabilities.TRANSPORT_VPN,true));
                vpn.connections=url->new Reply(url,200,()->{});
                cm.active=vpn;cm.networks=new Network[]{camera,cellular,vpn};
                int physicalOpens=cellular.httpOpens;
                try(AccountHttpTransport.OpenedConnection bound=opener.open(new URL(AccountHttpTransport.BASE_URL+"/health"))){check(bound.connection.getResponseCode()==200,"Validated default VPN is used");}
                check(vpn.httpOpens==1&&cellular.httpOpens==physicalOpens,"Default VPN is never bypassed for cellular");
                cm.active=camera;
                try(AccountHttpTransport.OpenedConnection bound=opener.open(new URL(AccountHttpTransport.BASE_URL+"/health"))){check(bound.connection.getResponseCode()==200,"Existing validated VPN is preferred to physical fallback");}
                check(vpn.httpOpens==2&&cellular.httpOpens==physicalOpens,"Enumeration order cannot route around VPN");
                vpn.capabilities=caps(NetworkCapabilities.TRANSPORT_VPN,false);cm.active=vpn;
                int vpnRequests=cm.requests;
                try{opener.open(new URL(AccountHttpTransport.BASE_URL+"/health"));throw new AssertionError("Unvalidated VPN must fail closed");}
                catch(AccountException vpnUnavailable){check(vpnUnavailable.code.equals("PUBLIC_VPN_UNAVAILABLE"),"VPN failure has a clear safe classification");}
                check(cm.requests==vpnRequests&&cellular.httpOpens==physicalOpens,"Unvalidated VPN cannot trigger direct physical or cellular request fallback");
                cm.active=cellular;
                try(AccountHttpTransport.OpenedConnection bound=opener.open(new URL(AccountHttpTransport.BASE_URL+"/health"))){check(bound.connection.getResponseCode()==200,"A validated per-app default honors explicit VPN app exclusions");}
                cm.active=camera;

                cm.networks=new Network[]{camera};cm.requested=null;cm.delayMillis=50;
                try { opener.open(new URL(AccountHttpTransport.BASE_URL+"/health"));throw new AssertionError("Missing cellular must fail"); }
                catch(AccountException unavailableNetwork){check(unavailableNetwork.code.equals("PUBLIC_NETWORK_UNAVAILABLE")&&unavailableNetwork.getMessage().contains("移动数据"),"No mobile data gives a clear network message");}
                cm.requested=cellular;cellular.connections=url->{throw new IOException("fixture connect failed");};
                try { opener.open(new URL(AccountHttpTransport.BASE_URL+"/health"));throw new AssertionError("Open failure must propagate"); }
                catch(IOException expected){check(cm.callbacks.size()==1,"Opening HTTP failure releases its callback");}
                check(cm.callbacks.contains(cm.cameraLease)&&cm.active==camera&&camera.httpOpens==0&&camera.socketFactories==1&&cm.processChanges==0,
                        "Success and failure never replace process routes, camera sockets, or camera lease");
                check(heartbeatFailure.get()==null&&heartbeat.get()>10,"Camera heartbeat is healthy throughout all network scenarios");
            } finally { stop.set(true);cameraSocket.close();peer.close();beats.join(2000);echo.join(2000); }
        }
        System.out.println("Public Internet host regression passed: "+checks+" checks; loopback camera heartbeat stayed active (physical camera not exercised).");
    }

    private static final class Reply extends HttpsURLConnection {
        private final int status;private final Runnable closed;private final byte[] body;
        Reply(URL url,int status,Runnable closed){super(url);this.status=status;this.closed=closed;body=(status==503?"<html>gateway unavailable</html>":"{}").getBytes(StandardCharsets.UTF_8);}
        public void connect() {} public void disconnect(){closed.run();} public boolean usingProxy(){return false;}
        public int getResponseCode(){return status;}
        public String getContentType(){return status==503?"text/html":"application/json; charset=utf-8";}
        public String getHeaderField(String name){return null;}
        public String getContentEncoding(){return null;}public long getContentLengthLong(){return body.length;}
        public InputStream getInputStream(){return new ByteArrayInputStream(body);}public InputStream getErrorStream(){return new ByteArrayInputStream(body);}
        public String getCipherSuite(){return "fixture";}public Certificate[] getLocalCertificates(){return null;}public Certificate[] getServerCertificates(){return null;}
    }
}
