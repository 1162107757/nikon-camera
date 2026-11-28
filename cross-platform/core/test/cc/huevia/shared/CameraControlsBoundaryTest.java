package cc.huevia.shared;

import cc.huevia.library.SharedJson;
import cc.huevia.ptp.*;
import cc.huevia.remote.*;
import cc.huevia.ncp.NcpCompatibilityFixtures;
import cc.huevia.album.PhotoCameraClient;
import java.io.*;
import java.nio.file.*;
import java.util.*;

/** Actual protocol-state boundaries, including mutations committed before a lost response. */
public final class CameraControlsBoundaryTest {
    private static int checks;
    private interface Action{void run()throws Exception;}
    private static void yes(boolean value){checks++;if(!value)throw new AssertionError("Camera controls check "+checks);}
    private static void rejects(Action action)throws Exception{checks++;try{action.run();}catch(IOException expected){return;}throw new AssertionError("Unsafe camera request accepted: "+checks);}
    static int run(Path temporary)throws Exception {
        checks=0;File root=Files.createDirectory(temporary.resolve("camera-controls")).toFile();
        guardChecks();slotChecks(root);ncpChecks(root);np3Checks(root);np2Checks(root);remoteChecks(root);
        remoteExposureChecks(Files.createDirectory(root.toPath().resolve("remote-exposure")).toFile());
        dispatcherChecks(root);
        System.out.println("PASS "+checks+" camera controls checks; explicit scope, exact target snapshots, one-shot write/delete/shutter, durable uncertainty and readback recovery");return checks;
    }
    private static void guardChecks()throws Exception {
        SharedSlotTransportGuard guard=new SharedSlotTransportGuard();
        rejects(()->guard.send(0x90cd,1,profile("A"),new long[]{201,0}));
        guard.read(0x1001,0,new long[0]);guard.command(0x1002,0,new long[]{1});
        rejects(()->guard.read(0x1009,1,new long[]{1}));
        guard.read(0x90cf,1,new long[]{1});rejects(()->guard.read(0x90cc,1,new long[]{201,0}));
        rejects(()->guard.read(0x90cc,2,new long[]{200,0}));
        rejects(()->guard.send(0x1016,2,new byte[]{1},new long[]{0x5010}));
        rejects(()->guard.send(0x90cd,2,profile("A"),new long[]{201,1}));
        guard.send(0x90cd,2,profile("A"),new long[]{201,0});
        rejects(()->guard.send(0x90cd,3,profile("B"),new long[]{202,0}));
        rejects(()->guard.authorizeDeletion(202));
        guard.command(0x1003,3,new long[0]);rejects(()->guard.command(0x1002,0,new long[]{1}));
        SharedSlotTransportGuard deletion=new SharedSlotTransportGuard();deletion.command(0x1002,0,new long[]{1});deletion.authorizeDeletion(201);
        rejects(()->deletion.command(0x90ce,1,new long[]{202}));rejects(()->deletion.send(0x90cd,1,profile("B"),new long[]{202,0}));
        deletion.command(0x90ce,1,new long[]{201});rejects(()->deletion.command(0x90ce,2,new long[]{201}));
    }
    private static void slotChecks(File root)throws Exception {
        SharedSlots slots=new SharedSlots(root);SlotPeer peer=new SlotPeer();
        Map<String,Object> opened=map(slots.open(peer,"slots-1","trusted-camera",()->false));yes(((List<?>)opened.get("items")).size()==9);yes(peer.writes==0&&peer.deletes==0);
        rejects(()->slots.request("camera.slots.prepare",SharedRuntime.map("session","old","kind","write","source",201,"target",202),()->false));
        Map<String,Object> plan=map(slots.request("camera.slots.prepare",SharedRuntime.map("session","slots-1","kind","write","source",201,"target",202),()->false));yes(peer.writes==0);
        final Map<String,Object> initialPlan=plan;
        rejects(()->slots.request("camera.slots.execute",SharedRuntime.map("session","slots-1","confirmationId",initialPlan.get("confirmationId")),()->false));
        peer.items.put(202,profile("INTERVENING"));
        rejects(()->slots.request("camera.slots.execute",confirm("slots-1",initialPlan),()->false));yes(peer.writes==0);peer.items.put(202,new byte[36]);
        plan=map(slots.request("camera.slots.prepare",SharedRuntime.map("session","slots-1","kind","write","source",201,"target",202),()->false));final Map<String,Object> changedSource=plan;
        peer.items.put(201,profile("CHANGED SOURCE"));rejects(()->slots.request("camera.slots.execute",confirm("slots-1",changedSource),()->false));yes(peer.writes==0);peer.items.put(201,profile("SOURCE"));
        plan=map(slots.request("camera.slots.prepare",SharedRuntime.map("session","slots-1","kind","write","source",201,"target",202),()->false));
        Map<String,Object> result=map(slots.request("camera.slots.execute",confirm("slots-1",plan),()->false));yes(peer.writes==1);yes(!Boolean.TRUE.equals(map(result.get("action")).get("pending")));yes(Arrays.equals(peer.items.get(201),peer.items.get(202)));
        final Map<String,Object> replay=plan;rejects(()->slots.request("camera.slots.execute",confirm("slots-1",replay),()->false));yes(peer.writes==1);
        rejects(()->slots.request("camera.slots.close",SharedRuntime.map("session","old"),()->false));yes(peer.open);slots.close();yes(!peer.open);
        // A physical write can succeed before the response is lost. Reopening must read, never replay.
        SlotPeer lost=new SlotPeer();lost.loseResponse=true;
        slots.open(lost,"slots-2","trusted-camera",()->false);
        plan=map(slots.request("camera.slots.prepare",SharedRuntime.map("session","slots-2","kind","write","source",201,"target",203),()->false));
        result=map(slots.request("camera.slots.execute",confirm("slots-2",plan),()->false));yes(Boolean.TRUE.equals(map(result.get("action")).get("pending")));yes(lost.writes==1&&!lost.open);
        SlotPeer recovered=new SlotPeer();recovered.items=lost.items;slots.open(recovered,"slots-3","trusted-camera",()->false);
        rejects(()->slots.request("camera.slots.prepare",SharedRuntime.map("session","slots-3","kind","delete","target",203),()->false));
        result=map(slots.request("camera.slots.reconcile",SharedRuntime.map("session","slots-3"),()->false));yes(map(result.get("action")).get("phase").equals("verifiedByReadback"));yes(recovered.writes==0&&recovered.deletes==0);
        plan=map(slots.request("camera.slots.prepare",SharedRuntime.map("session","slots-3","kind","delete","target",203),()->false));
        result=map(slots.request("camera.slots.execute",confirm("slots-3",plan),()->false));yes(recovered.deletes==1);yes(map(result.get("action")).get("phase").equals("verified"));yes(Arrays.equals(recovered.items.get(201),profile("SOURCE")));slots.close();
        SlotPeer active=new SlotPeer();active.active=201;slots.open(active,"slots-4","trusted-camera",()->false);
        plan=map(slots.request("camera.slots.prepare",SharedRuntime.map("session","slots-4","kind","delete","target",201),()->false));final Map<String,Object> activePlan=plan;
        rejects(()->slots.request("camera.slots.execute",confirm("slots-4",activePlan),()->false));yes(active.deletes==0);slots.close();
        SlotPeer managed=new SlotPeer();managed.managed=true;slots.open(managed,"slots-managed","trusted-camera",()->false);yes(managed.first.equals("open"));slots.close();
        SlotPeer interrupted=new SlotPeer();slots.open(interrupted,"slots-abort","trusted-camera",()->false);slots.abort();yes(!interrupted.open);yes(interrupted.closeCommands==0);slots.close();
    }
    private static void ncpChecks(File root)throws Exception {
        SharedSlots slots=new SharedSlots(root);SlotPeer peer=new SlotPeer();slots.open(peer,"ncp","trusted-camera",()->false);
        Path file=root.toPath().resolve("fixture.ncp");byte[] ncp=NcpCompatibilityFixtures.ncp();Files.write(file,ncp);
        Map<String,Object> plan=map(slots.request("camera.slots.prepare",SharedRuntime.map("session","ncp","kind","write","path",file.toString(),"target",204,"middleQuarter",8,"clarityQuarter",-4),()->false));
        yes(plan.get("name").equals("HOST NCP"));yes(peer.writes==0);yes(((String)plan.get("explanation")).contains("兼容适配"));
        rejects(()->slots.request("camera.slots.execute",confirm("ncp",plan),()->true));yes(peer.writes==0);
        Map<String,Object> result=map(slots.request("camera.slots.execute",confirm("ncp",plan),()->false));yes(map(result.get("action")).get("phase").equals("verified"));yes(Arrays.equals(peer.items.get(204),NcpCompatibilityFixtures.expectedData(8,-4)));yes(Arrays.equals(Files.readAllBytes(file),ncp));slots.close();
    }
    private static void np3Checks(File root)throws Exception {
        SharedSlots slots=new SharedSlots(root);SlotPeer peer=new SlotPeer();slots.open(peer,"np3","trusted-camera",()->false);
        Path file=root.toPath().resolve("partial.np3");byte[] original=cc.huevia.ncp.CameraPresetProjectionTest.np3(0x1234,8,true,true);Files.write(file,original);
        Map<String,Object> plan=map(slots.request("camera.slots.prepare",SharedRuntime.map("session","np3","kind","write","path",file.toString(),"target",205,"middleQuarter",4,"clarityQuarter",0),()->false));
        yes(peer.writes==0);yes(((String)plan.get("explanation")).contains("不导入"));yes(((String)plan.get("explanation")).contains("可继续导入"));
        rejects(()->slots.request("camera.slots.execute",confirm("np3",plan),()->true));yes(peer.writes==0);
        Map<String,Object> result=map(slots.request("camera.slots.execute",confirm("np3",plan),()->false));
        yes(map(result.get("action")).get("phase").equals("verified"));yes(peer.writes==1);
        yes(Arrays.equals(peer.items.get(205),cc.huevia.ncp.CameraPresetProjection.plan(original,null,null).conversion.dataBytes()));
        yes(Arrays.equals(Files.readAllBytes(file),original));
        rejects(()->slots.request("camera.slots.execute",confirm("np3",plan),()->false));yes(peer.writes==1);slots.close();
    }
    private static void np2Checks(File root)throws Exception {
        SharedSlots slots=new SharedSlots(root);SlotPeer peer=new SlotPeer();slots.open(peer,"np2","trusted-camera",()->false);
        Path file=root.toPath().resolve("partial.np2");
        byte[] original=cc.huevia.ncp.Np2SupportTest.scalar(cc.huevia.ncp.Np2Fixtures.flat(),6,13);
        original=cc.huevia.ncp.Np2SupportTest.replace(original,0xbeef,new byte[]{1,2});Files.write(file,original);
        Map<Integer,byte[]> before=new LinkedHashMap<>();for(var item:peer.items.entrySet())before.put(item.getKey(),item.getValue().clone());
        Map<String,Object> plan=map(slots.request("camera.slots.prepare",SharedRuntime.map("session","np2","kind","write","path",file.toString(),"target",206,"middleQuarter",4,"clarityQuarter",0),()->false));
        yes(peer.writes==0);Map<String,Object> report=map(plan.get("compatibility"));yes(report.get("format").equals("NP2"));
        yes(report.get("approximated").toString().contains("平面"));yes(report.get("omitted").toString().contains("扩展"));
        rejects(()->slots.request("camera.slots.execute",confirm("np2",plan),()->true));yes(peer.writes==0);
        Map<String,Object> result=map(slots.request("camera.slots.execute",confirm("np2",plan),()->false));
        yes(map(result.get("action")).get("phase").equals("verified"));yes(peer.writes==1);
        byte[] written=peer.items.get(206);yes(written.length==36&&written[25]==13&&written[27]==0);
        yes(Arrays.equals(written,cc.huevia.ncp.CameraPresetProjection.plan(original,null,null).conversion.dataBytes()));
        yes(Arrays.equals(original,Files.readAllBytes(file)));for(var item:before.entrySet())if(item.getKey()!=206)yes(Arrays.equals(item.getValue(),peer.items.get(item.getKey())));
        rejects(()->slots.request("camera.slots.execute",confirm("np2",plan),()->false));yes(peer.writes==1);slots.close();
    }
    private static void dispatcherChecks(File root)throws Exception {
        final class PhotoPeer implements PhotoCameraClient {
            boolean open;
            public byte[] connect(String h,int p,byte[] g,String n){open=true;return info(new int[]{0x1001,0x1002,0x1003,0x1004,0x1007,0x1008,0x1009,0x90cc,0x90cd,0x90ce,0x90cf},new int[0]);}
            public boolean isOpen(){return open;}public boolean isProtocolUnconfirmed(){return false;}public String closeReason(){return "";}public String connectedHost(){return "usb:fixture";}public int connectedPort(){return 0;}public String cameraIdentity(){return "";}
            public void setOnClosed(Runnable r){}public void setOnObjectAdded(java.util.function.LongConsumer l){}
            public byte[] readAlbumDeviceInfo(){return connect("",0,null,"");}
            public byte[] getData(int op,int max,long...p)throws IOException{if(op==0x1004||op==0x1007)return concat(le32(1),le32(1));if(op==0x1008)return new PtpObjectInfo.Builder().storageId(1).objectFormat(0x3801).compressedSize(8).filename("DISPATCH.JPG").build().toBytes();throw new IOException("Unexpected album read");}
            public byte[] getLargeThumbnail(long h)throws IOException{throw new IOException("No preview");}public long readTo(int o,OutputStream d,long m,long e,Progress p,long...a)throws IOException{throw new IOException("No download");}public void abortProtocol(IOException e){close();}public void close(){open=false;}
        }
        PhotoPeer photo=new PhotoPeer();final boolean[] fail={true};final SlotPeer[] slot={null};
        SharedCamera camera=new SharedCamera(root.getPath(),(h,p,f)->{throw new AssertionError("USB unexpectedly used Wi-Fi");},new SharedCamera.WiredConnections(){
            public String devices(){return "{\"items\":[]}";}public PhotoCameraClient create(String id){return photo;}
            public SharedSlots.Transport openSlots(String id)throws IOException{yes(id.equals("fixture"));if(fail[0]){fail[0]=false;throw new IOException("First USB open refused");}slot[0]=new SlotPeer();return slot[0];}
        });
        Map<String,Object> connected=call(camera,"camera.connect",SharedRuntime.map("transport","usb","deviceId","fixture","protocol","nikon"));String session=(String)connected.get("session");
        rejects(()->call(camera,"camera.remote.open",SharedRuntime.map("session",session)));
        yes(((List<?>)call(camera,"camera.page",SharedRuntime.map("session",session,"limit",10)).get("items")).size()==1);
        rejects(()->call(camera,"camera.slots.open",SharedRuntime.map("session",session)));yes(!photo.open);
        Map<String,Object> opened=call(camera,"camera.slots.open",SharedRuntime.map("session",session));yes(((List<?>)opened.get("items")).size()==9);
        String slotSession=(String)opened.get("session");call(camera,"camera.slots.close",SharedRuntime.map("session",slotSession));yes(!slot[0].open);
        opened=call(camera,"camera.slots.open",SharedRuntime.map("session",slotSession));yes(!slotSession.equals(opened.get("session")));camera.disconnect();yes(!slot[0].open);
    }
    private static Map<String,Object> call(SharedCamera camera,String operation,Map<String,Object> p)throws IOException{return SharedJson.object(camera.request(operation,SharedJson.encode(p),"camera-controls",()->false,v->{}));}
    private static void remoteChecks(File root)throws Exception {
        SharedRemote remote=new SharedRemote(root);RemotePeer peer=new RemotePeer();
        Map<String,Object> opened=map(remote.open(peer,()->{},PtpDeviceInfo.parseRedacted(remoteInfo()),"remote-1","trusted-camera"));final Map<String,Object> scope=SharedRuntime.map("session","remote-1","remoteId",opened.get("remoteId"));
        rejects(()->remote.request("camera.remote.capture",SharedRuntime.map("session","remote-1","remoteId","stale"),()->false));
        peer.single=false;rejects(()->remote.request("camera.remote.capture",scope,()->false));yes(peer.shutters==0);peer.single=true;
        peer.loseResponse=true;Map<String,Object> result=map(remote.request("camera.remote.capture",scope,()->false));yes(peer.shutters==1);yes(Boolean.TRUE.equals(map(result.get("action")).get("pending")));
        rejects(()->remote.request("camera.remote.capture",scope,()->false));yes(peer.shutters==1);
        result=map(remote.request("camera.remote.check",scope,()->false));yes(map(result.get("action")).get("phase").equals("verified"));yes(peer.shutters==1);
        rejects(()->remote.request("camera.remote.focus",SharedRuntime.map("session","remote-1","remoteId",scope.get("remoteId"),"x",Double.NaN,"y",0.5),()->false));
        remote.request("camera.remote.focus",scope,()->false);yes(peer.focuses==1);
        remote.request("camera.remote.view",SharedRuntime.map("session","remote-1","remoteId",scope.get("remoteId"),"enabled",true),()->false);yes(peer.starts==1);remote.close();yes(peer.stops==1);
        SharedRemote reopened=new SharedRemote(root);RemotePeer next=new RemotePeer();opened=map(reopened.open(next,()->{},PtpDeviceInfo.parseRedacted(remoteInfo()),"remote-2","trusted-camera"));
        final Map<String,Object> newerScope=SharedRuntime.map("session","remote-2","remoteId",opened.get("remoteId"));rejects(()->reopened.request("camera.remote.close",SharedRuntime.map("session","remote-1","remoteId","stale"),()->false));
        yes(map(reopened.request("camera.remote.status",newerScope,()->false)).get("connected").equals(true));reopened.close();

        long[] now={100_000};
        SharedRemote pairing=new SharedRemote(root,()->now[0]);RemotePeer slow=new RemotePeer();slow.files=0;
        opened=map(pairing.open(slow,()->{},PtpDeviceInfo.parseRedacted(remoteInfo()),"remote-3","trusted-camera"));
        Map<String,Object> pairingScope=SharedRuntime.map("session","remote-3","remoteId",opened.get("remoteId"));
        Map<String,Object> acknowledged=remoteAction(pairing,"camera.remote.capture",pairingScope);
        yes(acknowledged.get("phase").equals("acknowledged"));yes(!acknowledged.containsKey("baseline"));
        yes(Boolean.TRUE.equals(acknowledged.get("canCheck")));
        SharedRemote otherCamera=new SharedRemote(root);
        Map<String,Object> otherState=map(otherCamera.open(new RemotePeer(),()->{},PtpDeviceInfo.parseRedacted(remoteInfo()),"other-session","other-camera"));
        yes(Boolean.FALSE.equals(map(otherState.get("action")).get("canCheck")));
        Map<String,Object> otherScope=SharedRuntime.map("session","other-session","remoteId",otherState.get("remoteId"));
        rejects(()->otherCamera.request("camera.remote.check",otherScope,()->false));otherCamera.close();
        slow.busy=true;
        yes(remoteAction(pairing,"camera.remote.check",pairingScope).get("phase").equals("acknowledged"));
        slow.busy=false;
        yes(remoteAction(pairing,"camera.remote.check",pairingScope).get("phase").equals("waitingForPhoto"));
        slow.files=1;slow.staleHandle=true;
        yes(remoteAction(pairing,"camera.remote.check",pairingScope).get("phase").equals("waitingForPhoto"));
        slow.staleHandle=false;
        slow.files=1;slow.incomplete=true;
        yes(remoteAction(pairing,"camera.remote.check",pairingScope).get("phase").equals("waitingForPhoto"));
        slow.incomplete=false;
        yes(remoteAction(pairing,"camera.remote.check",pairingScope).get("phase").equals("waitingForJpeg"));
        now[0]+=9_999;
        yes(remoteAction(pairing,"camera.remote.check",pairingScope).get("phase").equals("waitingForJpeg"));
        slow.files=2;
        Map<String,Object> paired=remoteAction(pairing,"camera.remote.check",pairingScope);
        yes(paired.get("phase").equals("verified"));yes(((List<?>)paired.get("photos")).size()==2);yes(slow.shutters==1);
        Map<String,Object> lateConfirmation=new LinkedHashMap<>(pairingScope);
        lateConfirmation.put("confirmedOnCamera",true);lateConfirmation.put("actionId",paired.get("actionId"));
        yes(remoteAction(pairing,"camera.remote.acknowledge",lateConfirmation).get("phase").equals("verified"));
        pairing.close();

        SharedRemote noJpeg=new SharedRemote(root,()->now[0]);RemotePeer missing=new RemotePeer();missing.files=1;
        opened=map(noJpeg.open(missing,()->{},PtpDeviceInfo.parseRedacted(remoteInfo()),"remote-4","trusted-camera"));
        Map<String,Object> noJpegScope=SharedRuntime.map("session","remote-4","remoteId",opened.get("remoteId"));
        remoteAction(noJpeg,"camera.remote.capture",noJpegScope);
        yes(remoteAction(noJpeg,"camera.remote.check",noJpegScope).get("phase").equals("waitingForJpeg"));
        now[0]+=10_000;
        yes(remoteAction(noJpeg,"camera.remote.check",noJpegScope).get("phase").equals("verified"));yes(missing.shutters==1);
        noJpeg.close();

        SharedRemote interrupted=new SharedRemote(root);
        RemotePeer previousPeer=new RemotePeer();previousPeer.files=0;
        Map<String,Object> old=map(interrupted.open(previousPeer,()->{},PtpDeviceInfo.parseRedacted(remoteInfo()),"old-session","old-identity"));
        Map<String,Object> oldScope=SharedRuntime.map("session","old-session","remoteId",old.get("remoteId"));
        Map<String,Object> previous=remoteAction(interrupted,"camera.remote.capture",oldScope);
        RemotePeer freshPeer=new RemotePeer();
        Map<String,Object> fresh=map(interrupted.open(freshPeer,()->{},PtpDeviceInfo.parseRedacted(remoteInfo()),"new-session","new-identity"));
        Map<String,Object> freshScope=SharedRuntime.map("session","new-session","remoteId",fresh.get("remoteId"));
        rejects(()->interrupted.request("camera.remote.capture",freshScope,()->false));
        Map<String,Object> wrong=SharedRuntime.map("session","new-session","remoteId",fresh.get("remoteId"),"actionId","stale-result","continueWithoutConfirming",true);
        rejects(()->interrupted.request("camera.remote.acknowledge",wrong,()->false));
        wrong.put("actionId",previous.get("actionId"));
        Map<String,Object> closed=remoteAction(interrupted,"camera.remote.acknowledge",wrong);
        yes(Boolean.FALSE.equals(closed.get("pending")));yes("closedUnverified".equals(closed.get("phase")));
        yes(previousPeer.shutters==1&&freshPeer.shutters==0);
        Map<String,Object> nextCapture=remoteAction(interrupted,"camera.remote.capture",freshScope);
        yes(!Objects.equals(previous.get("actionId"),nextCapture.get("actionId")));yes(freshPeer.shutters==1);
        interrupted.close();
    }
    private static Map<String,Object> remoteAction(SharedRemote remote,String operation,Map<String,Object> scope)throws IOException {
        return map(map(remote.request(operation,scope,()->false)).get("action"));
    }
    private static void remoteExposureChecks(File root)throws Exception {
        final int aperture=RemoteExposure.APERTURE,shutter=RemoteExposure.SHUTTER,iso=RemoteExposure.ISO;
        final int ev=RemoteExposure.COMPENSATION,wb=RemoteExposure.WHITE_BALANCE,kelvin=RemoteExposure.COLOR_TEMPERATURE;
        Map<Integer,Long> actual=new HashMap<>(Map.of(aperture,280L,shutter,50L,iso,6400L,ev,0L,wb,2L,kelvin,5500L));
        Map<Integer,byte[]> descriptors=Map.of(
            aperture,enumDescriptor(aperture,4,true,280,280,400,560),
            shutter,enumDescriptor(shutter,6,true,50,25,50,100,0xffffffffL),
            iso,enumDescriptor(iso,4,true,6400,1600,3200,6400),
            ev,enumDescriptor(ev,3,true,0,-666,-333,0,333,666),
            wb,enumDescriptor(wb,4,true,2,2,0x8010,0x8012),
            kelvin,concat(le16(kelvin),le16(4),new byte[]{1},
                    le16(5500),le16(5500),new byte[]{1},le16(2500),le16(10000),le16(10)));
        int[] focusRequests={0},busyReplies={1},writes={0};
        boolean[] clamp={false},busyRead={false};
        RemoteTransport transport=new RemoteTransport(){
            public boolean isOpen(){return true;}
            public void command(int op,long...values)throws IOException{
                if(op!=NikonRemoteCamera.AF)throw new IOException("Unexpected camera mutation");
                focusRequests[0]++;
                if(busyReplies[0]-->0)throw new PtpResponseException(0x2019,0);
            }
            public byte[] data(int op,int maximum,long...values)throws IOException{
                int code=(int)values[0];
                if(op==0x1014&&descriptors.containsKey(code))return descriptors.get(code);
                if(op==0x1015&&actual.containsKey(code)){
                    if(busyRead[0]){busyRead[0]=false;throw new PtpResponseException(0x2019,0);}
                    return code==shutter?le32(actual.get(code).intValue()):le16(actual.get(code).intValue());
                }
                throw new IOException("Unexpected camera read "+op);
            }
        };
        try(SharedRemote remote=new SharedRemote(root)){
            PtpDeviceInfo device=PtpDeviceInfo.parseRedacted(info(new int[]{0x1014,0x1015,0x1016,0x90c1},new int[]{aperture,iso,shutter,ev,wb,kelvin}));
            Map<String,Object> opened=map(remote.open(transport,()->{},device,"exposure-session","nikon-test",(code,value,cancel)->{
                RemoteExposure.parse(code,descriptors.get(code)).encode(value);
                writes[0]++;
                actual.put(code,clamp[0]?280:value);
            }));
            Map<String,Object> scope=SharedRuntime.map("session","exposure-session","remoteId",opened.get("remoteId"));
            yes(Boolean.TRUE.equals(opened.get("exposureControls")));
            Map<String,Object> focused=map(remote.request("camera.remote.focus",scope,()->false));
            yes(focusRequests[0]==2&&!focused.containsKey("notice"));
            busyReplies[0]=2;
            focused=map(remote.request("camera.remote.focus",scope,()->false));
            yes(focusRequests[0]==4&&focused.get("notice").toString().contains("相机暂忙"));
            for(int code:new int[]{aperture,iso,shutter}){
                Map<String,Object> request=new LinkedHashMap<>(scope);request.put("code",code);
                Map<String,Object> options=map(remote.request("camera.remote.exposure.options",request,()->false));
                List<?> values=(List<?>)options.get("choices");
                yes(values.size()==3&&!values.contains(0xffffffffL));
                long wanted=(Long)values.get(code==shutter?2:1);
                request.put("value",wanted);
                busyRead[0]=true;
                Map<String,Object> changed=map(remote.request("camera.remote.exposure.set",request,()->false));
                yes(exposureValue(changed,code)==wanted&&!changed.containsKey("notice"));
            }
            yes(writes[0]==3);
            Map<String,Object> request=new LinkedHashMap<>(scope);request.put("code",aperture);request.put("value",560);
            clamp[0]=true;
            Map<String,Object> changed=map(remote.request("camera.remote.exposure.set",request,()->false));
            yes(exposureValue(changed,aperture)==280&&changed.containsKey("notice"));
            request.put("value",123);
            yes(map(remote.request("camera.remote.exposure.set",request,()->false)).containsKey("notice"));
            yes(writes[0]==4);
            request.put("code",0x500a);rejects(()->remote.request("camera.remote.exposure.set",request,()->false));
            request.put("code",aperture);request.put("remoteId","stale");rejects(()->remote.request("camera.remote.exposure.set",request,()->false));
            yes(writes[0]==4);
            clamp[0]=false;
            Map<String,Object> additional=new LinkedHashMap<>(scope);additional.put("code",ev);
            Map<String,Object> options=map(remote.request("camera.remote.exposure.options",additional,()->false));
            yes(options.get("choices").equals(List.of(-666L,-333L,0L,333L,666L)));
            for(int step:new int[]{-333,0}){
                additional.put("value",step);
                changed=map(remote.request("camera.remote.exposure.set",additional,()->false));
                yes(exposureValue(changed,ev)==step);
            }
            additional.put("code",kelvin);additional.put("value",5600);
            yes(map(remote.request("camera.remote.exposure.set",additional,()->false)).containsKey("notice"));
            yes(writes[0]==6);
            additional.put("code",wb);additional.put("value",RemoteExposure.TEMPERATURE_MODE);
            changed=map(remote.request("camera.remote.exposure.set",additional,()->false));
            yes(exposureValue(changed,wb)==RemoteExposure.TEMPERATURE_MODE);
            additional.put("code",kelvin);additional.put("value",5600);
            options=map(remote.request("camera.remote.exposure.options",additional,()->false));
            yes(((List<?>)options.get("choices")).size()==751);
            changed=map(remote.request("camera.remote.exposure.set",additional,()->false));
            yes(exposureValue(changed,kelvin)==5600);
            additional.put("code",wb);additional.put("value",0x8010);
            changed=map(remote.request("camera.remote.exposure.set",additional,()->false));
            yes(exposureValue(changed,wb)==0x8010 && writes[0]==9);
        }
        yes(RemoteExposure.parse(aperture,enumDescriptor(aperture,4,false,280,280,400)).choices.isEmpty());
        yes(Arrays.equals(RemoteExposure.parse(ev,descriptors.get(ev)).encode(-333),le16(-333)));
        yes(RemoteExposure.read(ev,le16(-666))==-666);
    }
    private static long exposureValue(Map<String,Object> state,int code) {
        for(Object item:(List<?>)state.get("parameters")){
            Map<String,Object> row=map(item);
            if(((Number)row.get("code")).intValue()==code)return ((Number)row.get("value")).longValue();
        }
        throw new AssertionError("Missing exposure value");
    }
    private static byte[] enumDescriptor(int code,int type,boolean writable,long current,long... options) {
        byte[] value=type==6?le32((int)current):le16((int)current);
        ByteArrayOutputStream out=new ByteArrayOutputStream();
        out.writeBytes(concat(le16(code),le16(type),new byte[]{(byte)(writable?1:0)},value,value,new byte[]{2},le16(options.length)));
        for(long option:options)out.writeBytes(type==6?le32((int)option):le16((int)option));
        return out.toByteArray();
    }
    @SuppressWarnings("unchecked") private static Map<String,Object> map(Object o){return (Map<String,Object>)o;}
    private static Map<String,Object> confirm(String session,Map<String,Object> plan){return SharedRuntime.map("session",session,"confirmationId",plan.get("confirmationId"),"confirmed",true);}
    private static byte[] profile(String name){byte[] value=new byte[36];value[0]=1;for(int i=0;i<name.length()&&i<20;i++)value[2+i]=(byte)name.charAt(i);return value;}
    private static final class SlotPeer implements SharedSlots.Transport {
        Map<Integer,byte[]> items=new LinkedHashMap<>();SharedSlotTransportGuard guard=new SharedSlotTransportGuard();boolean open=true,loseResponse,managed;int writes,deletes,active=1,closeCommands;String first="";
        SlotPeer(){for(int i=201;i<=209;i++)items.put(i,i==201?profile("SOURCE"):new byte[36]);}
        public boolean isOpen(){return open;}public boolean isSessionManaged(){return managed;}public void close(){open=false;}
        public void authorizeDeletion(int target)throws IOException{guard.authorizeDeletion(target);}
        public byte[] read(int op,long tx,long...p)throws IOException{if(first.isEmpty())first="read";guard.read(op,tx,p);if(op==0x1001)return slotInfo();if(op==0x90cf)return new byte[28];if(op==0x90cc)return items.get((int)p[0]).clone();if(op==0x1015)return le16(active);throw new IOException("Unexpected slot read");}
        public PtpContainer command(int op,long tx,long...p)throws IOException{if(first.isEmpty())first="open";guard.command(op,tx,p);if(op==0x1003)closeCommands++;if(op==0x90ce){deletes++;items.put((int)p[0],new byte[36]);}return PtpContainer.response(0x2001,tx);}
        public PtpContainer send(int op,long tx,byte[] bytes,long...p)throws IOException{guard.send(op,tx,bytes,p);writes++;items.put((int)p[0],bytes.clone());if(loseResponse)throw new IOException("Response lost after device mutation");return PtpContainer.response(0x2001,tx);}
    }
    private static final class RemotePeer implements RemoteTransport {
        boolean single=true,loseResponse,busy,incomplete,staleHandle;int shutters,focuses,starts,stops,files=-1;
        public boolean isOpen(){return true;}
        public void command(int op,long...p)throws IOException{if(op==NikonRemoteCamera.CAPTURE){shutters++;if(loseResponse)throw new IOException("Shutter response lost");}else if(op==NikonRemoteCamera.AF)focuses++;else if(op==NikonRemoteCamera.START)starts++;else if(op==NikonRemoteCamera.END)stops++;}
        public byte[] data(int op,int max,long...p)throws IOException {
            if(op==0x1014){int code=(int)p[0],type=code==0x5013?4:6;byte[] value=property(code);return concat(le16(code),le16(type),new byte[]{0},value,value,new byte[]{0});}
            if(op==0x1015)return property((int)p[0]);
            if(op==0x1004){if(busy)throw new PtpResponseException(0x2019,0);return concat(le32(1),le32(1));}
            if(op==0x1007){
                if(shutters==0||files==0)return concat(le32(1),le32(1));
                if(files==2)return concat(le32(3),le32(1),le32(2),le32(3));
                return concat(le32(2),le32(1),le32(2));
            }
            if(op==0x1008){
                if(staleHandle)throw new PtpResponseException(0x2009,0);
                boolean raw=files>=0&&p[0]==2;
                return new PtpObjectInfo.Builder().storageId(1).objectFormat(raw?0x3000:0x3801).compressedSize(incomplete?0:8).filename(raw?"DSC_0002.NEF":"DSC_0002.JPG").build().toBytes();
            }
            throw new IOException("Unexpected remote read "+op);
        }
        byte[] property(int code){return code==0x5013?le16(single?1:2):le32(code==0x5004?5:80);}
    }
    private static byte[] slotInfo(){return info(new int[]{0x1001,0x1002,0x1003,0x90cc,0x90cd,0x90ce,0x90cf,0x1015},new int[]{0xd200});}
    private static byte[] remoteInfo(){return info(new int[]{0x1001,0x1002,0x1003,0x1004,0x1007,0x1008,0x100a,0x1014,0x1015,0x9201,0x9202,0x9203,0x9205,0x9207,0x90c1},new int[]{0x5013,0x500d,0x5004});}
    private static byte[] info(int[] operations,int[] properties){return concat(le16(100),le32(10),le16(100),text(""),le16(0),array(operations),array(new int[0]),array(properties),array(new int[0]),array(new int[0]),text("NIKON CORPORATION"),text("NIKON TEST"),text("1"),text(""));}
    private static byte[] array(int[] values){ByteArrayOutputStream out=new ByteArrayOutputStream();out.writeBytes(le32(values.length));for(int value:values)out.writeBytes(le16(value));return out.toByteArray();}
    private static byte[] text(String s){ByteArrayOutputStream o=new ByteArrayOutputStream();if(s.isEmpty()){o.write(0);return o.toByteArray();}o.write(s.length()+1);for(char c:s.toCharArray())o.writeBytes(le16(c));o.writeBytes(le16(0));return o.toByteArray();}
    private static byte[] le16(int n){return new byte[]{(byte)n,(byte)(n>>>8)};}private static byte[] le32(int n){return new byte[]{(byte)n,(byte)(n>>>8),(byte)(n>>>16),(byte)(n>>>24)};}
    private static byte[] concat(byte[]...parts){ByteArrayOutputStream out=new ByteArrayOutputStream();for(byte[] p:parts)out.writeBytes(p);return out.toByteArray();}
    public static void main(String[] args)throws Exception{run(Files.createTempDirectory("camera-controls-"));}
}
