package cc.huevia.sharedapp;

import android.hardware.usb.*;
import android.os.SystemClock;
import cc.huevia.ptp.*;
import cc.huevia.shared.*;
import cc.huevia.album.PhotoCameraClient;
import java.io.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.locks.ReentrantLock;
import java.util.function.LongFunction;

/** Dedicated raw USB PTP owner. Android's MTP session must be closed before this is constructed. */
final class NativeUsbSlots implements SharedSlots.Transport {
    private final UsbDeviceConnection connection;
    private final UsbInterface intf;
    private final UsbEndpoint in,out;
    private final PtpContainerReader reader;
    private SharedSlotTransportGuard guard=new SharedSlotTransportGuard();
    private final ReentrantLock wire=new ReentrantLock();
    private boolean sessionOwned,photoMode;
    private long photoNext=1,inherited;
    private LongFunction<PhotoCameraClient> albumFactory;
    private final AtomicBoolean closed=new AtomicBoolean();
    private final byte[] buffer=new byte[16384];
    private int offset,limit;
    private long deadline;
    NativeUsbSlots(UsbDevice device,UsbManager manager)throws IOException {
        if(device.getVendorId()!=0x04b0||!manager.hasPermission(device))throw new IOException("请先授权尼康 USB 相机。");
        UsbInterface selected=null;UsbEndpoint input=null,output=null;
        for(int i=0;i<device.getInterfaceCount();i++){
            UsbInterface candidate=device.getInterface(i);if(candidate.getInterfaceClass()!=UsbConstants.USB_CLASS_STILL_IMAGE)continue;
            UsbEndpoint a=null,b=null;for(int j=0;j<candidate.getEndpointCount();j++){
                UsbEndpoint endpoint=candidate.getEndpoint(j);if(endpoint.getType()!=UsbConstants.USB_ENDPOINT_XFER_BULK)continue;
                if(endpoint.getDirection()==UsbConstants.USB_DIR_IN)a=endpoint;else if(endpoint.getDirection()==UsbConstants.USB_DIR_OUT)b=endpoint;
            }
            if(a!=null&&b!=null&&a.getMaxPacketSize()>0&&b.getMaxPacketSize()>0&&buffer.length%a.getMaxPacketSize()==0&&buffer.length%b.getMaxPacketSize()==0){selected=candidate;input=a;output=b;break;}
        }
        if(selected==null)throw new IOException("相机没有双向 PTP bulk 端点。");
        intf=selected;in=input;out=output;connection=manager.openDevice(device);
        if(connection==null)throw new IOException("USB 相机无法打开。");
        try{if(!connection.claimInterface(intf,false))throw new IOException("USB PTP 接口被占用，请关闭其他相机应用后重连。");reader=new PtpContainerReader(this::readBytes,16*1024*1024);}
        catch(IOException|RuntimeException failure){connection.close();throw failure;}
    }
    @Override public boolean isOpen(){return !closed.get();}
    byte[] openPhoto()throws IOException{
        return exchange(()->{
            byte[] info=rawRead(0x1001,0,new long[0]);
            begin(0x1002,0,new long[]{1});PtpValidation.requireOkResponse(next(),0);
            sessionOwned=true;photoMode=true;photoNext=1;return info;
        });
    }
    byte[] photoRead(int op,int max,long...p)throws IOException{
        if(!(op==0x1001&&p.length==0||op==0x1004&&p.length==0||op==0x1007&&p.length==3||op==0x1008&&p.length==1||op==0x100a&&p.length==1))throw new IOException("USB 照片通道拒绝未授权读取。");
        return exchange(()->{requirePhoto();byte[] bytes=rawRead(op,photoNext++,p);if(bytes.length>max)throw new IOException("USB 相机返回数据超出范围。");return bytes;});
    }
    long photoReadTo(OutputStream destination,long max,long expected,PhotoCameraClient.Progress progress,long handle)throws IOException{
        if(expected<4||expected>max||expected>512L*1024*1024)throw new IOException("USB 原文件大小超出范围。");
        return exchange(()->{
            requirePhoto();long tx=photoNext++;begin(0x1009,tx,new long[]{handle});
            byte[] header=new byte[12];fully(header,0,12);
            long length=u32(header,0);int type=u16(header,4),code=u16(header,6);long transaction=u32(header,8);
            if(type==PtpContainer.RESPONSE){
                if(length<12||length>32||(length-12)%4!=0||transaction!=tx)throw new IOException("USB 原文件响应无效。");
                fully(new byte[(int)length-12],0,(int)length-12);throw new PtpResponseException(code,tx);
            }
            if(type!=PtpContainer.DATA||code!=0x1009||transaction!=tx||length-12!=expected)throw new IOException("USB 原文件长度或事务与确认信息不同。");
            byte[] chunk=new byte[256*1024];long received=0,totalDeadline=SystemClock.elapsedRealtime()+600000;
            while(received<expected){deadline=Math.min(totalDeadline,SystemClock.elapsedRealtime()+30000);int count=(int)Math.min(chunk.length,expected-received);fully(chunk,0,count);destination.write(chunk,0,count);received+=count;progress.onProgress(received,expected);}
            deadline=Math.min(totalDeadline,SystemClock.elapsedRealtime()+30000);
            PtpValidation.requireOkResponse(next(),tx);return received;
        });
    }
    private static int u16(byte[] b,int i){return (b[i]&255)|((b[i+1]&255)<<8);}
    private static long u32(byte[] b,int i){return (u16(b,i)&65535L)|((long)u16(b,i+2)<<16);}
    private void fully(byte[] bytes,int at,int count)throws IOException{for(int n=0;n<count;){int read=readBytes(bytes,at+n,count-n);if(read<1)throw new EOFException("USB 数据不完整。");n+=read;}}
    private void requirePhoto()throws IOException{check();if(!photoMode||!sessionOwned)throw new IOException("USB 照片会话已移交。");}
    void adoptSlots(LongFunction<PhotoCameraClient> factory)throws IOException{
        requirePhoto();SharedSlotTransportGuard nextGuard=new SharedSlotTransportGuard();nextGuard.adoptSession(photoNext);guard=nextGuard;inherited=photoNext;albumFactory=factory;photoMode=false;
    }
    @Override public long inheritedTransaction(){return inherited;}
    @Override public PhotoCameraClient releaseAlbum(long next)throws IOException{
        if(!isOpen()||photoMode||!guard.canReleaseSession()||albumFactory==null)return null;
        photoNext=next;photoMode=true;inherited=0;LongFunction<PhotoCameraClient> factory=albumFactory;albumFactory=null;return factory.apply(next);
    }
    private byte[] rawRead(int op,long tx,long[] p)throws IOException{
        begin(op,tx,p);PtpContainer data=next();
        if(data.type()==PtpContainer.RESPONSE){PtpValidation.requireOkResponse(data,tx);throw new IOException("相机没有返回数据。");}
        byte[] bytes=PtpValidation.requireData(data,tx,op);PtpValidation.requireOkResponse(next(),tx);return bytes;
    }
    @Override public void authorizeDeletion(int target)throws IOException{guard.authorizeDeletion(target);}
    @Override public void authorizeParameters(java.util.Map<Integer,byte[]> values)throws IOException{guard.authorizeParameters(values);}
    @Override public byte[] read(int op,long tx,long...p)throws IOException {
        guard.read(op,tx,p);return exchange(()->{
            photoNext=Math.max(photoNext,tx+1);byte[] bytes=rawRead(op,tx,p);guard.observeReadback(op,bytes,p);return bytes;
        });
    }
    @Override public PtpContainer command(int op,long tx,long...p)throws IOException {
        guard.command(op,tx,p);return exchange(()->{photoNext=Math.max(photoNext,tx+1);begin(op,tx,p);PtpContainer response=next();PtpValidation.requireOkResponse(response,tx);if(op==0x1002)sessionOwned=true;if(op==0x1003)sessionOwned=false;return response;});
    }
    @Override public PtpContainer send(int op,long tx,byte[] bytes,long...p)throws IOException {
        guard.send(op,tx,bytes,p);return exchange(()->{
            photoNext=Math.max(photoNext,tx+1);
            begin(op,tx,p);byte[] data=PtpContainer.data(op,tx,bytes).toBytes();write(data);
            if(data.length%out.getMaxPacketSize()==0&&connection.bulkTransfer(out,new byte[0],0,timeout())<0)throw new IOException("USB 数据结束包未确认。");
            PtpContainer response=next();PtpValidation.requireOkResponse(response,tx);guard.observeWriteResponse(op,tx,response);return response;
        });
    }
    private void begin(int op,long tx,long[] p)throws IOException {check();deadline=SystemClock.elapsedRealtime()+30000;write(PtpContainer.command(op,tx,p).toBytes());}
    private PtpContainer next()throws IOException{PtpContainer value=reader.read();if(value==null)throw new IOException("USB 相机在完整响应前断开。");return value;}
    private void write(byte[] bytes)throws IOException {
        for(int position=0;position<bytes.length;){check();int count=Math.min(buffer.length,bytes.length-position);int written=connection.bulkTransfer(out,bytes,position,count,timeout());if(written!=count)throw new IOException("USB 命令或数据未完整确认；未重新发送。");position+=written;}
    }
    private int readBytes(byte[] destination,int at,int count)throws IOException {
        check();while(offset==limit){int received=connection.bulkTransfer(in,buffer,buffer.length,timeout());if(received<0)throw new IOException("USB 响应超时或断开。");offset=0;limit=received;if(received==0)timeout();}
        int copied=Math.min(count,limit-offset);System.arraycopy(buffer,offset,destination,at,copied);offset+=copied;return copied;
    }
    private void check()throws IOException {if(closed.get()||Thread.currentThread().isInterrupted())throw new IOException("USB 槽位连接已关闭或取消。");}
    private int timeout()throws IOException {check();long remaining=deadline-SystemClock.elapsedRealtime();if(remaining<=0)throw new IOException("USB PTP 事务超时。");return (int)Math.min(5000,remaining);}
    private interface Exchange<T>{T run()throws IOException;}
    private <T>T exchange(Exchange<T> work)throws IOException {
        wire.lock();
        try{return work.run();}catch(PtpResponseException known){throw known;}
        catch(IOException failure){abort();throw failure;}catch(RuntimeException error){abort();throw new IOException("USB PTP 阶段无法确认，连接已关闭。",error);}finally{wire.unlock();}
    }
    void abort(){if(!closed.compareAndSet(false,true))return;try{connection.releaseInterface(intf);}finally{connection.close();}}
    @Override public void close(){
        if(!wire.tryLock()){abort();return;}
        try{if(!closed.get()&&sessionOwned){try{deadline=SystemClock.elapsedRealtime()+1500;write(PtpContainer.command(0x1003,photoNext++).toBytes());PtpValidation.requireOkResponse(next(),photoNext-1);}catch(IOException ignored){}sessionOwned=false;}abort();}finally{wire.unlock();}
    }
}
