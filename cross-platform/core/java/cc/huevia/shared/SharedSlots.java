package cc.huevia.shared;

import cc.huevia.album.PtpIpClient;
import cc.huevia.album.PhotoCameraClient;
import cc.huevia.ncp.NcpPictureControlConverter;
import cc.huevia.picturecontrol.*;
import cc.huevia.ptp.*;
import cc.huevia.usb.CameraParameterController;
import cc.huevia.usb.CameraParameterRequest;
import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.function.BooleanSupplier;

/** Dedicated, bounded Picture Control session; album read privileges never authorize writes. */
public final class SharedSlots implements AutoCloseable {
    public interface Transport extends AutoCloseable {
        byte[] read(int operation,long transaction,long...parameters)throws IOException;
        PtpContainer command(int operation,long transaction,long...parameters)throws IOException;
        PtpContainer send(int operation,long transaction,byte[] bytes,long...parameters)throws IOException;
        void authorizeDeletion(int target)throws IOException;
        default void authorizeParameters(Map<Integer,byte[]> values)throws IOException{throw new IOException("此通道未提供拍摄参数授权。");}
        boolean isOpen();
        default boolean isSessionManaged(){return false;}
        @Override void close();
    }
    private final File root;
    private final SharedCameraMutationStore journal;
    private volatile Transport transport;
    private PtpDeviceInfo device;
    private long next;
    private boolean owned,consumed;
    private String session="",cameraId="",snapshot="";
    private Map<Integer,byte[]> slots=new LinkedHashMap<>();
    private Map<String,Object> preparation;
    private byte[] requested,confirmed;
    public SharedSlots(File root)throws IOException{this.root=root.getCanonicalFile();journal=new SharedCameraMutationStore(this.root,"slots");}
    public static Transport wifi(PtpIpClient.SocketConnector connector,String host,int port,byte[] guid)throws IOException {
        PtpIpClient client=PtpIpClient.forPictureControl(connector);
        try{client.connectForPictureControl(host,port,guid,"Huevia Picture Control");}
        catch(IOException|RuntimeException error){client.close();throw error;}
        return new WifiTransport(client,0);
    }
    static Transport fromAlbum(PtpIpClient album)throws IOException {
        PtpIpClient client=album.transferToPictureControl();
        try{return new WifiTransport(client,client.claimTransferredSession());}
        catch(IOException|RuntimeException error){client.close();throw error;}
    }
    private static final class WifiTransport implements Transport {
        private volatile PtpIpClient client;
        final long inheritedTransaction;
        private boolean attempted,deletion;
        WifiTransport(PtpIpClient client,long inherited){this.client=client;inheritedTransaction=inherited;}
        private PtpIpClient current()throws IOException{PtpIpClient current=client;if(current==null)throw new InterruptedIOException("槽位会话已取消。");return current;}
        public byte[] read(int op,long tx,long...p)throws IOException{return current().getPictureControlData(op,tx,p);}
        public PtpContainer command(int op,long tx,long...p)throws IOException{if(op==0x90ce)attempted=true;return current().pictureControlCommand(op,tx,p);}
        public PtpContainer send(int op,long tx,byte[] data,long...p)throws IOException{attempted=true;return current().sendPictureControlData(op,tx,data,p);}
        public void authorizeDeletion(int target)throws IOException{current().authorizePictureControlDeletion(target);deletion=true;}
        public void authorizeParameters(Map<Integer,byte[]> values)throws IOException{current().authorizeCameraParameters(values);}
        public boolean isOpen(){PtpIpClient current=client;return current!=null&&current.isOpen()&&!current.isProtocolUnconfirmed();}
        public void close(){PtpIpClient old;synchronized(this){old=client;client=null;}if(old!=null)old.close();}
        synchronized PhotoCameraClient release(long next)throws IOException {
            if(!isOpen())return null;
            try{
                if(attempted){
                    // Never rearm a rejected, lost-ACK or mismatched-readback write.
                    client=deletion?client.transferAfterVerifiedPictureControlDeletion(next):client.transferAfterVerifiedPictureControlImport(next);
                    if(client.claimTransferredSession()!=next)throw new IOException("槽位返回会话的事务序列不符。");
                }
                PtpIpClient album=client.transferToAlbum(next);client=album;
                if(album.claimTransferredAlbumSession()!=next)throw new IOException("相册返回会话的事务序列不符。");
                client=null;return album;
            }catch(IOException unverified){return null;}
        }
    }
    public Object open(Transport connection,String sessionId,String identity,BooleanSupplier cancel)throws IOException {
        return open(connection,sessionId,identity,cancel,false);
    }
    Object openRetainingSession(Transport connection,String sessionId,String identity,BooleanSupplier cancel)throws IOException {
        return open(connection,sessionId,identity,cancel,true);
    }
    private Object open(Transport connection,String sessionId,String identity,BooleanSupplier cancel,boolean retainHealthy)throws IOException {
        close();stage(connection,sessionId,identity);return initialize(cancel,retainHealthy);
    }
    void stage(Transport connection,String sessionId,String identity){
        if(transport!=null)throw new IllegalStateException("槽位通道尚未移交。");
        transport=connection;session=sessionId;cameraId=identity;next=1;consumed=false;
    }
    Object openStagedSession(BooleanSupplier cancel)throws IOException{return initialize(cancel,true);}
    private Object initialize(BooleanSupplier cancel,boolean retainHealthy)throws IOException {
        try{
            check(cancel);Transport connection=transport;if(connection==null)throw new InterruptedIOException("槽位会话已取消。");boolean managed=connection.isSessionManaged();
            long inherited=connection instanceof WifiTransport?((WifiTransport)connection).inheritedTransaction:0;
            if(inherited>0){next=inherited;owned=true;}
            else if(managed){command(0x1002,0,1);owned=true;}
            byte[] info=read(0x1001,owned?next++:0);device=PtpDeviceInfo.parseRedacted(info);PtpDeviceInfo identified=device;
            try{identified=PtpDeviceInfo.parse(info);}catch(PtpProtocolException optionalSerial){}
            // Persist only a hash, never the serial itself. Unknown identity remains session scoped.
            String serial=SharedCameraMutationStore.serial(identified.serialNumber());
            if(!serial.isEmpty())cameraId=SharedCameraMutationStore.sha(("huevia-slot-camera-v1\n"+identified.manufacturer()+"\n"+identified.model()+"\n"+serial).getBytes(java.nio.charset.StandardCharsets.UTF_8));
            requireReadCapabilities(device);
            if(!owned){command(0x1002,0,1);owned=true;}refresh(cancel);return state();
        }catch(IOException|RuntimeException error){if(!retainHealthy||!(transport instanceof WifiTransport)||!isConnected()||cancel.getAsBoolean())close();throw error;}
    }
    public boolean isConnected(){Transport current=transport;return current!=null&&current.isOpen();}
    /** Original prepared-session read-only heartbeat: built-in Picture Control1. */
    void keepAlive(String expected,BooleanSupplier cancel)throws IOException{
        if(!session.equals(expected)||!isConnected())throw new IOException("槽位会话已变化，未发送保活请求。");
        check(cancel);long transaction=next++;
        try{PictureControlData.parse(read(0x90cc,transaction,1,0));}
        catch(PtpResponseException response){
            if(response.transactionId()!=transaction)throw new PtpProtocolException("无线保活响应的事务编号不匹配。",response);
            if(response.responseCode()==0x2002||response.responseCode()==0x2019)return;
            throw response;
        }
        check(cancel);
    }
    Transport transportSnapshot(){return transport;}
    void detachTransport(Transport expected){if(transport==expected){transport=null;owned=false;}}
    static void requireReadCapabilities(PtpDeviceInfo device)throws IOException{
        if(device==null||!device.isNikonCamera())throw new IOException("当前设备未确认尼康身份，未发送优化校准命令。");
        for(int required:new int[]{0x1002,0x1003,0x90cc,0x90cf})if(!device.supportsOperation(required))throw new IOException("相机未声明优化校准读取能力，已停止。");
    }
    PhotoCameraClient releaseAlbum(String expectedSession)throws IOException {
        if(!session.equals(expectedSession))throw new IOException("槽位会话已变化。");
        Transport current=transport;if(!(current instanceof WifiTransport))return null;
        PhotoCameraClient album=((WifiTransport)current).release(next);
        if(album!=null){transport=null;owned=false;preparation=null;requested=null;confirmed=null;}
        return album;
    }
    public Object request(String op,Map<String,Object> p,BooleanSupplier cancel)throws IOException {
        if(op.equals("camera.slots.close")){if(!session.equals(p.get("session")))throw new IOException("槽位会话已变化。");close();return SharedRuntime.map("closed",true);}
        require(p);check(cancel);
        if(op.equals("camera.slots.refresh")){refresh(cancel);return state();}
        if(op.equals("camera.slots.status"))return state();
        if(op.equals("camera.slots.prepare"))return prepare(p,cancel);
        if(op.equals("camera.slots.execute"))return execute(p,cancel);
        if(op.equals("camera.slots.reconcile"))return reconcile(cancel);
        if(op.equals("camera.slots.acknowledge")){
            Map<String,Object> record=journal.read();
            if(!Boolean.TRUE.equals(p.get("confirmedOnCamera"))||!Objects.equals(p.get("actionId"),record.get("actionId"))||!device.model().equals(record.get("model")))throw new IOException("请先连接原相机并手动核对槽位结果。");
            record.put("pending",false);record.put("parametersPending",false);record.put("parametersManuallyChecked",true);record.put("phase",Boolean.TRUE.equals(record.get("presetVerified"))?"verified":"manuallyChecked");journal.save(record);return state();
        }
        throw new IOException("未知的槽位操作。");
    }
    private Object prepare(Map<String,Object> p,BooleanSupplier cancel)throws IOException {
        if(consumed)throw new IOException("本次连接已尝试过一次操作，请关闭后重新读取槽位。");
        if(Boolean.TRUE.equals(journal.read().get("pending"))||Boolean.TRUE.equals(journal.read().get("parametersPending")))throw new IOException("上次操作结果待核对，请先只读核对；不会重复写入。");
        String kind=SharedRuntime.text(p,"kind",16);int target=SharedRuntime.integer(p,"target",0);target(target);
        byte[] old=slots.get(target);if(old==null)throw new IOException("目标槽位不属于当前快照。");
        PictureControlData before=PictureControlData.parse(old);String explanation="";
        if(kind.equals("delete")){
            if(!device.supportsOperation(0x90ce)||before.hasNoBasePictureControl())throw new IOException("此槽位为空或相机未提供删除能力。");
            requested=null;
        }else if(kind.equals("write")){
            if(!device.supportsOperation(0x90cd))throw new IOException("相机未提供预设写入能力。");
            if(p.containsKey("source")){
                int source=SharedRuntime.integer(p,"source",0);target(source);if(source==target)throw new IOException("来源和目标必须是不同的槽位。");
                requested=slots.get(source);if(requested==null)throw new IOException("来源槽位无效。");requested=requested.clone();
                PictureControlWriteValidation.validateConvertedData(requested);explanation="将当前相机槽位复制到目标；不会选择或应用此预设。";
            }else{
                String path=SharedRuntime.text(p,"path",4096);File file=new File(path).getCanonicalFile();
                if(!file.toPath().startsWith(root.toPath())||!file.isFile()||file.length()!=638)throw new IOException("请选择已导入 App 的受支持 NCP 文件。");
                byte[] original=Files.readAllBytes(file.toPath());
                NcpPictureControlConverter.Conversion conversion=NcpPictureControlConverter.convert(original,SharedRuntime.integer(p,"middleQuarter",0),SharedRuntime.integer(p,"clarityQuarter",0));
                requested=conversion.dataBytes();PictureControlWriteValidation.validateConvertedData(requested);explanation=conversion.toDisplayText();
            }
        }else throw new IOException("请选择写入或删除。");
        CameraParameterRequest parameters=SharedSlotParameters.parse(p.get("parameters"));
        if(!kind.equals("write")&&!parameters.isEmpty())throw new IOException("删除槽位时不能调整拍摄参数。");
        check(cancel);confirmed=old.clone();
        preparation=SharedRuntime.map("confirmationId",UUID.randomUUID().toString(),"session",session,"snapshot",snapshot,"kind",kind,"target",target,"targetLabel","C"+(target-200),"beforeName",before.registrationName(),"beforeSha256",SharedCameraMutationStore.sha(old),"overwrite",!before.hasNoBasePictureControl(),"name",requested==null?"":PictureControlData.parse(requested).registrationName(),"desiredSha256",requested==null?"":SharedCameraMutationStore.sha(requested),"explanation",explanation);
        if(p.containsKey("source"))preparation.put("source",p.get("source"));
        preparation.put("parameters",SharedSlotParameters.values(parameters));preparation.put("parameterSummary",parameters.summary());
        return new LinkedHashMap<>(preparation);
    }
    private Object execute(Map<String,Object> p,BooleanSupplier cancel)throws IOException {
        if(consumed||preparation==null||!Objects.equals(p.get("confirmationId"),preparation.get("confirmationId"))||!Boolean.TRUE.equals(p.get("confirmed")))throw new IOException("确认已失效，请重新读取并确认目标槽位。");
        if(Boolean.TRUE.equals(journal.read().get("pending")))throw new IOException("上次操作仍待核对，本次未写入。");
        Transport channel=currentTransport();Map<String,Object> plan=preparation;preparation=null;
        int target=((Number)plan.get("target")).intValue();boolean deleting=plan.get("kind").equals("delete");
        PtpDeviceInfo fresh=PtpDeviceInfo.parseRedacted(read(0x1001,next++));
        if(!fresh.isNikonCamera()||!fresh.model().equals(device.model()))throw new IOException("确认后相机身份变化，已停止。");
        for(int required:new int[]{0x90cc,0x90cf,deleting?0x90ce:0x90cd})if(!fresh.supportsOperation(required))throw new IOException("确认后相机能力变化，已停止。");
        PictureControlCapability.parse(read(0x90cf,next++,1));Map<Integer,byte[]> before=readSlots(cancel);
        if(plan.get("source") instanceof Number)match(requested,before.get(((Number)plan.get("source")).intValue()));
        match(confirmed,before.get(target));
        if(deleting){
            channel.authorizeDeletion(target);
            if(fresh.supportsOperation(0x1015))for(int property:fresh.devicePropertiesSupported())if(property==0xd200||property==0xd237){
                byte[] value=read(0x1015,next++,property);if(value.length!=1&&value.length!=2&&value.length!=4)throw new IOException("当前预设状态无法核对，未删除。");
                long active=0;for(int i=0;i<value.length;i++)active|=(value[i]&255L)<<(8*i);
                if(active==target)throw new IOException("相机正在使用此槽位，请在机身切换其他预设后重新确认。");
            }
        }
        check(cancel);byte[] finalTarget=read(0x90cc,next++,target,0);PictureControlData.parse(finalTarget);match(confirmed,finalTarget);
        Map<String,Object> record=new LinkedHashMap<>(plan);record.put("pending",true);record.put("cameraId",cameraId);record.put("model",device.model());record.put("actionId",UUID.randomUUID().toString());record.put("phase","resultUnknown");record.put("time",System.currentTimeMillis());
        Map<String,Object> other=new LinkedHashMap<>();for(Map.Entry<Integer,byte[]> item:before.entrySet())if(item.getKey()!=target)other.put(String.valueOf(item.getKey()),SharedCameraMutationStore.sha(item.getValue()));record.put("otherSlots",other);
        journal.save(record);consumed=true; // The durable intent and one-shot budget precede mutation.
        try{
            long transaction=next++;
            if(deleting)PtpValidation.requireOkResponse(channel.command(0x90ce,transaction,target),transaction);
            else PtpValidation.requireOkResponse(channel.send(0x90cd,transaction,requested.clone(),target,0),transaction);
            record.put("acknowledged",true);journal.save(record);
            Map<Integer,byte[]> after=readSlots(cancel);slots=after;snapshot=UUID.randomUUID().toString();
            boolean equal=deleting?PictureControlData.parse(after.get(target)).hasNoBasePictureControl():Arrays.equals(requested,after.get(target));
            for(Map.Entry<Integer,byte[]> item:before.entrySet())if(item.getKey()!=target&&!Arrays.equals(item.getValue(),after.get(item.getKey())))equal=false;
            if(!equal)throw new IOException("相机已响应，但读回或其他槽位与预期不同；请核对，不会自动重试或还原。");
            record.put("pending",false);record.put("phase","verified");record.put("presetVerified",true);record.put("readbackSha256",SharedCameraMutationStore.sha(after.get(target)));journal.save(record);
            if(!deleting)applyParameters(record,fresh,channel,cancel);
        }catch(PtpResponseException rejected){record.put("phase",Boolean.TRUE.equals(record.get("acknowledged"))?"resultUnknown":"rejected");record.put("pending",Boolean.TRUE.equals(record.get("acknowledged")));record.put("message",rejected.getMessage());journal.save(record);}
        catch(IOException failure){owned=false;channel.close();record.put("message",failure.getMessage());journal.save(record);}
        return state();
    }
    private void applyParameters(Map<String,Object> record,PtpDeviceInfo fresh,Transport channel,BooleanSupplier cancel)throws IOException {
        CameraParameterRequest requested=SharedSlotParameters.parse(record.get("parameters"));
        CameraParameterController.Result result=CameraParameterController.prepare(requested);
        if(requested.isEmpty()){record.put("parameterResult",SharedSlotParameters.result(result));journal.save(record);return;}
        record.put("parametersPending",true);record.put("pending",true);record.put("parameterResult",SharedSlotParameters.result(result));journal.save(record);
        try{
            CameraParameterController.apply(result,fresh.supportsOperation(0x1014)&&fresh.supportsOperation(0x1015)&&fresh.supportsOperation(0x1016),new CameraParameterController.Access(){
                public byte[] get(int operation,int code)throws IOException{check(cancel);return read(operation,next++,code);}
                public void authorize(Map<Integer,byte[]> values)throws IOException{check(cancel);channel.authorizeParameters(values);}
                public void set(int code,byte[] value)throws IOException{
                    check(cancel);record.put("parameterAttemptedCode",code);record.put("parameterResult",SharedSlotParameters.result(result));journal.save(record);
                    long transaction=next++;PtpValidation.requireOkResponse(channel.send(0x1016,transaction,value,code),transaction);
                }
            },snapshot->{record.put("parameterResult",SharedSlotParameters.result(snapshot));journal.save(record);});
        }catch(IOException failure){
            record.put("parameterMessage",failure.getMessage());
            // The old controller marks an interrupted attempted write uncertain. A failed
            // descriptor read before the first write does not claim a mutation occurred.
            if(result.uncertain){owned=false;channel.close();}
        }
        for(CameraParameterController.Change change:result.changes())if(change.status.equals("结果待核对")||change.status.equals("读回不一致")||change.status.equals("已写入，读回未确认"))result.uncertain=true;
        record.put("parametersPending",result.uncertain);record.put("pending",result.uncertain);record.put("parameterResult",SharedSlotParameters.result(result));journal.save(record);
    }
    private Object reconcile(BooleanSupplier cancel)throws IOException {
        Map<String,Object> record=journal.read();refresh(cancel);
        if(!Boolean.TRUE.equals(record.get("pending")))return state();
        if(!cameraId.equals(record.get("cameraId")))throw new IOException("请连接原相机后只读核对上次操作。");
        // Parameter writes are never replayed or implicitly acknowledged by a preset-only check.
        if(Boolean.TRUE.equals(record.get("presetVerified"))&&Boolean.TRUE.equals(record.get("parametersPending")))return state();
        int target=((Number)record.get("target")).intValue();target(target);byte[] actual=slots.get(target);
        boolean desired=record.get("kind").equals("delete")?PictureControlData.parse(actual).hasNoBasePictureControl():SharedCameraMutationStore.sha(actual).equals(record.get("desiredSha256"));
        boolean unchanged=SharedCameraMutationStore.sha(actual).equals(record.get("beforeSha256"));
        Object others=record.get("otherSlots");boolean othersMatch=others instanceof Map;
        if(othersMatch)for(Map.Entry<?,?> item:((Map<?,?>)others).entrySet()){int slot=Integer.parseInt(item.getKey().toString());if(!SharedCameraMutationStore.sha(slots.get(slot)).equals(item.getValue()))othersMatch=false;}
        if(othersMatch&&(desired||unchanged)){record.put("pending",false);record.put("phase",desired?"verifiedByReadback":"unchangedByReadback");record.put("readbackSha256",SharedCameraMutationStore.sha(actual));journal.save(record);}
        return state();
    }
    private void refresh(BooleanSupplier cancel)throws IOException {PictureControlCapability.parse(read(0x90cf,next++,1));slots=readSlots(cancel);snapshot=UUID.randomUUID().toString();preparation=null;}
    private Map<Integer,byte[]> readSlots(BooleanSupplier cancel)throws IOException {Map<Integer,byte[]> result=new LinkedHashMap<>();for(int item=201;item<=209;item++){check(cancel);byte[] bytes=read(0x90cc,next++,item,0);PictureControlData.parse(bytes);result.put(item,bytes.clone());}return result;}
    private Object state()throws IOException {
        List<Object> rows=new ArrayList<>();for(Map.Entry<Integer,byte[]> entry:slots.entrySet()){PictureControlData data=PictureControlData.parse(entry.getValue());rows.add(SharedRuntime.map("target",entry.getKey(),"label","C"+(entry.getKey()-200),"name",data.registrationName(),"empty",data.hasNoBasePictureControl(),"sha256",SharedCameraMutationStore.sha(entry.getValue()),"base",data.basePictureControl()));}
        return SharedRuntime.map("session",session,"snapshot",snapshot,"model",device==null?"":device.model(),"connected",isConnected(),"canWrite",device!=null&&device.supportsOperation(0x90cd)&&!consumed,"canDelete",device!=null&&device.supportsOperation(0x90ce)&&!consumed,"consumed",consumed,"items",rows,"action",journal.read());
    }
    private Transport currentTransport()throws IOException{Transport current=transport;if(current==null)throw new InterruptedIOException("槽位通道已取消。");return current;}
    private byte[] read(int op,long transaction,long...p)throws IOException {
        Transport current=currentTransport();
        try{byte[] bytes=current.read(op,transaction,p);if(bytes==null||bytes.length>1024*1024)throw new IOException("相机槽位数据超出范围。");return bytes;}
        catch(PtpResponseException known){throw known;}
        catch(IOException failure){owned=false;current.close();throw failure;}
    }
    private void command(int op,long transaction,long...p)throws IOException{PtpValidation.requireOkResponse(currentTransport().command(op,transaction,p),transaction);}
    private void require(Map<String,Object> p)throws IOException{Transport current=transport;if(current==null||!current.isOpen()||!session.equals(p.get("session")))throw new IOException("槽位会话已结束，请重新连接读取。");}
    private static void target(int target)throws IOException{if(target<201||target>209)throw new IOException("仅允许明确选择 C1–C9 槽位。");}
    private static void match(byte[] expected,byte[] actual)throws IOException{if(expected==null||!Arrays.equals(expected,actual))throw new IOException("目标槽位与确认快照不同，已停止；请重新读取确认。");}
    private static void check(BooleanSupplier cancel)throws IOException{if(cancel.getAsBoolean())throw new InterruptedIOException("槽位操作已取消。");}
    /** Lifecycle/cancellation only closes the channel; it must not interleave a PTP CloseSession. */
    public void abort(){Transport current=transport;if(current!=null)current.close();}
    @Override public void close(){Transport old=transport;transport=null;if(old!=null){if(owned&&old.isOpen())try{PtpValidation.requireOkResponse(old.command(0x1003,next++),next-1);}catch(IOException ignored){}old.close();}owned=false;preparation=null;requested=null;confirmed=null;}
}
