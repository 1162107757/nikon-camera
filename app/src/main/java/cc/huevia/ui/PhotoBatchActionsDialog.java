package cc.huevia.ui;

import android.app.Activity;
import android.app.Dialog;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.graphics.drawable.StateListDrawable;
import android.os.Build;
import android.text.TextUtils;
import android.view.*;
import android.view.accessibility.AccessibilityNodeInfo;
import android.widget.*;
import java.util.function.IntConsumer;

/** Compact themed action sheet. Only a chosen row dispatches the existing batch callback. */
final class PhotoBatchActionsDialog extends Dialog {
    private final Activity activity;
    private final UiPalette colors;
    private final int count;
    private final IntConsumer action;
    private boolean submitted;
    private LinearLayout shell;
    private int windowWidth=-1,windowHeight=-1,windowBottom=-1;
    static PhotoBatchActionsDialog show(Activity activity,int count,IntConsumer action){
        if(activity.isFinishing()||activity.isDestroyed()||count<1)return null;
        PhotoBatchActionsDialog sheet=new PhotoBatchActionsDialog(activity,count,action);sheet.show();return sheet;
    }
    private PhotoBatchActionsDialog(Activity activity,int count,IntConsumer action){
        super(activity);this.activity=activity;this.count=count;this.action=action;colors=new UiPalette(activity);
        requestWindowFeature(Window.FEATURE_NO_TITLE);setContentView(content());setCanceledOnTouchOutside(true);
        Window window=getWindow();if(window!=null){window.setBackgroundDrawableResource(android.R.color.transparent);window.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);window.setDimAmount(.30f);window.setGravity(Gravity.BOTTOM);window.setNavigationBarColor(colors.surface);
        }
    }
    @Override public void show(){super.show();layoutWindow();}
    private void layoutWindow(){
        Window window=getWindow();if(window==null)return;
        android.util.DisplayMetrics metrics=activity.getResources().getDisplayMetrics();
        android.graphics.Rect frame=new android.graphics.Rect();activity.getWindow().getDecorView().getWindowVisibleDisplayFrame(frame);
        int width=Math.min(dp(560),Math.max(dp(48),(frame.width()>0?frame.width():metrics.widthPixels)-dp(24)));
        int available=Math.max(dp(48),(frame.height()>0?frame.height():metrics.heightPixels)-dp(16));
        shell.measure(View.MeasureSpec.makeMeasureSpec(width,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(0,View.MeasureSpec.UNSPECIFIED));
        int height=Math.min(shell.getMeasuredHeight(),available),bottom=dp(8);
        if(windowWidth!=width||windowHeight!=height){windowWidth=width;windowHeight=height;window.setLayout(width,height);}
        if(windowBottom!=bottom){windowBottom=bottom;WindowManager.LayoutParams params=window.getAttributes();params.y=bottom;window.setAttributes(params);}
    }
    private View content(){
        ScrollView scroll=new ScrollView(getContext());scroll.setTag("batch-actions-sheet");scroll.setFillViewport(false);scroll.setOverScrollMode(View.OVER_SCROLL_NEVER);scroll.setBackground(shape(colors.card,26));scroll.setClipToOutline(true);
        scroll.setOnApplyWindowInsetsListener((v,insets)->{
            layoutWindow();return insets;
        });
        shell=new LinearLayout(getContext());shell.setOrientation(LinearLayout.VERTICAL);shell.setPadding(dp(12),dp(10),dp(12),dp(12));shell.setBackground(shape(colors.card,26));shell.setClipToOutline(true);scroll.addView(shell);
        View handle=new View(getContext());handle.setBackground(shape(colors.outline,2));handle.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);LinearLayout.LayoutParams hp=new LinearLayout.LayoutParams(dp(28),dp(3));hp.gravity=Gravity.CENTER_HORIZONTAL;hp.bottomMargin=dp(5);shell.addView(handle,hp);
        LinearLayout header=new LinearLayout(getContext());header.setGravity(Gravity.CENTER_VERTICAL);header.setPadding(dp(8),0,0,dp(4));
        TextView title=label("批量编辑",17,colors.text);title.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));title.setSingleLine(true);if(Build.VERSION.SDK_INT>=28)title.setAccessibilityHeading(true);header.addView(title,new LinearLayout.LayoutParams(0,dp(48),1));
        TextView total=label(count+" 张",12,colors.secondary);total.setTag("batch-actions-count");total.setSingleLine(true);header.addView(total,new LinearLayout.LayoutParams(-2,-2));
        ImageButton close=new ImageButton(getContext());close.setTag("batch-actions-close");close.setImageDrawable(new AppIcon(AppIcon.Kind.CLOSE,colors.secondary,density()));close.setPadding(dp(14),dp(14),dp(14),dp(14));close.setBackground(ripple(12));close.setContentDescription("取消批量编辑，保留所选照片");close.setOnClickListener(v->dismiss());header.addView(close,new LinearLayout.LayoutParams(dp(48),dp(48)));shell.addView(header);
        shell.addView(option(0,"套用滤镜",AppIcon.Kind.PRESETS,"","为所选照片批量套用滤镜"));
        shell.addView(option(1,"我的配方",AppIcon.Kind.RECIPE,"","为所选照片批量套用我的配方"));
        divider();shell.addView(option(2,"导出照片",AppIcon.Kind.DOWNLOAD,"","按各照片所选版本导出"));
        divider();shell.addView(option(3,"自然精修",AppIcon.Kind.CLEANUP,"","批量自然精修所选照片"));
        shell.addView(option(4,"同步人像设置",AppIcon.Kind.PERSON,"首张","将第一张所选照片的人像设置同步至其余所选照片"));
        return scroll;
    }
    private View option(int id,String title,AppIcon.Kind icon,String trailing,String description){
        LinearLayout row=new LinearLayout(getContext());row.setTag("batch-action-"+id);row.setGravity(Gravity.CENTER_VERTICAL);row.setMinimumHeight(dp(56));row.setPadding(dp(12),dp(8),dp(12),dp(8));row.setFocusable(true);row.setClickable(true);row.setBackground(ripple(14));row.setContentDescription(title+"，"+description);
        row.setAccessibilityDelegate(new View.AccessibilityDelegate(){@Override public void onInitializeAccessibilityNodeInfo(View v,AccessibilityNodeInfo info){super.onInitializeAccessibilityNodeInfo(v,info);info.setClassName(Button.class.getName());}});
        ImageView image=new ImageView(getContext());image.setImageDrawable(new AppIcon(icon,id==2?colors.primary:colors.secondary,density()));image.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);row.addView(image,new LinearLayout.LayoutParams(dp(22),dp(22)));
        TextView text=label(title,14,colors.text);text.setTag("batch-action-label-"+id);text.setMaxLines(2);text.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);LinearLayout.LayoutParams tp=new LinearLayout.LayoutParams(0,-2,1);tp.leftMargin=dp(14);tp.rightMargin=dp(8);row.addView(text,tp);
        if(!trailing.isEmpty()){TextView hint=label(trailing,11,colors.secondary);hint.setSingleLine(true);hint.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-2,-2);p.rightMargin=dp(8);row.addView(hint,p);}
        ImageView arrow=new ImageView(getContext());arrow.setImageDrawable(new AppIcon(AppIcon.Kind.CHEVRON,colors.secondary,density()));arrow.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);row.addView(arrow,new LinearLayout.LayoutParams(dp(16),dp(16)));
        row.setOnClickListener(v->{if(submitted)return;submitted=true;dismiss();action.accept(id);});return row;
    }
    private void divider(){View line=new View(getContext());line.setBackgroundColor(colors.outline);line.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,dp(1));p.setMargins(dp(48),dp(4),dp(12),dp(4));shell.addView(line,p);}
    private android.graphics.drawable.Drawable ripple(int radius){StateListDrawable states=new StateListDrawable();states.addState(new int[]{android.R.attr.state_focused},shape(colors.container,radius));states.addState(new int[]{},shape(Color.TRANSPARENT,radius));return new RippleDrawable(ColorStateList.valueOf(colors.primaryContainer),states,shape(Color.WHITE,radius));}
    private TextView label(String text,int size,int color){TextView t=new TextView(getContext());t.setText(text);t.setTextSize(size);t.setTextColor(color);t.setIncludeFontPadding(false);t.setGravity(Gravity.CENTER_VERTICAL);return t;}
    private GradientDrawable shape(int color,int radius){GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(dp(radius));return d;}
    private float density(){return activity.getResources().getDisplayMetrics().density;}
    private int dp(float value){return Math.round(value*density());}
}
