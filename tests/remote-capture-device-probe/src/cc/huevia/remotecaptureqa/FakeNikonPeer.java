package cc.huevia.remotecaptureqa;

import cc.huevia.album.PtpIpClient;
import cc.huevia.ptp.PtpObjectInfo;
import java.io.*;
import java.net.*;
import java.util.*;
import java.util.concurrent.CopyOnWriteArrayList;

/** In-process byte-framed PTP/IP test peer. No network, real camera or production demo mode. */
final class FakeNikonPeer implements PtpIpClient.SocketConnector,AutoCloseable {
    final byte[] jpeg,info;
    final int width,height;
    final long vendor;
    final List<Integer> operations=new CopyOnWriteArrayList<>();
    final List<long[]> areas=new CopyOnWriteArrayList<>();
    final List<PeerSocket> sockets=new CopyOnWriteArrayList<>();
    volatile boolean live,viewFailure,cutCapture,busyCapture,rawFirst,rejectFocus;
    private volatile Preview preview;
    private static final class Preview {final byte[] jpeg;final int width,height;Preview(byte[] jpeg,int width,int height){this.jpeg=jpeg;this.width=width;this.height=height;}}
    void preview(byte[] jpeg,int width,int height){preview=jpeg==null?null:new Preview(jpeg,width,height);}
    final Map<Integer,Long> rawShots=new java.util.concurrent.ConcurrentHashMap<>();
    volatile int shots,shutters,focuses;
    FakeNikonPeer(byte[] jpeg,int width,int height)throws IOException{this(jpeg,width,height,10);}
    FakeNikonPeer(byte[] jpeg,int width,int height,long vendor)throws IOException{this.jpeg=jpeg;this.width=width;this.height=height;this.vendor=vendor;info=info();}
    @Override public Socket connect(String host,int port,int timeout){PeerSocket socket=new PeerSocket();sockets.add(socket);return socket;}
    @Override public void close(){for(PeerSocket socket:sockets)try{socket.close();}catch(Exception ignored){}}
    private void packet(PeerSocket socket,int type,byte[] data)throws IOException{
        if(type==1){ByteArrayOutputStream out=new ByteArrayOutputStream();u32(out,1);out.write(new byte[]{0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15});out.write("QA camera\0".getBytes(java.nio.charset.StandardCharsets.UTF_16LE));u32(out,0x10000);socket.offer(2,out.toByteArray());return;}
        if(type==3){socket.offer(4,new byte[0]);return;}
        if(type!=6)throw new IOException("unexpected packet "+type);
        int op=u16(data,4);long tx=u32(data,6);long[] p=new long[(data.length-10)/4];for(int i=0;i<p.length;i++)p[i]=u32(data,10+i*4);operations.add(op);
        byte[] result=null;int response=0x2001;
        switch(op){
            case 0x1001:result=info;break;
            case 0x1002:case 0x1003:break;
            case 0x1004:result=array32(0x10001);break;
            case 0x1007:List<Long> listed=new ArrayList<>();for(int i=0;i<=shots;i++)listed.add(10L+i);for(Map.Entry<Integer,Long> item:rawShots.entrySet())if(android.os.SystemClock.elapsedRealtime()>=item.getValue())listed.add(item.getKey()+1000L);long[] handles=new long[listed.size()];for(int i=0;i<handles.length;i++)handles[i]=listed.get(i);result=array32(handles);break;
            case 0x1008:result=object(p[0]).toBytes();break;
            case 0x1009:case 0x100a:result=jpeg;break;
            case 0x90ca:result=new byte[4];break;
            case 0x1014:result=descriptor((int)p[0]);break;
            case 0x1015:result=value((int)p[0]);break;
            case 0x9201:live=true;break;
            case 0x9202:live=false;break;
            case 0x9203:
                if(viewFailure||!live){response=0xa00b;break;}
                Preview shown=preview;byte[] frame=shown==null?jpeg:shown.jpeg;int w=shown==null?width:shown.width,h=shown==null?height:shown.height;
                result=new byte[384+frame.length];put16(result,0,w);put16(result,2,h);put16(result,4,w);put16(result,6,h);put16(result,16,48);put16(result,18,40);result[40]=2;System.arraycopy(frame,0,result,384,frame.length);break;
            case 0x90c1:if(rejectFocus)response=0x200f;else focuses++;break;
            case 0x9205:areas.add(p);break;
            case 0x9207:
                shutters++;if(busyCapture){response=0x2019;break;}shots++;if(rawFirst)rawShots.put(shots+10,android.os.SystemClock.elapsedRealtime()+2000);
                if(cutCapture){close();return;}break;
            default:response=0x2005;
        }
        if(result!=null){ByteArrayOutputStream start=new ByteArrayOutputStream();u32(start,tx);u32(start,result.length);u32(start,0);socket.offer(9,start.toByteArray());ByteArrayOutputStream end=new ByteArrayOutputStream();u32(end,tx);end.write(result);socket.offer(12,end.toByteArray());}
        ByteArrayOutputStream end=new ByteArrayOutputStream();u16(end,response);u32(end,tx);socket.offer(7,end.toByteArray());
    }
    PtpObjectInfo object(long handle){boolean raw=rawShots.containsKey((int)handle);long number=handle>=1000?handle-1000:handle;return new PtpObjectInfo.Builder().storageId(0x10001).objectFormat(raw?0xb103:0x3801).filename(String.format(Locale.ROOT,"QA_REMOTE_%04d.%s",number,raw?"NEF":"JPG")).compressedSize(jpeg.length).thumbFormat(0x3801).thumbCompressedSize(jpeg.length).imagePixWidth(width).imagePixHeight(height).captureDate("20261024T120000").build();}
    private int type(int code){return code==0x5001||code==0x5004||code==0xd061||code==0xd1a2||code==0xd054?2:code==0x500d||code==0xd1a4?6:code==0x5010?3:4;}
    private byte[] value(int code)throws IOException{long v=code==0x5001?68:code==0x5007?280:code==0x500d?40:code==0x500f?320:code==0x500e||code==0x5013?1:code==0x5004?(rawFirst?7:2):code==0xd1a2&&live?1:0;ByteArrayOutputStream b=new ByteArrayOutputStream();int size=1<<((type(code)-1)/2);for(int i=0;i<size;i++)b.write((int)(v>>(8*i)));return b.toByteArray();}
    private byte[] descriptor(int code)throws IOException{ByteArrayOutputStream b=new ByteArrayOutputStream();u16(b,code);u16(b,type(code));b.write(0);byte[] value=value(code);b.write(new byte[value.length]);b.write(value);b.write(0);return b.toByteArray();}
    private byte[] info()throws IOException{ByteArrayOutputStream b=new ByteArrayOutputStream();u16(b,100);u32(b,vendor);u16(b,100);str(b,"Nikon test peer");u16(b,0);array16(b,new int[]{0x1001,0x1002,0x1003,0x1004,0x1007,0x1008,0x1009,0x100a,0x1014,0x1015,0x90ca,0x9201,0x9202,0x9203,0x90c1,0x9205,0x9207});array16(b,new int[]{0x4002});array16(b,new int[]{0x5001,0x5007,0x500d,0x500f,0x5010,0x500e,0x500a,0x5004,0x5013,0xd061,0xd161,0xd1a2,0xd1a4,0xd054});array16(b,new int[]{0x3801});array16(b,new int[]{0x3801});str(b,"Nikon Corporation");str(b,"NIKON Z 6_2");str(b,"QA");str(b,"SYNTHETIC-REMOTE-QA");return b.toByteArray();}
    private static byte[] array32(long...values)throws IOException{ByteArrayOutputStream b=new ByteArrayOutputStream();u32(b,values.length);for(long v:values)u32(b,v);return b.toByteArray();}
    private static void array16(OutputStream b,int[] values)throws IOException{u32(b,values.length);for(int v:values)u16(b,v);}
    private static void str(OutputStream b,String text)throws IOException{b.write(text.length()+1);b.write((text+"\0").getBytes(java.nio.charset.StandardCharsets.UTF_16LE));}
    static int u16(byte[]b,int o){return(b[o]&255)|((b[o+1]&255)<<8);}
    static long u32(byte[]b,int o){return(b[o]&255L)|((b[o+1]&255L)<<8)|((b[o+2]&255L)<<16)|((b[o+3]&255L)<<24);}
    static void u16(OutputStream b,int v)throws IOException{b.write(v);b.write(v>>8);}
    static void u32(OutputStream b,long v)throws IOException{for(int i=0;i<4;i++)b.write((int)(v>>(8*i)));}
    static void put16(byte[]b,int o,int v){b[o]=(byte)v;b[o+1]=(byte)(v>>8);}
    final class PeerSocket extends Socket {
        final ArrayDeque<byte[]> chunks=new ArrayDeque<>();int offset,timeout;boolean closed;
        final InputStream input=new InputStream(){
            @Override public int read()throws IOException{byte[] b=new byte[1];int n=read(b,0,1);return n<0?-1:b[0]&255;}
            @Override public int read(byte[]b,int o,int n)throws IOException{synchronized(PeerSocket.this){while(chunks.isEmpty()&&!closed)try{PeerSocket.this.wait(timeout);}catch(InterruptedException error){Thread.currentThread().interrupt();throw new IOException(error);}if(chunks.isEmpty())return-1;byte[] top=chunks.peek();int take=Math.min(n,top.length-offset);System.arraycopy(top,offset,b,o,take);offset+=take;if(offset==top.length){chunks.remove();offset=0;}return take;}}
        };
        final OutputStream output=new OutputStream(){ByteArrayOutputStream pending=new ByteArrayOutputStream();
            @Override public void write(int v)throws IOException{write(new byte[]{(byte)v});}
            @Override public synchronized void write(byte[]b,int o,int n)throws IOException{if(closed)throw new IOException("closed test peer");pending.write(b,o,n);byte[] bytes=pending.toByteArray();while(bytes.length>=8){int length=(int)u32(bytes,0);if(bytes.length<length)break;packet(PeerSocket.this,(int)u32(bytes,4),Arrays.copyOfRange(bytes,8,length));bytes=Arrays.copyOfRange(bytes,length,bytes.length);}pending.reset();pending.write(bytes);}
        };
        synchronized void offer(int type,byte[] data)throws IOException{ByteArrayOutputStream b=new ByteArrayOutputStream();u32(b,data.length+8);u32(b,type);b.write(data);chunks.add(b.toByteArray());notifyAll();}
        @Override public InputStream getInputStream(){return input;}
        @Override public OutputStream getOutputStream(){return output;}
        @Override public void setTcpNoDelay(boolean ignored){}
        @Override public synchronized void setSoTimeout(int value){timeout=value;}
        @Override public synchronized boolean isClosed(){return closed;}
        @Override public synchronized void close(){closed=true;notifyAll();}
    }
}
