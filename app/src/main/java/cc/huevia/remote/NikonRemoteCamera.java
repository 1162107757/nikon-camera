package cc.huevia.remote;

import cc.huevia.ptp.*;
import java.io.IOException;
import java.util.*;

/** Nikon capture operations. All calls are serialized by the album's existing worker. */
public final class NikonRemoteCamera {
    public static final int START=0x9201,END=0x9202,FRAME=0x9203,AF=0x90c1,AREA=0x9205,CAPTURE=0x9207;
    public static final int[] PROPERTIES={0x5001,0x5007,0x500d,0x500f,0x5010,0x500e,0x500a,0x5004,0x5013,0xd061,0xd161,0xd1a2,0xd1a4,0xd054};
    private final RemoteTransport transport;
    private final PtpDeviceInfo info;
    private final Set<Integer> supportedProperties=new HashSet<>(),unavailable=new HashSet<>();
    private final Map<Integer,RemoteProperty> descriptors=new HashMap<>();
    public final String identity,model;
    public final boolean liveView,capture,autoFocus,pointFocus;
    public NikonRemoteCamera(RemoteTransport transport,PtpDeviceInfo info,String identity) throws IOException {
        if(transport==null||info==null||!info.isNikonCamera())throw new IOException("当前连接不是受支持的尼康遥控会话。");
        this.transport=transport;this.info=info;this.identity=identity;model=info.model();
        liveView=has(START)&&has(END)&&has(FRAME);capture=has(CAPTURE)&&has(0x1004)&&has(0x1007)&&has(0x1008);
        autoFocus=has(AF);pointFocus=autoFocus&&has(AREA);
        for(int value:info.devicePropertiesSupported())supportedProperties.add(value);
        if(has(0x90ca)){
            try{byte[] codes=transport.data(0x90ca,65536);if(codes.length<4)throw new IOException("厂商参数列表不完整。");
                long n=u32(codes,0);if(n>4096||codes.length!=4+n*2)throw new IOException("厂商参数列表长度无效。");
                for(int i=0;i<n;i++)supportedProperties.add(RemoteProperty.u16(codes,4+i*2));
            }catch(PtpResponseException unsupported){if(!optional(unsupported))throw unsupported;}
        }
    }
    private boolean has(int operation){return info.supportsOperation(operation);}
    public boolean isOpen(){return transport.isOpen();}
    public Map<Integer,Long> parameters() throws IOException {
        Map<Integer,Long> values=new HashMap<>();
        if(!has(0x1014)||!has(0x1015))return values;
        for(int code:PROPERTIES){
            if(!supportedProperties.contains(code)||unavailable.contains(code))continue;
            try{
                RemoteProperty old=descriptors.get(code);
                RemoteProperty current=old==null?RemoteProperty.descriptor(code,transport.data(0x1014,65536,code)):old.update(transport.data(0x1015,16,code));
                descriptors.put(code,current);values.put(code,current.value);
            }catch(PtpResponseException error){if(optional(error)){unavailable.add(code);descriptors.remove(code);}else if(error.responseCode()!=0x2019)throw error;}
        }
        return values;
    }
    public void startView() throws IOException {
        if(!liveView)throw new IOException("相机未开放实时取景能力。");
        if(has(0x1015)&&supportedProperties.contains(0xd1a2)){
            try{byte[] current=transport.data(0x1015,16,0xd1a2);if(current.length==1&&current[0]==1)return;}
            catch(PtpResponseException error){if(!optional(error)&&error.responseCode()!=0x2019)throw error;}
        }
        try{transport.command(START);}catch(PtpResponseException error){if(error.responseCode()!=0x2019)throw error;}
    }
    public void stopView() throws IOException {if(liveView&&isOpen())try{transport.command(END);}catch(PtpResponseException error){if(error.responseCode()!=0xa00b)throw error;}}
    public RemoteLiveFrame frame() throws IOException {if(!liveView)throw new IOException("相机未开放实时取景能力。");try{return RemoteLiveFrame.parse(transport.data(FRAME,8*1024*1024));}catch(PtpResponseException error){if(error.responseCode()==0x2019||error.responseCode()==0xa004)return null;throw error;}}
    public void focus(RemoteLiveFrame frame,Double x,Double y) throws IOException {
        if(!autoFocus)throw new IOException("相机未开放遥控对焦能力。");
        if(x!=null){if(!pointFocus||frame==null)throw new IOException("相机未开放点按对焦能力。");int[] point=frame.focusPoint(x,y);transport.command(AREA,point[0],point[1]);}
        transport.command(AF);
    }
    public Set<Long> inventory() throws IOException {
        if(!capture)throw new IOException("相机未开放拍摄与结果核对能力。");
        Set<Long> handles=new LinkedHashSet<>();long[] storages=PtpStorageIds.parse(transport.data(0x1004,4096));
        if(storages.length>64)throw new IOException("相机存储空间数量超过上限。");
        for(long storage:storages){
            try{for(long handle:PtpObjectHandles.parse(transport.data(0x1007,1024*1024,storage,0,0))){
                if(handle==0||handle==0xffffffffL)throw new IOException("相机照片索引无效。");handles.add(handle);
                if(handles.size()>20000)throw new IOException("相机对象超过 20000 个，请先整理存储卡。");
            }}catch(PtpResponseException error){if(error.responseCode()!=0x2013)throw error;}
        }
        if(storages.length==0)throw new IOException("未检测到可用存储卡，请在相机上检查。");
        return handles;
    }
    /** Called once per explicit user action, only after the durable journal has been written. */
    public void release() throws IOException {if(!capture)throw new IOException("相机未开放遥控快门能力。");transport.command(CAPTURE,0xffffffffL,0);}
    public List<CapturedPhoto> newPhotos(Set<Long> baseline) throws IOException {
        List<CapturedPhoto> result=new ArrayList<>();
        for(long handle:inventory())if(!baseline.contains(handle)){
            PtpObjectInfo object=PtpObjectInfo.parse(transport.data(0x1008,65536,handle));
            String name=object.filename().toLowerCase(Locale.ROOT);
            if(object.objectFormat()==0x3801||name.endsWith(".nef"))result.add(new CapturedPhoto(handle,object));
            if(result.size()>32)throw new IOException("检测到多张新照片，请先核对最近拍摄。");
        }
        return result;
    }
    public byte[] thumbnail(long handle) throws IOException {
        if(!has(0x100a))throw new IOException("相机未提供缩略图读取能力。");
        return transport.data(0x100a,4*1024*1024,handle);
    }
    public static boolean oneExposure(List<CapturedPhoto> photos){
        if(photos.isEmpty())return false;String stem=stem(photos.get(0).object.filename());
        for(CapturedPhoto photo:photos)if(!stem.equals(stem(photo.object.filename())))return false;
        return true;
    }
    private static String stem(String name){int dot=name.lastIndexOf('.');return (dot>0?name.substring(0,dot):name).toLowerCase(Locale.ROOT);}
    public static final class CapturedPhoto {
        public final long handle;public final PtpObjectInfo object;
        public CapturedPhoto(long handle,PtpObjectInfo object){this.handle=handle;this.object=object;}
        public boolean jpeg(){return object.objectFormat()==0x3801;}
    }
    private static boolean optional(PtpResponseException error){int c=error.responseCode();return c==0x2005||c==0x200a||c==0x201d||c==0x2006;}
    private static long u32(byte[] b,int o){return(b[o]&255L)|((b[o+1]&255L)<<8)|((b[o+2]&255L)<<16)|((b[o+3]&255L)<<24);}
}
