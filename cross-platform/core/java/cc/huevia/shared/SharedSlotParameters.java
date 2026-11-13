package cc.huevia.shared;

import cc.huevia.usb.CameraParameterController;
import cc.huevia.usb.CameraParameterRequest;
import java.io.IOException;
import java.util.*;

/** Only the original explicit WB/Kelvin/EV choices; null means leave the camera unchanged. */
final class SharedSlotParameters {
    private SharedSlotParameters(){}
    static CameraParameterRequest parse(Object value)throws IOException {
        if(value==null)return CameraParameterRequest.NONE;
        if(!(value instanceof Map))throw new IOException("拍摄参数格式无效。");
        Map<?,?> values=(Map<?,?>)value;
        for(Object key:values.keySet())if(!Arrays.asList("whiteBalance","kelvin","exposureMilliEv").contains(key))throw new IOException("拍摄参数超出允许范围。");
        try{return new CameraParameterRequest(integer(values,"whiteBalance"),integer(values,"kelvin"),integer(values,"exposureMilliEv"));}
        catch(IllegalArgumentException invalid){throw new IOException("拍摄参数不在原版允许范围内。",invalid);}
    }
    private static Long integer(Map<?,?> values,String key)throws IOException {
        Object value=values.get(key);if(value==null)return null;
        if(!(value instanceof Byte||value instanceof Short||value instanceof Integer||value instanceof Long))throw new IOException("拍摄参数必须为整数。");
        return ((Number)value).longValue();
    }
    static Map<String,Object> values(CameraParameterRequest request){return SharedRuntime.map("whiteBalance",request.whiteBalance,"kelvin",request.kelvin,"exposureMilliEv",request.exposureMilliEv);}
    static Map<String,Object> result(CameraParameterController.Result result){
        List<Object> changes=new ArrayList<>();for(CameraParameterController.Change change:result.changes())changes.add(SharedRuntime.map("code",change.code,"desired",change.desired,"before",change.before,"observed",change.observed,"status",change.status,"reason",change.reason));
        return SharedRuntime.map("uncertain",result.uncertain,"detail",result.text(),"changes",changes);
    }
}
