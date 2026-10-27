package cc.huevia;

import android.app.Activity;
import android.content.res.Configuration;
import android.graphics.Color;
import android.os.Bundle;
import android.view.*;
import cc.huevia.connection.CameraConnectionRuntime;
import cc.huevia.remote.RemoteCaptureController;
import cc.huevia.ui.RemoteCaptureView;

/** Dedicated camera workspace; connection and unconfirmed capture are application-owned. */
public final class RemoteCaptureActivity extends Activity {
    private RemoteCaptureController controller;
    private RemoteCaptureView surface;
    private Bundle uiState;
    private final Runnable observer=()->{if(surface!=null)surface.update();};
    @Override public void onCreate(Bundle saved){setTheme(android.R.style.Theme_Material_NoActionBar);super.onCreate(saved);controller=RemoteCaptureController.get(this);uiState=saved;render();}
    private void render(){
        getWindow().setStatusBarColor(0xff121313);getWindow().setNavigationBarColor(0xff121313);
        getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LAYOUT_STABLE|View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN|View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION);
        if(android.os.Build.VERSION.SDK_INT>=30){WindowInsetsController c=getWindow().getInsetsController();if(c!=null){c.show(WindowInsets.Type.systemBars());c.setSystemBarsAppearance(0,WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS|WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS);}}
        surface=new RemoteCaptureView(this,controller,getResources().getConfiguration().orientation==Configuration.ORIENTATION_LANDSCAPE);setContentView(surface);
        surface.restoreUi(uiState);
        surface.setOnApplyWindowInsetsListener((v,insets)->{if(android.os.Build.VERSION.SDK_INT>=30){android.graphics.Insets i=insets.getInsets(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout());v.setPadding(i.left,i.top,i.right,i.bottom);}else v.setPadding(insets.getSystemWindowInsetLeft(),insets.getSystemWindowInsetTop(),insets.getSystemWindowInsetRight(),insets.getSystemWindowInsetBottom());return insets;});surface.requestApplyInsets();
    }
    @Override public void onConfigurationChanged(Configuration c){uiState=new Bundle();surface.saveUi(uiState);super.onConfigurationChanged(c);render();}
    @Override protected void onSaveInstanceState(Bundle out){surface.saveUi(out);super.onSaveInstanceState(out);}
    @Override protected void onStart(){super.onStart();controller.addObserver(observer);controller.setVisible(true);}
    @Override protected void onStop(){controller.removeObserver(observer);controller.setVisible(false);super.onStop();}
}
