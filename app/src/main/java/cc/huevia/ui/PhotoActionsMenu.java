package cc.huevia.ui;

import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.graphics.drawable.StateListDrawable;
import android.view.*;
import android.view.accessibility.AccessibilityNodeInfo;
import android.widget.*;
import java.util.function.BooleanSupplier;

/** Anchored photo utilities, using a public Android Menu model to keep the existing action callbacks. */
final class PhotoActionsMenu {
    static final int HISTOGRAM=10,FAVOURITE=11,VERSIONS=12,DETAIL=20,COPY=30,UNDO_COPY=31,
            RESTORE_DRAFT=32,RESET_COLOUR=40,RESTORE_ORIGINAL=41,DELETE=50;
    private static final int BG=0xff19211d,TEXT=PhotoPrismaStyle.WHITE,MUTED=PhotoPrismaStyle.MUTED,
            ACCENT=0xffffe335,DANGER=0xffedaaa3;
    private PhotoActionsMenu(){}

    static MenuItem item(Context context,Menu menu,int group,int id,int order,String title,
                         String hint,AppIcon.Kind icon,Runnable action){
        MenuItem item=menu.add(group,id,order,title);
        item.setIcon(new AppIcon(icon,danger(id)?DANGER:MUTED,context.getResources().getDisplayMetrics().density));
        if(hint!=null&&!hint.isEmpty())item.setTooltipText(hint);
        item.setContentDescription(title+(hint==null||hint.isEmpty()?"":"，"+hint));
        item.setOnMenuItemClickListener(v->{action.run();return true;});return item;
    }

    static PopupWindow show(View anchor,Menu menu,BooleanSupplier current){
        if(!anchor.isAttachedToWindow()||!current.getAsBoolean())return null;
        Context context=anchor.getContext();
        ScrollView scroll=new ScrollView(context);scroll.setTag("photo-actions-menu");
        scroll.setFillViewport(false);scroll.setBackground(shape(context,BG,16));scroll.setClipToOutline(true);
        scroll.setVerticalScrollBarEnabled(true);scroll.setOverScrollMode(View.OVER_SCROLL_NEVER);
        LinearLayout content=new LinearLayout(context);content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(dp(context,8),dp(context,8),dp(context,8),dp(context,8));scroll.addView(content);
        PopupWindow popup=new PopupWindow(scroll,1,1,true);
        popup.setBackgroundDrawable(shape(context,BG,16));popup.setElevation(dp(context,8));
        popup.setOutsideTouchable(true);popup.setInputMethodMode(PopupWindow.INPUT_METHOD_NOT_NEEDED);
        popup.setAnimationStyle(0);
        int previousGroup=-1;
        for(int i=0;i<menu.size();i++){
            MenuItem item=menu.getItem(i);if(!item.isVisible())continue;
            if(previousGroup!=-1&&previousGroup!=item.getGroupId()){
                View line=new View(context);line.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
                line.setBackgroundColor(0x1af4efe9);
                LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,dp(context,1));
                p.setMargins(dp(context,12),dp(context,6),dp(context,12),dp(context,6));content.addView(line,p);
            }
            previousGroup=item.getGroupId();
            content.addView(row(context,item,()->{popup.dismiss();if(current.getAsBoolean())menu.performIdentifierAction(item.getItemId(),0);}),new LinearLayout.LayoutParams(-1,-2));
        }
        int width=Math.max(dp(context,48),Math.min(dp(context,280),anchor.getRootView().getWidth()-dp(context,24)));
        View root=anchor.getRootView();int[] rootOrigin=new int[2],anchorOrigin=new int[2];root.getLocationOnScreen(rootOrigin);anchor.getLocationOnScreen(anchorOrigin);
        int safeTop=rootOrigin[1],safeBottom=rootOrigin[1]+root.getHeight();android.view.WindowInsets insets=root.getRootWindowInsets();
        if(insets!=null){if(android.os.Build.VERSION.SDK_INT>=30){android.graphics.Insets safe=insets.getInsetsIgnoringVisibility(android.view.WindowInsets.Type.systemBars()|android.view.WindowInsets.Type.displayCutout());safeTop+=safe.top;safeBottom-=safe.bottom;}else{safeTop+=insets.getStableInsetTop();safeBottom-=insets.getStableInsetBottom();}}
        int screenSpace=Math.max(safeBottom-anchorOrigin[1]-anchor.getHeight(),anchorOrigin[1]-safeTop)-dp(context,6);
        int available=Math.max(dp(context,48),Math.min(popup.getMaxAvailableHeight(anchor,dp(context,6)),screenSpace));
        scroll.measure(View.MeasureSpec.makeMeasureSpec(width,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(available,View.MeasureSpec.AT_MOST));
        popup.setWidth(width);popup.setHeight(scroll.getMeasuredHeight());
        View.OnAttachStateChangeListener listener=new View.OnAttachStateChangeListener(){
            public void onViewAttachedToWindow(View v){}
            public void onViewDetachedFromWindow(View v){popup.dismiss();}
        };
        anchor.addOnAttachStateChangeListener(listener);
        popup.setOnDismissListener(()->anchor.removeOnAttachStateChangeListener(listener));
        popup.showAsDropDown(anchor,0,dp(context,6),Gravity.START);
        return popup;
    }

