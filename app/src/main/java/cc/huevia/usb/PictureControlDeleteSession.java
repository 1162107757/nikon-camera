package cc.huevia.usb;

import cc.huevia.picturecontrol.PictureControlCapability;
import cc.huevia.picturecontrol.PictureControlData;
import cc.huevia.ptp.PtpContainer;
import cc.huevia.ptp.PtpDeviceInfo;
import cc.huevia.ptp.PtpProtocolException;
import cc.huevia.ptp.PtpResponseException;
import cc.huevia.ptp.PtpValidation;
import java.io.*;
import java.util.*;
import org.json.*;

/** One explicitly confirmed custom-slot deletion. No object deletion, upload, selection or property writes. */
public final class PictureControlDeleteSession {
    public interface Operations extends PictureControlReadSession.Operations {
        void authorizeDeletion(int target) throws IOException;
    }
    public static final class Confirmation {
        public final int target;
        public final String name, sha256, model;
        private final byte[] bytes;
        public Confirmation(UsbPictureControlProbe.ItemRecord item, String model) throws IOException {
            if(item==null||item.itemCode<201||item.itemCode>209||!item.parsed||item.empty)throw new IOException("请选择已有预设的 C1–C9 槽位。");
            PictureControlData parsed=PictureControlData.parse(item.rawBytes());
            if(parsed.basePictureControl()==0)throw new IOException("此槽位已经为空。");
            target=item.itemCode;bytes=item.rawBytes().clone();sha256=UsbPictureControlProbe.sha256(bytes);
            if(!sha256.equals(item.sha256))throw new IOException("槽位快照校验失败，请重新读取。");
            name=parsed.registrationName();this.model=model==null?"":model;
        }
        public byte[] backupBytes(){return bytes.clone();}
        private void matches(UsbPictureControlProbe.ItemRecord item)throws IOException{
            if(item==null||item.itemCode!=target||item.empty||!Arrays.equals(bytes,item.rawBytes()))throw new IOException("槽位内容已变化，本次未删除。请重新读取后确认。");
        }
    }
    public static final class Result {
        public String model="",phase="准备删除",error="",cleanupError="";
        public int target; public boolean attempted,acknowledged,verified,sessionClosed,sessionRetained,protocolUnconfirmed;
        public byte[] capability=new byte[0]; public int[] operations=new int[0];
        public final List<UsbPictureControlProbe.ItemRecord> before=new ArrayList<>(),after=new ArrayList<>();
        public final List<String> commands=new ArrayList<>();
        public String toJsonString()throws JSONException{
            JSONObject json=new JSONObject().put("type","custom_picture_control_delete").put("schemaVersion",1).put("model",model)
                    .put("target",target).put("phase",phase).put("error",error).put("cleanupError",cleanupError).put("attempted",attempted)
                    .put("acknowledged",acknowledged).put("verified",verified).put("sessionClosed",sessionClosed).put("sessionRetained",sessionRetained)
                    .put("protocolUnconfirmed",protocolUnconfirmed).put("commands",new JSONArray(commands));
            JSONArray snapshots=new JSONArray();for(UsbPictureControlProbe.ItemRecord item:before)snapshots.put(new JSONObject().put("item",item.itemCode).put("sha256",item.sha256).put("empty",item.empty));
            json.put("before",snapshots);snapshots=new JSONArray();for(UsbPictureControlProbe.ItemRecord item:after)snapshots.put(new JSONObject().put("item",item.itemCode).put("sha256",item.sha256).put("empty",item.empty));return json.put("after",snapshots).toString(2);
        }
    }
    private final Operations operations;private final Confirmation confirmation;private final Result result;
    private long next;private boolean owned,started,abort;
    public PictureControlDeleteSession(Operations operations,Confirmation confirmation,Result result){this(operations,confirmation,result,0);}
    PictureControlDeleteSession(Operations operations,Confirmation confirmation,Result result,long retainedNext){
        this.operations=Objects.requireNonNull(operations);this.confirmation=Objects.requireNonNull(confirmation);this.result=Objects.requireNonNull(result);
        if(retainedNext<0||retainedNext>0xffffffffL)throw new IllegalArgumentException("Invalid transaction");next=retainedNext;owned=retainedNext>0;result.target=confirmation.target;
    }
    public void run()throws IOException{
        if(started)throw new IOException("删除操作不能重复执行，请重新读取槽位。");started=true;
        try{
            PtpDeviceInfo device=PtpDeviceInfo.parseRedacted(query(0x1001,owned?next++:0));result.model=device.model();result.operations=device.operationsSupported();
            if(!device.isNikonCamera()||!confirmation.model.equals(device.model()))throw new IOException("相机与确认时不一致，本次未删除。");
            for(int required:new int[]{0x1002,0x1003,0x90cc,0x90ce,0x90cf})if(!device.supportsOperation(required))throw new IOException("相机未开放预设删除接口，本次未删除。");
            if(!owned){command(0x1002,0,1);owned=true;next=1;}
            result.capability=query(0x90cf,next++,1);PictureControlCapability.parse(result.capability);
            for(int item=201;item<=209;item++)result.before.add(read(item));
            confirmation.matches(find(result.before,confirmation.target));
            operations.authorizeDeletion(confirmation.target);
            // Do not silently change the photo/movie Picture Control by removing an active slot.
            if(device.supportsOperation(0x1015))for(int property:device.devicePropertiesSupported())if(property==0xd200||property==0xd237){
                byte[] value=query(0x1015,next++,property);
                if(value.length!=1&&value.length!=2&&value.length!=4)throw new IOException("当前预设状态无法核对，本次未删除。");
                long active=0;for(int i=0;i<value.length;i++)active|=(value[i]&255L)<<(8*i);
                if(active==confirmation.target)throw new IOException("相机正在使用此槽位，请先在相机切换其他预设，再重新读取并删除。");
            }
            // Nothing intervenes between this last content check and the only destructive command.
            confirmation.matches(read(confirmation.target));
            result.phase="删除槽位";result.attempted=true;command(0x90ce,next++,confirmation.target);result.acknowledged=true;
            result.phase="读回核对";
            for(int item=201;item<=209;item++)result.after.add(read(item));
            if(!find(result.after,confirmation.target).empty)throw new IOException("相机已响应，但目标槽位尚未确认为空。请重新读取核对，勿重复删除。");
            for(int item=201;item<=209;item++)if(item!=confirmation.target&&!Arrays.equals(find(result.before,item).rawBytes(),find(result.after,item).rawBytes()))
                throw new IOException("删除后其他槽位发生变化，请重新读取核对。未自动恢复或重试。");
            result.verified=true;result.phase="删除已核对";
        }catch(IOException failure){result.error=failure.getMessage()==null?failure.toString():failure.getMessage();throw failure;}
        catch(RuntimeException failure){abort=true;result.protocolUnconfirmed=true;result.error="删除响应无法核对。";throw new IOException(result.error,failure);}
    }
    private UsbPictureControlProbe.ItemRecord read(int item)throws IOException{
        byte[] bytes=query(0x90cc,next++,item,0);PictureControlData data=PictureControlData.parse(bytes);
        UsbPictureControlProbe.ItemRecord record=new UsbPictureControlProbe.ItemRecord(item,bytes);record.basePictureControl=data.basePictureControl();record.registrationName=data.registrationName();record.customCurveEnabled=data.customCurveEnabled();record.empty=data.basePictureControl()==0;record.parsed=true;return record;
    }
    private byte[] query(int op,long transaction,long...parameters)throws IOException{
        trace(op,transaction,parameters);try{return operations.getData(op,transaction,parameters);}catch(PtpResponseException error){if(error.transactionId()!=transaction){abort=true;result.protocolUnconfirmed=true;}throw error;}catch(IOException error){abort=true;result.protocolUnconfirmed=true;throw error;}
    }
    private void command(int op,long transaction,long...parameters)throws IOException{
        trace(op,transaction,parameters);try{PtpValidation.requireOkResponse(operations.command(op,transaction,parameters),transaction);}catch(PtpResponseException error){if(error.transactionId()!=transaction){abort=true;result.protocolUnconfirmed=true;}throw error;}catch(IOException error){abort=true;result.protocolUnconfirmed=true;throw error;}
    }
    private void trace(int op,long transaction,long[] parameters)throws IOException{if(Thread.currentThread().isInterrupted())throw new InterruptedIOException("删除操作已取消。");result.commands.add(String.format(Locale.ROOT,"0x%04X tx=%d %s",op,transaction,Arrays.toString(parameters)));}
    public void closeSession()throws IOException{if(!owned||abort)return;try{command(0x1003,next++);result.sessionClosed=true;}finally{owned=false;}}
    long transferVerifiedSession()throws IOException{if(!owned||abort||!result.verified)throw new IOException("删除结果未核对，不能保留会话。");owned=false;return next;}
    public boolean mayCloseSession(){return owned&&!abort;}
    private static UsbPictureControlProbe.ItemRecord find(List<UsbPictureControlProbe.ItemRecord> values,int target)throws IOException{for(UsbPictureControlProbe.ItemRecord item:values)if(item.itemCode==target)return item;throw new IOException("槽位读取不完整。");}
}
