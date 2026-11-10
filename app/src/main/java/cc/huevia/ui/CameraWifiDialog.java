package cc.huevia.ui;

import android.app.AlertDialog;
import android.app.Activity;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.RippleDrawable;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.ScrollView;
import android.widget.TextView;
import cc.huevia.R;

/** Presentation only; the host retains Wi-Fi selection, polling and cancellation ownership. */
public final class CameraWifiDialog {
    public final AlertDialog dialog;
    public final TextView status;
    public final Button choose, retry;

    public CameraWifiDialog(Activity activity, boolean waiting) {
        UiPalette palette = UiPalette.home(activity);
        float density = activity.getResources().getDisplayMetrics().density;
        LinearLayout header = new LinearLayout(activity);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(density,24),dp(density,12),dp(density,12),dp(density,8));
        TextView title = text(activity, waiting ? "正在连接相机" : "连接相机 Wi-Fi",16,palette.text,true);
        title.setMaxLines(3);
        header.addView(title,new LinearLayout.LayoutParams(0,-2,1));
        ImageView close = new ImageView(activity);
        close.setImageDrawable(new AppIcon(AppIcon.Kind.CLOSE,palette.secondary,density));
        close.setPadding(dp(density,14),dp(density,14),dp(density,14),dp(density,14));
        close.setContentDescription("取消连接");close.setTag("camera-wifi-close");close.setFocusable(true);
        close.setBackground(new RippleDrawable(ColorStateList.valueOf(palette.container),null,HueTheme.rounded(Color.WHITE,dp(density,24))));
        LinearLayout.LayoutParams closeLayout = new LinearLayout.LayoutParams(dp(density,48),dp(density,48));
        closeLayout.leftMargin=dp(density,8);header.addView(close,closeLayout);

        LinearLayout content = new LinearLayout(activity);content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(dp(density,24),0,dp(density,24),dp(density,16));
        TextView explanation = text(activity,waiting ? "正在确认当前 Wi-Fi，请保持相机热点开启。"
                : "在系统 Wi-Fi 中选择相机热点，返回后自动继续。",14,palette.secondary,false);
        explanation.setLineSpacing(dp(density,3),1);content.addView(explanation);
        status=text(activity,"",13,palette.secondary,false);status.setTag("camera-wifi-status");
        status.setLineSpacing(dp(density,3),1);status.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);
        status.setVisibility(View.GONE);
        LinearLayout.LayoutParams statusLayout=new LinearLayout.LayoutParams(-1,-2);statusLayout.topMargin=dp(density,16);
        content.addView(status,statusLayout);
        if(waiting){
            ProgressBar progress=new ProgressBar(activity);progress.setIndeterminateTintList(ColorStateList.valueOf(palette.text));
            LinearLayout.LayoutParams progressLayout=new LinearLayout.LayoutParams(dp(density,24),dp(density,24));
            progressLayout.topMargin=dp(density,20);progressLayout.bottomMargin=dp(density,12);progressLayout.gravity=Gravity.CENTER_HORIZONTAL;
            content.addView(progress,progressLayout);
        }
        choose=action(activity,"选择相机 Wi-Fi",palette,true);choose.setTag("camera-wifi-choose");
        LinearLayout.LayoutParams chooseLayout=new LinearLayout.LayoutParams(-1,-2);chooseLayout.topMargin=dp(density,20);
        content.addView(choose,chooseLayout);if(waiting)choose.setVisibility(View.GONE);
        retry=action(activity,waiting?"取消连接":"我已连接，继续",palette,false);retry.setTag("camera-wifi-retry");
        LinearLayout.LayoutParams retryLayout=new LinearLayout.LayoutParams(-1,-2);retryLayout.topMargin=dp(density,8);
        content.addView(retry,retryLayout);
        ScrollView scroll=new ScrollView(activity){
            @Override protected void onMeasure(int width,int height){
                int limit=Math.max(dp(density,120),activity.getResources().getDisplayMetrics().heightPixels-dp(density,200));
                if(MeasureSpec.getMode(height)!=MeasureSpec.UNSPECIFIED)limit=Math.min(limit,MeasureSpec.getSize(height));
                super.onMeasure(width,MeasureSpec.makeMeasureSpec(limit,MeasureSpec.AT_MOST));
            }
        };
        scroll.setClipToPadding(false);scroll.addView(content);
        dialog=new AppDialog.Builder(activity,palette.dark?R.style.AppThemeDark:R.style.AppThemeLight)
                .setCustomTitle(header).setView(scroll).create();
        close.setOnClickListener(v->dialog.cancel());
        if(waiting)retry.setOnClickListener(v->dialog.cancel());
    }
    private static Button action(Activity activity,String label,UiPalette palette,boolean primary){
        float density=activity.getResources().getDisplayMetrics().density;
        Button button=new Button(activity);button.setText(label);button.setTextSize(14);button.setAllCaps(false);
        button.setIncludeFontPadding(false);button.setGravity(Gravity.CENTER);button.setMinWidth(0);button.setMinimumWidth(0);
        button.setTypeface(Typeface.create(primary?"sans-serif-medium":"sans-serif",Typeface.NORMAL));
        button.setPadding(dp(density,16),dp(density,12),dp(density,16),dp(density,12));
        HueTheme.styleAction(button,palette,primary);
        if(!primary){
            button.setTextColor(palette.secondary);
            button.setBackground(new RippleDrawable(ColorStateList.valueOf(palette.container),null,HueTheme.rounded(Color.WHITE,dp(density,26))));
        }
        return button;
    }
    private static TextView text(Activity activity,String value,int sp,int color,boolean medium){
        TextView text=new TextView(activity);text.setText(value);text.setTextSize(sp);text.setTextColor(color);
        text.setIncludeFontPadding(false);text.setTypeface(Typeface.create(medium?"sans-serif-medium":"sans-serif",Typeface.NORMAL));return text;
    }
    private static int dp(float density,float value){return Math.round(density*value);}
}
