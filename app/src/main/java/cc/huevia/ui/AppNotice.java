package cc.huevia.ui;

import android.app.Activity;
import android.graphics.drawable.GradientDrawable;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.widget.FrameLayout;
import android.widget.TextView;

/** Short foreground feedback, styled as part of the app rather than an OS toast. */
public final class AppNotice {
    private AppNotice(){}
    public static void show(Activity activity,CharSequence message,boolean longer){
        activity.runOnUiThread(()->{
            if(activity.isFinishing()||activity.isDestroyed())return;
            View decor=activity.getWindow().getDecorView();if(!(decor instanceof FrameLayout))return;
            FrameLayout root=(FrameLayout)decor;View old=root.findViewWithTag("huevia-notice");
            if(old!=null&&old.getParent() instanceof ViewGroup)((ViewGroup)old.getParent()).removeView(old);
            float density=activity.getResources().getDisplayMetrics().density;UiPalette p=new UiPalette(activity);
            TextView notice=new TextView(activity);notice.setTag("huevia-notice");notice.setText(message);notice.setTextSize(13);notice.setTextColor(p.text);
            notice.setPadding(Math.round(16*density),Math.round(12*density),Math.round(16*density),Math.round(12*density));
            notice.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);notice.setMaxLines(4);
            GradientDrawable background=new GradientDrawable();background.setColor(p.card);background.setCornerRadius(16*density);background.setStroke(Math.round(density),p.outline);notice.setBackground(background);
            int safeTop=0;WindowInsets insets=decor.getRootWindowInsets();
            if(insets!=null){if(android.os.Build.VERSION.SDK_INT>=30)safeTop=insets.getInsets(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout()).top;else safeTop=insets.getSystemWindowInsetTop();}
            int width=root.getWidth()>0?root.getWidth():activity.getResources().getDisplayMetrics().widthPixels;
            FrameLayout.LayoutParams layout=new FrameLayout.LayoutParams(Math.max(1,Math.min(Math.round(520*density),width-Math.round(32*density))),-2,Gravity.TOP|Gravity.CENTER_HORIZONTAL);
            layout.topMargin=safeTop+Math.round(12*density);root.addView(notice,layout);
            Runnable dismiss=()->{if(notice.getParent() instanceof ViewGroup)((ViewGroup)notice.getParent()).removeView(notice);};
            notice.addOnAttachStateChangeListener(new View.OnAttachStateChangeListener(){public void onViewAttachedToWindow(View v){}public void onViewDetachedFromWindow(View v){v.removeCallbacks(dismiss);}});
            notice.postDelayed(dismiss,longer?3500:2200);notice.announceForAccessibility(message);
        });
    }
}
