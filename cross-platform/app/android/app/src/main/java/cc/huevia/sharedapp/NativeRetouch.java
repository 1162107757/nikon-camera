package cc.huevia.sharedapp;

import android.content.Context;
import android.graphics.*;
import android.media.ExifInterface;
import cc.huevia.album.*;
import cc.huevia.library.SharedJson;
import cc.huevia.ncp.*;
import cc.huevia.shared.*;
import java.io.*;
import java.util.*;
import java.util.function.*;

/** CPU-only original model inference. Analysis images never leave the device. */
final class NativeRetouch {
    static String request(Context context,SharedRuntime runtime,String operation,Map<String,Object> p,File source,BooleanSupplier cancel,DoubleConsumer progress)throws IOException {
        String owner=SharedRuntime.text(p,"owner",64);runtime.guardOwner(owner);String identity=runtime.sourceIdentity(source.getPath(),true),json=SharedJson.encode(p),result;List<Object> people=null;
        if(operation.equals("media.retouchDescribe")||operation.equals("media.retouchChange")){
            if(operation.equals("media.retouchChange")&&"manualFace".equals(p.get("action"))){Bitmap image=decode(source,1280,cancel);try{Map<String,Object> value=SharedRuntime.object(p.get("value"));double cx=((Number)value.get("cx")).doubleValue(),cy=((Number)value.get("cy")).doubleValue();double rx=value.get("rx") instanceof Number?((Number)value.get("rx")).doubleValue():.12,ry=value.get("ry") instanceof Number?((Number)value.get("ry")).doubleValue():.18;PhotoPortrait.Face face=PhotoPortraitDetection.manualFace(image,cx,cy,rx,ry);value.put("skinR",face.skinR);value.put("skinG",face.skinG);value.put("skinB",face.skinB);json=SharedJson.encode(p);}finally{image.recycle();}}
            result=SharedRetouch.request(operation,json,cancel);
        }
        else {
            Bitmap image=decode(source,operation.equals("media.retouchPatch")?384:1280,cancel);
            try {
                if(operation.equals("media.retouchPatch")){int[] pixels=new int[image.getWidth()*image.getHeight()];image.getPixels(pixels,0,image.getWidth(),0,0,image.getWidth(),image.getHeight());result=SharedRetouch.patch(json,pixels,image.getWidth(),image.getHeight(),cancel);}
                else if(operation.equals("media.retouchHeal")){int[] pixels=new int[image.getWidth()*image.getHeight()];image.getPixels(pixels,0,image.getWidth(),0,0,image.getWidth(),image.getHeight());result=SharedPortraitInference.heal(json,pixels,image.getWidth(),image.getHeight(),cancel);}
                else if(operation.equals("media.retouchAnalyze")&&"autoBlemish".equals(p.get("mode"))){int[] pixels=new int[image.getWidth()*image.getHeight()];image.getPixels(pixels,0,image.getWidth(),0,0,image.getWidth(),image.getHeight());result=SharedAutoBlemishes.analyze(json,pixels,image.getWidth(),image.getHeight(),cancel);}
                else if(operation.equals("media.retouchAnalyze")&&("overlay".equals(p.get("mode"))||"hitFace".equals(p.get("mode")))){int[] pixels=new int[image.getWidth()*image.getHeight()];image.getPixels(pixels,0,image.getWidth(),0,0,image.getWidth(),image.getHeight());result=SharedPortraitOverlay.render(json,pixels,image.getWidth(),image.getHeight(),cancel);}
                else if(operation.equals("media.retouchAnalyze")) {
                    String mode=SharedRuntime.text(p,"mode",16);PhotoLocalEdits local=SharedRetouch.local(p);PhotoPortrait portrait=SharedRetouch.portrait(local,p);
                    if(mode.equals("face")) {
                        List<PhotoPortrait.Face> found=PhotoPortraitDetection.detect(image,cancel);
                        if(!found.isEmpty())found=PhotoFaceSkinMask.refine(context,image,PhotoFaceLandmarks.refine(context,image,found,cancel),cancel);
                        List<PhotoPortrait.Face> retained=new ArrayList<>();for(PhotoPortrait.Face candidate:found){for(PhotoPortrait.Face old:portrait.faces())if(Math.hypot(old.cx-candidate.cx,old.cy-candidate.cy)<Math.max(old.rx,candidate.rx)*.7){candidate=candidate.withSettings(old.settings).withRetouch(old.retouch).withTone(old.tone).withStrokes(old.strokes).withEnabled(old.enabled).withBodySkinMask(old.bodySkinMask);break;}retained.add(candidate);}found=retained;
                        portrait=portrait.withFaces(found);
                    }else if(mode.equals("faceBody")) {
                        if(portrait.faces().isEmpty())throw new IOException("请先选择一张人脸。");
                        portrait=portrait.withFaces(PhotoFaceBodySkin.refine(context,image,portrait.faces(),cancel));
                    }else if(mode.equals("skin")) {
                        PhotoPersonAnalysis.Result found=PhotoPersonAnalysis.analyze(context,image,cancel);
                        portrait=portrait.withGlobalSkinMask(found.skin);if(portrait.faces().isEmpty())portrait=portrait.withFaces(found.faces);
                    }else if(mode.equals("body")) {
                        PhotoBodyAnalysis.Result found=PhotoBodyAnalysis.analyze(context,image,cancel);
                        people=new ArrayList<>();for(PhotoBodyAnalysis.Person person:found.people)people.add(SharedRuntime.map("left",person.left,"top",person.top,"right",person.right,"bottom",person.bottom,"legsVisible",person.legsVisible));
                        if(found.people.isEmpty())throw new IOException("未识别到完整人物，请手动调整塑形范围。");
                        int selected=SharedRuntime.integer(p,"person",0);if(selected<0||selected>=found.people.size())throw new IOException("人物选择无效。");
                        portrait=portrait.withBodyShape(PhotoBodyAnalysis.locate(portrait.bodyShape,found.people.get(selected)).withBackgroundProtection(found.protection,70));
                    }else throw new IOException("请选择人脸、皮肤或身体分析。");
                    result=SharedRetouch.resultFor(SharedRetouch.withPortrait(local,p,portrait),p,cancel);
                }else throw new IOException("未知的人像分析请求。");
            }finally{image.recycle();}
        }
        if(people!=null){Map<String,Object> value=SharedJson.object(result);value.put("people",people);value.put("selectedPerson",SharedRuntime.integer(p,"person",0));result=SharedJson.encode(value);}
        if(cancel.getAsBoolean())throw new InterruptedIOException("编辑计算已停止。");runtime.guardOwner(owner);runtime.validateSource(source.getPath(),identity);progress.accept(1);return result;
    }
    private static Bitmap decode(File source,int edge,BooleanSupplier cancel)throws IOException {
        BitmapFactory.Options o=new BitmapFactory.Options();o.inJustDecodeBounds=true;BitmapFactory.decodeFile(source.getPath(),o);
        if(o.outWidth<2||o.outHeight<2||(long)o.outWidth*o.outHeight>60000000)throw new IOException("照片尺寸无效或超过处理上限。");
        o.inSampleSize=1;while(Math.max(o.outWidth,o.outHeight)/o.inSampleSize>edge*2)o.inSampleSize*=2;o.inJustDecodeBounds=false;o.inPreferredConfig=Bitmap.Config.ARGB_8888;
        Bitmap raw=BitmapFactory.decodeFile(source.getPath(),o);if(raw==null)throw new IOException("无法读取照片，请先显影 RAW。");Bitmap oriented=null,returned=null;
        try {
            int orientation=new ExifInterface(source.getPath()).getAttributeInt(ExifInterface.TAG_ORIENTATION,1);Matrix m=new Matrix();
            switch(orientation){case 2:m.setScale(-1,1);break;case 3:m.setRotate(180);break;case 4:m.setScale(1,-1);break;case 5:m.setRotate(90);m.postScale(-1,1);break;case 6:m.setRotate(90);break;case 7:m.setRotate(-90);m.postScale(-1,1);break;case 8:m.setRotate(-90);break;}
            oriented=Bitmap.createBitmap(raw,0,0,raw.getWidth(),raw.getHeight(),m,true);double scale=Math.min(1,edge/(double)Math.max(oriented.getWidth(),oriented.getHeight()));
            Bitmap bounded=Bitmap.createScaledBitmap(oriented,Math.max(2,(int)Math.round(oriented.getWidth()*scale)),Math.max(2,(int)Math.round(oriented.getHeight()*scale)),true);
            if(bounded!=oriented)oriented.recycle();oriented=null;if(cancel.getAsBoolean()){bounded.recycle();throw new InterruptedIOException("编辑计算已停止。");}returned=bounded;return bounded;
        }finally{if(oriented!=null&&oriented!=raw&&!oriented.isRecycled())oriented.recycle();if(raw!=returned&&!raw.isRecycled())raw.recycle();}
    }
}
