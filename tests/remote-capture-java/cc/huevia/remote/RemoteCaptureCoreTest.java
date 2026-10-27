package cc.huevia.remote;

import cc.huevia.ptp.*;
import java.io.*;
import java.util.*;

/** Synthetic datasets only; no camera or shutter is accessed by this host suite. */
public final class RemoteCaptureCoreTest {
    private static int checks;
    public static void main(String[] args)throws Exception{
        propertyUnitsAndSignedness();liveFrameBoundsAndFocusCoordinates();capabilitiesDoNotGuess();captureIsSingleExplicitCommand();
        System.out.println("PASS "+checks+" remote capture core checks");
    }
    private static void check(boolean value,String detail){checks++;if(!value)throw new AssertionError(detail);}
    private interface Throwing{void run()throws Exception;}
    private static void rejects(Throwing action,String detail)throws Exception{try{action.run();throw new AssertionError(detail);}catch(IOException expected){checks++;}}
    private static void propertyUnitsAndSignedness()throws Exception{
        check(RemoteProperty.descriptor(0x5010,desc(0x5010,3,-1000)).value==-1000,"signed EV");
        check(RemoteProperty.compensation(-1000).equals("-1.0"),"EV unit");
        check(RemoteProperty.aperture(280).equals("F2.8"),"aperture unit");
        check(RemoteProperty.shutter(40).equals("1/250"),"1/10000 s shutter unit");
        check(RemoteProperty.shutter(15000).equals("1.5s"),"long exposure");
        check(RemoteProperty.shutter(0xffffffffL).equals("Bulb"),"bulb never a huge number");
        check(RemoteProperty.descriptor(0x500d,desc(0x500d,6,0xffffffffL)).value==0xffffffffL,"unsigned scalar");
        rejects(()->RemoteProperty.descriptor(0x5007,desc(0x500d,6,40)),"wrong property descriptor");
        rejects(()->RemoteProperty.descriptor(0x500d,new byte[7]),"truncated descriptor");
        rejects(()->RemoteProperty.descriptor(0x500d,desc(0x500d,10,40)),"array descriptor rejected");
        rejects(()->RemoteProperty.descriptor(0x500d,desc(0x500d,6,40)).update(new byte[2]),"truncated current value");
    }
    private static void liveFrameBoundsAndFocusCoordinates()throws Exception{
        byte[] jpeg={(byte)255,(byte)216,(byte)255,(byte)192,0,11,8,0,3,0,4,1,1,17,0,(byte)255,(byte)218,0,8,1,1,0,0,63,0,42,(byte)255,0,42,(byte)255,(byte)217};
        byte[] wire=new byte[384+jpeg.length];u16(wire,0,4);u16(wire,2,3);u16(wire,4,400);u16(wire,6,300);wire[40]=2;System.arraycopy(jpeg,0,wire,384,jpeg.length);
        RemoteLiveFrame frame=RemoteLiveFrame.parse(wire);check(frame.width==4&&frame.height==3,"JPEG dimensions");check(Arrays.equals(jpeg,frame.jpeg),"header stripped without changing JPEG");
        check(Arrays.equals(frame.focusPoint(1,1),new int[]{399,299}),"AF uses reported coordinate plane");check(frame.focused,"known focus metadata");
        rejects(()->frame.focusPoint(-.1,.5),"black margin not mapped");rejects(()->frame.focusPoint(Double.NaN,.5),"invalid AF location");
        wire[29]=2;RemoteLiveFrame rotated=RemoteLiveFrame.parse(wire);check(rotated.rotation==90&&Arrays.equals(rotated.focusPoint(0,0),new int[]{0,299}),"clockwise frame maps AF back to sensor");wire[29]=1;rotated=RemoteLiveFrame.parse(wire);check(rotated.rotation==-90&&Arrays.equals(rotated.focusPoint(0,0),new int[]{399,0}),"counterclockwise frame maps AF back to sensor");wire[29]=0;
        RemoteLiveFrame bare=RemoteLiveFrame.parse(jpeg);check(bare.afWidth==0&&!bare.focusKnown,"no metadata means no invented tap AF");rejects(()->bare.focusPoint(.5,.5),"unknown AF geometry");
        byte[] cut=Arrays.copyOf(wire,wire.length-1);rejects(()->RemoteLiveFrame.parse(cut),"incomplete JPEG");
        wire[0]=5;check(RemoteLiveFrame.parse(wire).afWidth==0,"mismatched metadata disables point AF");
    }
    private static void capabilitiesDoNotGuess()throws Exception{
        Peer peer=new Peer();NikonRemoteCamera camera=new NikonRemoteCamera(peer,info(10,"Nikon Corporation",new int[]{0x1014,0x1015}),"same");
        check(!camera.capture&&!camera.liveView&&!camera.autoFocus,"Wi-Fi does not imply shooting");
        rejects(camera::release,"unadvertised shutter rejected");rejects(camera::startView,"unadvertised view rejected");
        rejects(()->new NikonRemoteCamera(peer,info(1,"Nikon Corporation",new int[0]),"same"),"vendor mismatch");
        rejects(()->new NikonRemoteCamera(peer,info(10,"Fujifilm",new int[0]),"same"),"manufacturer mismatch");
        check(peer.commands.isEmpty(),"capability discovery never sends shutter");
        for(int vendor:new int[]{10,6,-1}){
            NikonRemoteCamera compatible=new NikonRemoteCamera(peer,info(vendor,"NIKON CORPORATION",new int[]{0x9201,0x9202,0x9203}),"same");
            check(compatible.liveView&&!compatible.capture,"Nikon identity supports native/Microsoft/MTP vendor "+Integer.toUnsignedString(vendor));
            rejects(compatible::release,"MTP identity never invents an unadvertised shutter");
        }
        rejects(()->new NikonRemoteCamera(peer,info(-1,"Sony Corporation",new int[]{0x9207}),"same"),"generic MTP is not Nikon without Nikon manufacturer");
        rejects(()->new NikonRemoteCamera(peer,info(10,"NotNikon Inc",new int[]{0x9207}),"same"),"manufacturer substring is not Nikon identity");
    }
    private static void captureIsSingleExplicitCommand()throws Exception{
        Peer peer=new Peer();NikonRemoteCamera camera=new NikonRemoteCamera(peer,info(10,"Nikon Corporation",new int[]{0x9207,0x1004,0x1007,0x1008}),"same");
        check(camera.capture,"complete capture/check capability");Set<Long> before=camera.inventory();check(before.equals(Set.of(1L)),"baseline includes old photo");check(camera.newPhotos(before).isEmpty(),"old image cannot confirm a new shot");
        camera.release();check(peer.commands.size()==1&&peer.commands.get(0).equals("37383:[4294967295, 0]"),"one media/card shutter with no AF or SDRAM fallback");
        peer.added=true;List<NikonRemoteCamera.CapturedPhoto> photos=camera.newPhotos(before);check(photos.size()==1&&photos.get(0).handle==2,"new card descriptor confirms object");check(NikonRemoteCamera.oneExposure(photos),"single exposure group");
        photos.add(new NikonRemoteCamera.CapturedPhoto(3,object("DSC_0003.JPG")));check(!NikonRemoteCamera.oneExposure(photos),"multiple shots require manual check");
    }
    private static final class Peer implements RemoteTransport {
        boolean added;List<String> commands=new ArrayList<>();
        public boolean isOpen(){return true;}
        public void command(int op,long...p){commands.add(op+":"+Arrays.toString(p));}
        public byte[] data(int op,int maximum,long...p)throws IOException{
            ByteArrayOutputStream b=new ByteArrayOutputStream();if(op==0x1004){u32(b,1);u32(b,0x10001);return b.toByteArray();}
            if(op==0x1007){u32(b,added?2:1);u32(b,1);if(added)u32(b,2);return b.toByteArray();}
            if(op==0x1008)return object("DSC_0002.JPG").toBytes();throw new IOException("unexpected "+op);
        }
    }
    private static PtpObjectInfo object(String name){return new PtpObjectInfo.Builder().storageId(0x10001).objectFormat(0x3801).filename(name).compressedSize(4096).build();}
    private static byte[] desc(int prop,int type,long value)throws IOException{ByteArrayOutputStream b=new ByteArrayOutputStream();u16(b,prop);u16(b,type);b.write(0);int size=type>=1&&type<=8?1<<((type-1)/2):2;for(int i=0;i<size;i++)b.write(0);for(int i=0;i<size;i++)b.write((int)(value>>(i*8)));b.write(0);return b.toByteArray();}
    private static PtpDeviceInfo info(int vendor,String maker,int[] operations)throws Exception{ByteArrayOutputStream b=new ByteArrayOutputStream();u16(b,100);u32(b,vendor);u16(b,100);str(b,"");u16(b,0);array(b,operations);array(b,new int[0]);array(b,new int[]{0x5007,0x500d,0x5010});array(b,new int[0]);array(b,new int[]{0x3801});str(b,maker);str(b,"NIKON Z 6_2");str(b,"1.0");str(b,"synthetic");return PtpDeviceInfo.parse(b.toByteArray());}
    private static void array(OutputStream b,int[] a)throws IOException{u32(b,a.length);for(int v:a)u16(b,v);}
    private static void str(OutputStream b,String value)throws IOException{b.write(value.length()+1);for(char c:value.toCharArray())u16(b,c);u16(b,0);}
    private static void u16(byte[] b,int o,int n){b[o]=(byte)n;b[o+1]=(byte)(n>>8);}
    private static void u16(OutputStream b,int n)throws IOException{b.write(n);b.write(n>>8);}
    private static void u32(OutputStream b,long n)throws IOException{for(int i=0;i<4;i++)b.write((int)(n>>(i*8)));}
}
