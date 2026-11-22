package cc.huevia.sharedapp;

import java.nio.charset.StandardCharsets;

public final class MotionPhotoMetadataTest {
    public static void main(String[] args){
        String namespace="xmlns:GCamera=\"http://ns.google.com/photos/1.0/camera/\" ";
        require(namespace+"GCamera:MotionPhoto=\"1\"",true);
        require(namespace+"GCamera:MicroVideo='1'",true);
        require(namespace+"<GCamera:MotionPhoto>1</GCamera:MotionPhoto>",true);
        require(namespace+"GCamera:MotionPhoto=\"0\"",false);
        require(namespace+"GCamera:MotionPhotoVersion=\"1\"",false);
        require("static image called MotionPhoto.jpg",false);
        require("GCamera:MotionPhoto=\"1\"",false);
        if(MotionPhotoMetadata.isMotion(null)||MotionPhotoMetadata.isMotion(new byte[600000]))throw new AssertionError("bounded metadata");
        System.out.println("Motion Photo metadata: 9 checks passed.");
    }
    private static void require(String value,boolean expected){if(MotionPhotoMetadata.isMotion(value.getBytes(StandardCharsets.UTF_8))!=expected)throw new AssertionError(value);}
}
