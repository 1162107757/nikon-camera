package cc.huevia.sharedapp;

import android.hardware.usb.*;
import android.os.SystemClock;
import cc.huevia.ptp.*;
import cc.huevia.shared.*;
import java.io.*;
import java.util.concurrent.atomic.AtomicBoolean;

/** Dedicated raw USB PTP owner. Android's MTP session must be closed before this is constructed. */
final class NativeUsbSlots implements SharedSlots.Transport {
    private final UsbDeviceConnection connection;
    private final UsbInterface intf;
    private final UsbEndpoint in,out;
    private final PtpContainerReader reader;
    private final SharedSlotTransportGuard guard=new SharedSlotTransportGuard();
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
        try{if(!connection.claimInterface(intf,false))throw new IOException("USB PTP 接口被占用，请关闭其他相机应用后重连。");reader=new PtpContainerReader(this::readBytes,1024*1024);}
        catch(IOException|RuntimeException failure){connection.close();throw failure;}
    }
    @Override public boolean isOpen(){return !closed.get();}
    @Override public void authorizeDeletion(int target)throws IOException{guard.authorizeDeletion(target);}
    @Override public void authorizeParameters(java.util.Map<Integer,byte[]> values)throws IOException{guard.authorizeParameters(values);}
    @Override public byte[] read(int op,long tx,long...p)throws IOException {
        guard.read(op,tx,p);return exchange(()->{
            begin(op,tx,p);PtpContainer data=next();
            if(data.type()==PtpContainer.RESPONSE){PtpValidation.requireOkResponse(data,tx);throw new IOException("相机成功响应但没有返回数据。");}
            byte[] bytes=PtpValidation.requireData(data,tx,op);PtpValidation.requireOkResponse(next(),tx);guard.observeReadback(op,bytes,p);return bytes;
        });
    }
    @Override public PtpContainer command(int op,long tx,long...p)throws IOException {
        guard.command(op,tx,p);return exchange(()->{begin(op,tx,p);PtpContainer response=next();PtpValidation.requireOkResponse(response,tx);return response;});
    }
    @Override public PtpContainer send(int op,long tx,byte[] bytes,long...p)throws IOException {
        guard.send(op,tx,bytes,p);return exchange(()->{
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
        try{return work.run();}catch(PtpResponseException known){throw known;}
        catch(IOException failure){close();throw failure;}catch(RuntimeException error){close();throw new IOException("USB PTP 阶段无法确认，连接已关闭。",error);}
    }
    @Override public void close(){if(!closed.compareAndSet(false,true))return;try{connection.releaseInterface(intf);}finally{connection.close();}}
}
