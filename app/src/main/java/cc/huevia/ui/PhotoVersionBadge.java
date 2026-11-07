package cc.huevia.ui;

import android.content.Context;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.view.Gravity;
import android.view.View;
import android.widget.*;

/** Compact album-stack count, with a 48dp minimum touch target inside the thumbnail. */
public final class PhotoVersionBadge extends FrameLayout {
    public PhotoVersionBadge(Context context,int count,Runnable click){
        this(context,count,"",click);
    }
    public PhotoVersionBadge(Context context,int count,String name,Runnable click){
        super(context);setTag("photo-version-badge");setMinimumWidth(dp(48));setMinimumHeight(dp(48));setFocusable(true);setClickable(true);setContentDescription("当前版本 "+name+"，"+count+"个版本，选择照片版本");setTooltipText(name+" · "+count+"个版本");
        LinearLayout face=new LinearLayout(context);face.setTag("photo-version-badge-face");face.setGravity(Gravity.CENTER);face.setPadding(dp(7),0,dp(7),0);GradientDrawable background=new GradientDrawable();background.setColor(0xdd292724);background.setCornerRadius(dp(6));face.setBackground(background);face.setMinimumWidth(dp(36));
        ImageView icon=new ImageView(context);icon.setImageDrawable(new AppIcon(AppIcon.Kind.STACK,Color.WHITE,getResources().getDisplayMetrics().density));icon.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);face.addView(icon,new LinearLayout.LayoutParams(dp(13),dp(13)));
        TextView number=new TextView(context);number.setText(name.isEmpty()?String.valueOf(count):name);number.setTextSize(11);number.setTextColor(Color.WHITE);number.setSingleLine(true);number.setEllipsize(android.text.TextUtils.TruncateAt.END);number.setMaxWidth(dp(94));number.setIncludeFontPadding(false);number.setGravity(Gravity.CENTER);number.setPadding(dp(4),0,0,0);number.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);face.addView(number,new LinearLayout.LayoutParams(-2,-1));
        addView(face,new FrameLayout.LayoutParams(-2,Math.max(dp(24),(int)(number.getTextSize()*1.45f)),Gravity.BOTTOM|Gravity.END));setOnClickListener(v->click.run());
    }
    private int dp(int value){return Math.round(value*getResources().getDisplayMetrics().density);}
}