    private static View row(Context context,MenuItem item,Runnable action){
        LinearLayout row=new LinearLayout(context);row.setOrientation(LinearLayout.HORIZONTAL);row.setGravity(Gravity.CENTER_VERTICAL);
        row.setTag("photo-action-"+item.getItemId());row.setPadding(dp(context,12),dp(context,8),dp(context,12),dp(context,8));
        CharSequence hint=item.getTooltipText();boolean subtitle=hint!=null&&hint.length()>0;
        row.setMinimumHeight(dp(context,subtitle?56:48));row.setFocusable(true);row.setClickable(true);
        row.setEnabled(item.isEnabled());row.setAlpha(item.isEnabled()?1:.4f);
        row.setContentDescription(item.getContentDescription()==null?item.getTitle():item.getContentDescription());
        GradientDrawable focus=shape(context,0x18ffe335,10);focus.setStroke(dp(context,1),ACCENT);
        StateListDrawable states=new StateListDrawable();states.addState(new int[]{android.R.attr.state_focused},focus);states.addState(new int[]{},shape(context,Color.TRANSPARENT,10));
        row.setBackground(new RippleDrawable(ColorStateList.valueOf(0x22ffe335),states,shape(context,Color.WHITE,10)));
        row.setAccessibilityDelegate(new View.AccessibilityDelegate(){@Override public void onInitializeAccessibilityNodeInfo(View host,AccessibilityNodeInfo info){super.onInitializeAccessibilityNodeInfo(host,info);info.setClassName(Button.class.getName());info.setCheckable(item.isCheckable());if(item.isCheckable())info.setChecked(item.isChecked());}});
        ImageView icon=new ImageView(context);icon.setImageDrawable(item.getIcon());icon.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        row.addView(icon,new LinearLayout.LayoutParams(dp(context,20),dp(context,20)));
        LinearLayout labels=new LinearLayout(context);labels.setOrientation(LinearLayout.VERTICAL);
        LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(0,-2,1);lp.leftMargin=dp(context,12);lp.rightMargin=dp(context,8);row.addView(labels,lp);
        TextView title=label(context,item.getTitle(),14,danger(item.getItemId())?DANGER:item.isChecked()?ACCENT:TEXT);
        title.setTag("photo-action-title-"+item.getItemId());title.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));title.setMaxLines(2);labels.addView(title);
        if(subtitle){TextView detail=label(context,hint,11,MUTED);detail.setTag("photo-action-hint-"+item.getItemId());detail.setMaxLines(2);detail.setEllipsize(android.text.TextUtils.TruncateAt.END);LinearLayout.LayoutParams d=new LinearLayout.LayoutParams(-1,-2);d.topMargin=dp(context,3);labels.addView(detail,d);}
        ImageView end=new ImageView(context);end.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        if(item.isCheckable()&&item.isChecked())end.setImageDrawable(new AppIcon(AppIcon.Kind.CHECK,ACCENT,context.getResources().getDisplayMetrics().density));
        else if(navigation(item.getItemId()))end.setImageDrawable(new AppIcon(AppIcon.Kind.CHEVRON,MUTED,context.getResources().getDisplayMetrics().density));
        row.addView(end,new LinearLayout.LayoutParams(dp(context,18),dp(context,18)));
        row.setOnClickListener(v->{if(item.isEnabled())action.run();});return row;
    }
    private static TextView label(Context c,CharSequence value,int size,int color){TextView t=new TextView(c);t.setText(value);t.setTextSize(size);t.setTextColor(color);t.setIncludeFontPadding(false);t.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);return t;}
    private static boolean danger(int id){return id==RESTORE_ORIGINAL||id==DELETE;}
    private static boolean navigation(int id){return id==VERSIONS||id==DETAIL||id==COPY;}
    private static GradientDrawable shape(Context c,int color,int radius){GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(dp(c,radius));return d;}
    private static int dp(Context c,float value){return Math.round(value*c.getResources().getDisplayMetrics().density);}
}
