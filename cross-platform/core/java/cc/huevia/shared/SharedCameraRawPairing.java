package cc.huevia.shared;

import cc.huevia.album.*;
import cc.huevia.ptp.*;
import java.io.*;
import java.util.*;
import java.util.function.BooleanSupplier;

/** A complete all-card, read-only pairing inventory, isolated from the visible album pagination. */
public final class SharedCameraRawPairing {
    private final PhotoCameraClient client;
    private final String session;
    private final boolean trusted;
    private final String cameraId;
    private String jpegDescriptor="";
    private String token="",reason="";
    private long matched;
    private int objects,unavailable;
    private final LinkedHashMap<Long,PtpObjectInfo> candidates=new LinkedHashMap<>();
    SharedCameraRawPairing(PhotoCameraClient client,String session,boolean trusted){this(client,session,trusted,"");}
    SharedCameraRawPairing(PhotoCameraClient client,String session,boolean trusted,String cameraId){this.client=client;this.session=session;this.trusted=trusted;this.cameraId=cameraId;}
    Object open(long jpegHandle,PtpObjectInfo expected,BooleanSupplier cancel)throws IOException {
        if(SharedCamera.photoFormat(expected)!=PhotoFormat.JPEG)throw new IOException("请选择相机中的 JPEG 后核对 RAW。");
        PtpObjectInfo jpeg=PtpObjectInfo.parse(client.getData(0x1008,65536,jpegHandle));same(expected,jpeg);
        jpegDescriptor=SharedCameraMutationStore.sha(jpeg.toBytes());
        candidates.clear();objects=unavailable=0;matched=0;reason="";
        long[] storages=PtpStorageIds.parse(client.getData(0x1004,4096));if(storages.length>64)throw new IOException("相机存储空间数量超出范围。");
        Set<Long> all=new LinkedHashSet<>();
        for(long storage:storages){check(cancel);long[] handles;
            try{handles=PtpObjectHandles.parse(client.getData(0x1007,1024*1024,storage,0,0));}
            catch(PtpResponseException missing){if(missing.responseCode()!=0x2013)throw missing;unavailable++;continue;}
            for(long handle:handles){if(handle<1||handle>=0xffffffffL)throw new IOException("相机库存索引无效。");all.add(handle);if(all.size()>20000)throw new IOException("RAW 配对最多核对 20000 个对象，请先整理存储卡。");}
        }
        for(long handle:all){check(cancel);PtpObjectInfo info;
            try{info=PtpObjectInfo.parse(client.getData(0x1008,65536,handle));}
            catch(PtpResponseException gone){if(gone.responseCode()!=0x2009)throw gone;unavailable++;continue;}
            if(PhotoFormat.of(info)==PhotoFormat.NEF)candidates.put(handle,info);
        }
        objects=all.size();check(cancel);same(jpeg,PtpObjectInfo.parse(client.getData(0x1008,65536,jpegHandle)));
        long[] handles=new long[candidates.size()];PtpObjectInfo[] infos=new PtpObjectInfo[candidates.size()];int index=0;
        for(Map.Entry<Long,PtpObjectInfo> entry:candidates.entrySet()){handles[index]=entry.getKey();infos[index++]=entry.getValue();}
        try{matched=SharedRawPairing.uniqueHandle(jpeg,handles,infos,trusted&&unavailable==0&&storages.length>0,objects);reason="已核对同一相机、完整库存、文件名、拍摄时间和拍摄序列；请确认后接收。";}
        catch(IOException selection){reason=selection.getMessage();}
        if(unavailable>0)reason="有存储卡或对象无法读取，不能自动配对。"+reason;
        token=UUID.randomUUID().toString();return page(SharedRuntime.map("pairId",token,"offset",0,"limit",60));
    }
    Object page(Map<String,Object> p)throws IOException {
        require(p);int offset=SharedRuntime.integer(p,"offset",0),limit=SharedRuntime.integer(p,"limit",60);
        if(offset<0||offset>candidates.size()||limit<1||limit>60)throw new IOException("RAW 库存分页参数无效。");
        List<Object> rows=new ArrayList<>();int cursor=0,next=offset;
        for(Map.Entry<Long,PtpObjectInfo> item:candidates.entrySet()){if(cursor++<offset)continue;if(rows.size()==limit)break;rows.add(row(item.getKey(),item.getValue()));next++;}
        return SharedRuntime.map("session",session,"pairId",token,"cameraId",cameraId,"jpegDescriptor",jpegDescriptor,"matchedHandle",matched,"matched",matched==0?null:row(matched,candidates.get(matched)),"reason",reason,"objects",objects,"rawCount",candidates.size(),"unavailable",unavailable,"items",rows,"nextOffset",next,"hasMore",next<candidates.size());
    }
    PtpObjectInfo select(Map<String,Object> p,BooleanSupplier cancel)throws IOException {
        require(p);if(!Boolean.TRUE.equals(p.get("confirmed")))throw new IOException("请明确选择并确认 RAW 原文件。");
        Object value=p.get("handle");if(!(value instanceof Number)||((Number)value).doubleValue()!=((Number)value).longValue())throw new IOException("RAW 索引无效。");
        long handle=((Number)value).longValue();PtpObjectInfo selected=candidates.get(handle);if(selected==null)throw new IOException("RAW 不属于本次完整库存。");
        check(cancel);same(selected,PtpObjectInfo.parse(client.getData(0x1008,65536,handle)));check(cancel);return selected;
    }
    static Object row(long handle,PtpObjectInfo info){return SharedRuntime.map("handle",handle,"name",info.filename(),"bytes",info.compressedSize(),"width",info.imagePixWidth(),"height",info.imagePixHeight(),"raw",true,"storage",info.storageId(),"descriptor",SharedCameraMutationStore.sha(info.toBytes()),"parent",info.parentObject(),"capturedAt",info.captureDate(),"sequence",info.sequenceNumber());}
    private void require(Map<String,Object> p)throws IOException{if(token.isEmpty()||!token.equals(p.get("pairId"))||!client.isOpen())throw new IOException("RAW 配对库存已失效，请重新核对。");}
    private static void same(PtpObjectInfo first,PtpObjectInfo second)throws IOException{if(!Arrays.equals(first.toBytes(),second.toBytes()))throw new IOException("相机原文件已变化，请重新读取库存。");}
    private static void check(BooleanSupplier cancel)throws IOException{if(cancel.getAsBoolean())throw new InterruptedIOException("RAW 库存核对已取消。");}
}
