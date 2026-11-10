package cc.huevia.ncp;

import java.io.*;
import java.util.*;
import cc.huevia.rawdevelopmentqa.SyntheticDng;

public final class RawDevelopmentSettingsTest {
    static int checks;
    public static void main(String[] args)throws Exception{
        Set<String> identities=new HashSet<>();RawDevelopmentSettings d=RawDevelopmentSettings.DEFAULT;check(d.whiteBalance==RawDevelopmentSettings.WhiteBalance.CAMERA,"camera WB default");
        for(RawDevelopmentSettings.WhiteBalance wb:RawDevelopmentSettings.WhiteBalance.values())for(int ev:new int[]{-50,-10,0,10,50})for(int highlights:new int[]{0,2,3,9})for(int quality:new int[]{0,3}){
            RawDevelopmentSettings value=new RawDevelopmentSettings(wb,5500,7,ev,highlights,quality);ByteArrayOutputStream bytes=new ByteArrayOutputStream();value.write(new DataOutputStream(bytes));RawDevelopmentSettings read=RawDevelopmentSettings.read(new DataInputStream(new ByteArrayInputStream(bytes.toByteArray())));check(value.equals(read)&&value.hashCode()==read.hashCode(),"settings roundtrip");check(identities.add(value.identity()),"every native setting has distinct cache identity");
        }
        check(d.withTemperature(3000).whiteBalance==RawDevelopmentSettings.WhiteBalance.CUSTOM&&d.whiteBalance==RawDevelopmentSettings.WhiteBalance.CAMERA,"temperature creates immutable custom WB");check(d.withTint(-20).whiteBalance==RawDevelopmentSettings.WhiteBalance.CUSTOM,"tint selects custom WB");
        invalid(()->d.withTemperature(1999));invalid(()->d.withTemperature(12001));invalid(()->d.withTint(101));invalid(()->d.withExposure(-51));invalid(()->d.withExposure(51));invalid(()->d.withHighlights(10));invalid(()->d.withDemosaicQuality(2));
        ByteArrayOutputStream bytes=new ByteArrayOutputStream();d.write(new DataOutputStream(bytes));byte[] body=bytes.toByteArray();for(int size=0;size<body.length;size++){boolean failed=false;try{RawDevelopmentSettings.read(new DataInputStream(new ByteArrayInputStream(Arrays.copyOf(body,size))));}catch(IOException expected){failed=true;}check(failed,"truncated settings rejected");}
        check(d.colorMode==RawDevelopmentSettings.ColorMode.CAMERA_JPEG,"JPEG restoration default");
        RawDevelopmentSettings neutral=d.withColorMode(RawDevelopmentSettings.ColorMode.NEUTRAL);
        check(!d.equals(neutral)&&!d.identity().equals(neutral.identity()),"color modes isolate work caches");
        for(RawDevelopmentSettings value:new RawDevelopmentSettings[]{neutral.withExposure(10),neutral.withTemperature(3000),neutral.withTint(10),neutral.withWhiteBalance(RawDevelopmentSettings.WhiteBalance.AUTO),neutral.withHighlights(3),neutral.withDemosaicQuality(0)})check(value.colorMode==RawDevelopmentSettings.ColorMode.NEUTRAL,"editing preserves color mode");
        ByteArrayOutputStream legacyBytes=new ByteArrayOutputStream();DataOutputStream legacy=new DataOutputStream(legacyBytes);for(int value:new int[]{0x52445331,0,5500,0,0,2,3})legacy.writeInt(value);
        check(neutral.equals(RawDevelopmentSettings.read(new DataInputStream(new ByteArrayInputStream(legacyBytes.toByteArray())))),"old v1 settings retain previous neutral rendering");
        ByteArrayOutputStream neutralBytes=new ByteArrayOutputStream();neutral.write(new DataOutputStream(neutralBytes));check(neutral.equals(RawDevelopmentSettings.read(new DataInputStream(new ByteArrayInputStream(neutralBytes.toByteArray())))),"neutral v2 roundtrip");
        for(int ordinal:new int[]{-1,2,Integer.MAX_VALUE}){byte[] broken=body.clone();java.nio.ByteBuffer.wrap(broken).putInt(broken.length-4,ordinal);boolean rejected=false;try{RawDevelopmentSettings.read(new DataInputStream(new ByteArrayInputStream(broken)));}catch(IOException expected){rejected=true;}check(rejected,"invalid color ordinal rejected");}
        invalid(()->d.withColorMode(null));
        File f=new File(args[0],"bayer-test.dng");SyntheticDng.write(f,96,64,6);byte[] tiff=java.nio.file.Files.readAllBytes(f.toPath());check(tiff[0]=='I'&&tiff[1]=='I'&&tiff[2]==42,"fixture real TIFF header");check(tiff.length>96*64*2,"fixture contains full Bayer sample payload");String text=new String(tiff,java.nio.charset.StandardCharsets.ISO_8859_1);check(!text.contains("JFIF")&&!text.contains("Exif\0\0"),"fixture contains no embedded JPEG");System.out.println("PASS RAW development settings/fixture "+checks+" checks; fixture="+f.getAbsolutePath());
    }
    interface Task{void run();}static void invalid(Task task){boolean failed=false;try{task.run();}catch(IllegalArgumentException expected){failed=true;}check(failed,"invalid settings rejected");}static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
}
