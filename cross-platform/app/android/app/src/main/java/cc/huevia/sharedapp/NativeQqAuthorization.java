package cc.huevia.sharedapp;

import android.app.Activity;
import android.content.Intent;
import cc.huevia.account.QqLoginController;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;
import java.util.Collections;

/** Activity-scoped bridge. SDK initialization remains behind the explicit consent argument. */
public final class NativeQqAuthorization implements AutoCloseable {
    private final QqLoginController controller;
    private MethodChannel.Result pending;
    public NativeQqAuthorization(Activity host, BinaryMessenger messenger) {
        controller = new QqLoginController(host, new QqLoginController.Callback() {
            public void onAuthorized(String token) {
                MethodChannel.Result reply=take();
                if(reply!=null)reply.success(Collections.singletonMap("accessToken",token));
            }
            public void onCancelled() { finishCancelled(); }
            public void onError(String message) {
                MethodChannel.Result reply=take();
                if(reply!=null)reply.error("QQ_AUTH_FAILED",message,null);
            }
        });
        new MethodChannel(messenger,"cc.huevia/qq").setMethodCallHandler((call,reply)->{
            if(call.method.equals("cancel")){controller.cancel();finishCancelled();reply.success(null);return;}
            if(!call.method.equals("authorize")){reply.notImplemented();return;}
            if(!Boolean.TRUE.equals(call.argument("consent"))){reply.error("QQ_CONSENT_REQUIRED","请先阅读并同意 QQ 登录说明。",null);return;}
            if(pending!=null||controller.isInProgress()){reply.error("QQ_BUSY","请先完成当前 QQ 授权。",null);return;}
            pending=reply;controller.start();
        });
    }
    private MethodChannel.Result take(){MethodChannel.Result value=pending;pending=null;return value;}
    private void finishCancelled(){MethodChannel.Result reply=take();if(reply!=null)reply.success(Collections.singletonMap("cancelled",true));}
    public boolean onActivityResult(int request,int result,Intent data){return controller.onActivityResult(request,result,data);}
    public void onHostPaused(){controller.onHostPaused();}
    public void onHostResumed(){controller.onHostResumed();}
    @Override public void close(){controller.close();finishCancelled();}
}
