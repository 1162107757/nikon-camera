package cc.huevia.ncp;

import java.io.*;
import java.util.*;

/** Structural, ownership and active-control coverage; photographic calibration is separate. */
public final class NcpMonochromePreviewProfileTest {
    private static int checks;
    public static void main(String[] args)throws Exception{
        routingAndIdentity();curveAndOwnership();activeControls();strictRejection();
        System.out.println("PASS: "+checks+" NCP monochrome host checks");
    }
    private static void routingAndIdentity()throws Exception{
        byte[] mono=fixture(0x80,0x80,0xff);byte[] before=mono.clone();PresetPreviewProfile selected=PresetPreviewProfiles.fromPreset(mono);
        check(selected instanceof NcpMonochromePreviewProfile,"monochrome content selects dedicated reader");check(selected.modelVersion().equals(NcpMonochromePreviewProfile.MODEL_VERSION),"dedicated effect identity distinct from existing colour and NP3 identities");
        check(PresetPreviewProfiles.fromPreset(NcpCompatibilityFixtures.ncp()) instanceof NcpPreviewProfile,"colour branch retained");check(NcpPreviewProfile.MODEL_VERSION.equals("encoded-rgb-tone-hsv-v1"),"old colour identity retained");
        check(Np3PreviewProfile.MODEL_VERSION.equals("np3-0310-encoded-hsl-zones-spatial-v4")&&Np3MonochromePreviewProfile.STANDARD_MODEL_VERSION.equals("np3-0310-monochrome-spatial-v1")&&Np3MonochromePreviewProfile.MODEL_VERSION.equals("np3-0310-deep-tone-monochrome-spatial-v1"),"Flexible Color identity advances; monochrome identities retained");
        check(PresetPreviewProfiles.MODEL_VERSION.contains(NcpMonochromePreviewProfile.MODEL_VERSION),"aggregate preview key invalidates old unsupported caches");
        check(Arrays.equals(before,mono),"parsing never rewrites original preset");
        expectIo(()->NcpPictureControlConverter.convert(mono,0,0),"phone monochrome support does not loosen camera converter");
        for(int flag:new int[]{0,1,2,255}){byte[] changed=mono.clone();changed[38]=(byte)flag;check(Arrays.equals(selected.render(colors(),16,16),PresetPreviewProfiles.fromPreset(changed).render(colors(),16,16)),"modification metadata does not alter existing stored effect");}
        NcpMonochromePreviewProfile parsed=NcpMonochromePreviewProfile.fromNcp(mono);check(parsed.registrationName().equals("HOST NCP")&&parsed.sharpening()==2&&parsed.filterEffect()==0x80&&parsed.toning()==0x80&&parsed.toningDensity()==255,"audited parameter metadata exposed without invention");
    }
    private static void curveAndOwnership()throws Exception{
        byte[] data=fixture(0x80,0x80,255);sample(data,0,1024);sample(data,1,3072);sample(data,128,8192);sample(data,129,24576);sample(data,256,30000);NcpMonochromePreviewProfile profile=NcpMonochromePreviewProfile.fromNcp(data);
        near(profile.mapTone(0),1024/32767.0,"stored black endpoint");near(profile.mapTone(1),30000/32767.0,"stored white endpoint");near(profile.mapTone(1/512.0),2048/32767.0,"fractional raw curve samples");near(profile.mapTone(128.25/256),12288/32767.0,"interpolation uses raw nonmonotone curve");
        byte[] gamma=data.clone();gamma[62]=2;gamma[63]=50;NcpMonochromePreviewProfile other=NcpMonochromePreviewProfile.fromNcp(gamma);check(Arrays.equals(profile.render(colors(),16,16),other.render(colors(),16,16)),"editor Gamma metadata not applied twice");
        int[] input=colors(),copy=input.clone(),result=profile.render(input,16,16);check(Arrays.equals(input,copy)&&result!=input,"render owns output and retains input");int[] stable=result.clone();Arrays.fill(data,(byte)0);check(Arrays.equals(stable,profile.render(input,16,16)),"caller file edits cannot mutate parsed profile");result[0]^=0xffffff;check(Arrays.equals(stable,profile.render(input,16,16)),"caller output edits cannot mutate profile");
        for(int i=0;i<result.length;i++)check((copy[i]>>>24)==(stable[i]>>>24),"every source alpha retained");
        for(double value:new double[]{-.1,1.1,Double.NaN,Double.POSITIVE_INFINITY})expectInvalid(()->profile.mapTone(value),"invalid tone position rejected");
    }
    private static void activeControls()throws Exception{
        for(int filter=0x80;filter<=0x84;filter++){
            NcpMonochromePreviewProfile bw=NcpMonochromePreviewProfile.fromNcp(fixture(filter,0x80,255));
            for(int pixel:colors()){int value=bw.applyArgb(pixel),r=(value>>>16)&255,g=(value>>>8)&255,b=value&255;check(r==g&&g==b,"B&W filter output is achromatic");check((value>>>24)==(pixel>>>24),"filter preserves alpha");}
            for(int level:new int[]{0,32,64,128,192,255}){int pixel=0xff000000|(level<<16)|(level<<8)|level;int reference=NcpMonochromePreviewProfile.fromNcp(fixture(0x80,0x80,255)).applyArgb(pixel);check(bw.applyArgb(pixel)==reference,"nonnegative normalized colour filters keep gray ramp equal");}
        }
        int offRed=NcpMonochromePreviewProfile.fromNcp(fixture(0x80,0x80,255)).applyArgb(0xffff0000)&255;
        int yellowRed=NcpMonochromePreviewProfile.fromNcp(fixture(0x81,0x80,255)).applyArgb(0xffff0000)&255,orangeRed=NcpMonochromePreviewProfile.fromNcp(fixture(0x82,0x80,255)).applyArgb(0xffff0000)&255,redRed=NcpMonochromePreviewProfile.fromNcp(fixture(0x83,0x80,255)).applyArgb(0xffff0000)&255,greenRed=NcpMonochromePreviewProfile.fromNcp(fixture(0x84,0x80,255)).applyArgb(0xffff0000)&255;
        check(redRed>orangeRed&&orangeRed>yellowRed&&yellowRed>offRed&&offRed>greenRed,"yellow-orange-red transmission strength and green exclusion have distinct paths");
        for(int tone:new int[]{0x81,0x84}){int previous=-1;Set<Integer> outputs=new HashSet<>();for(int density=1;density<=7;density++){NcpMonochromePreviewProfile toned=NcpMonochromePreviewProfile.fromNcp(fixture(0x80,tone,128+density));int output=toned.applyArgb(0xff808080),r=(output>>>16)&255,g=(output>>>8)&255,b=output&255;check(r>=g&&g>b,"sepia/yellow toning has active chroma rather than grayscale fallback");int chroma=r-b;check(chroma>=previous,"tone density has monotonic chroma");previous=chroma;outputs.add(output);check(toned.applyArgb(0xff000000)!=0xff000000&&toned.applyArgb(0xffffffff)!=0xffffffff,"observed toning also colours dark and light endpoints");}check(outputs.size()==7,"every density step has distinct visible output");}
        int bw=NcpMonochromePreviewProfile.fromNcp(fixture(0x80,0x80,255)).applyArgb(0xff808080),sepia=NcpMonochromePreviewProfile.fromNcp(fixture(0x80,0x81,0x84)).applyArgb(0xff808080),yellow=NcpMonochromePreviewProfile.fromNcp(fixture(0x80,0x84,0x84)).applyArgb(0xff808080);check(bw!=sepia&&sepia!=yellow&&bw!=yellow,"B&W, sepia and yellow differ");
    }
    private static void strictRejection()throws Exception{
        for(int length:new int[]{0,8,637,639,1024*1024+1}){byte[] data=Arrays.copyOf(fixture(0x80,0x80,255),length);expectIo(()->PresetPreviewProfiles.fromPreset(data),"malformed envelope cannot fall through");}
        for(int[] mutation:new int[][]{{0,'X'},{12,'9'},{11,35},{51,3},{637,1},{36,0x7f},{39,0},{40,255},{41,0},{42,0},{43,128},{44,128},{45,127},{45,133},{46,130},{46,133},{47,129},{56,0},{62,21},{63,101},{64,1},{64,21},{105,1},{120,128}}){byte[] data=fixture(0x80,0x80,255);data[mutation[0]]=(byte)mutation[1];expectIo(()->NcpMonochromePreviewProfile.fromNcp(data),"unknown or malformed control rejected at "+mutation[0]);}
        for(int density:new int[]{0,128,136,255})expectIo(()->NcpMonochromePreviewProfile.fromNcp(fixture(0x80,0x81,density)),"toned density sentinels rejected");
        byte[] unknown=fixture(0x80,0x80,255);unknown[46]=(byte)0x85;expectIo(()->PresetPreviewProfiles.fromPreset(unknown),"known monochrome base with unsupported active tone does not fall back to colour");
        byte[] badName=fixture(0x80,0x80,255);Arrays.fill(badName,16,36,(byte)'A');expectIo(()->NcpMonochromePreviewProfile.fromNcp(badName),"unterminated name rejected");
        byte[] hidden=fixture(0x80,0x80,255);hidden[35]=1;expectIo(()->NcpMonochromePreviewProfile.fromNcp(hidden),"unknown name padding rejected");
    }
    public static byte[] fixture(int filter,int tone,int density){byte[] bytes=NcpCompatibilityFixtures.ncp();bytes[36]=6;bytes[37]=0x4d;bytes[43]=bytes[44]=(byte)255;bytes[45]=(byte)filter;bytes[46]=(byte)tone;bytes[47]=(byte)density;for(int i=0;i<=256;i++)sample(bytes,i,(int)Math.round(i*32767/256.0));return bytes;}
    private static void sample(byte[] bytes,int index,int value){bytes[120+index*2]=(byte)(value>>>8);bytes[121+index*2]=(byte)value;}
    private static int[] colors(){int[] values=new int[256];for(int i=0;i<values.length;i++)values[i]=(i<<24)|(((i*29)&255)<<16)|(((i*53)&255)<<8)|((i*97)&255);return values;}
    private static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}private static void near(double actual,double expected,String message){check(Math.abs(actual-expected)<1e-12,message);}
    private interface Action{void run()throws Exception;}
    private static void expectIo(Action action,String message)throws Exception{checks++;try{action.run();throw new AssertionError(message);}catch(IOException expected){}}
    private static void expectInvalid(Action action,String message)throws Exception{checks++;try{action.run();throw new AssertionError(message);}catch(IllegalArgumentException expected){}}
}
