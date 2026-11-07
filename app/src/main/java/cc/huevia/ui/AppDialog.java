package cc.huevia.ui;

import android.app.AlertDialog;
import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Rect;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.graphics.drawable.StateListDrawable;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowManager;
import android.view.ViewTreeObserver;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.TextView;
import cc.huevia.R;
import java.util.ArrayList;
import java.util.List;

/** Shared alert finish. Keeps Android's buttons, validation, choice model and cancellation semantics. */
public final class AppDialog {
    private AppDialog(){}

    public static class Builder extends AlertDialog.Builder {
        public Builder(Context context){super(context,theme(context,0));}
        public Builder(Context context,int requestedTheme){super(context,theme(context,requestedTheme));}
        @Override public AlertDialog create(){AlertDialog dialog=super.create();attach(dialog);return dialog;}
    }
    private static int theme(Context context,int requested){
        boolean dark=requested==R.style.AppThemeDark||requested==R.style.HueviaDialogDark
                ||(requested!=R.style.AppThemeLight&&requested!=R.style.HueviaDialogLight&&UiPalette.forTheme(context).dark);
        return dark?R.style.HueviaDialogDark:R.style.HueviaDialogLight;
    }
    private static void attach(AlertDialog dialog){
        Window window=dialog.getWindow();if(window==null)return;
        View decor=window.getDecorView();
        decor.addOnAttachStateChangeListener(new View.OnAttachStateChangeListener(){
            private final ViewTreeObserver.OnGlobalLayoutListener layout=()->style(dialog);
            private final ViewTreeObserver.OnScrollChangedListener scroll=()->styleChoices(dialog);
            @Override public void onViewAttachedToWindow(View v){
                style(dialog);v.getViewTreeObserver().addOnGlobalLayoutListener(layout);
                v.getViewTreeObserver().addOnScrollChangedListener(scroll);
                v.post(()->{if(v.isAttachedToWindow())style(dialog);});
            }
            @Override public void onViewDetachedFromWindow(View v){
                if(v.getViewTreeObserver().isAlive()){
                    v.getViewTreeObserver().removeOnGlobalLayoutListener(layout);
                    v.getViewTreeObserver().removeOnScrollChangedListener(scroll);
                }
            }
        });
    }
    static void style(AlertDialog dialog){
        Window window=dialog.getWindow();if(window==null)return;
        Context context=dialog.getContext();UiPalette p=UiPalette.forTheme(context);
        View decor=window.getDecorView();
        if(!Boolean.TRUE.equals(decor.getTag(R.id.huevia_dialog_styled))){
            decor.setTag(R.id.huevia_dialog_styled,true);decor.setPadding(0,0,0,0);
            window.setBackgroundDrawable(shape(context,p.card,24));window.setDimAmount(p.dark?.42f:.28f);
            View panel=named(dialog,"parentPanel");
            if(panel!=null){panel.setBackground(shape(context,p.card,24));panel.setClipToOutline(true);}
            for(String name:new String[]{"topPanel","contentPanel","customPanel","buttonPanel"}){
                View part=named(dialog,name);if(part!=null)part.setBackgroundColor(Color.TRANSPARENT);
            }
            TextView title=named(dialog,"alertTitle") instanceof TextView?(TextView)named(dialog,"alertTitle"):null;
            if(title!=null){title.setTextSize(16);title.setTextColor(p.text);title.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));title.setMaxLines(3);title.setBreakStrategy(android.text.Layout.BREAK_STRATEGY_BALANCED);}
            TextView message=dialog.findViewById(android.R.id.message);
            if(message!=null){message.setTextSize(14);message.setTextColor(p.secondary);message.setLineSpacing(dp(context,3),1);message.setBreakStrategy(android.text.Layout.BREAK_STRATEGY_BALANCED);}
            for(String name:new String[]{"titleDivider","titleDividerNoCustom","titleDividerTop"}){View line=named(dialog,name);if(line!=null)line.setVisibility(View.GONE);}
            insetForm(dialog);fields(decor,p);
        }
        fitWindow(window,decor,context);
        List<Button> buttons=new ArrayList<>();
        for(int which:new int[]{AlertDialog.BUTTON_NEUTRAL,AlertDialog.BUTTON_NEGATIVE,AlertDialog.BUTTON_POSITIVE}){
            Button b=dialog.getButton(which);if(b==null||b.getVisibility()!=View.VISIBLE)continue;buttons.add(b);
            if(!Boolean.TRUE.equals(b.getTag(R.id.huevia_dialog_styled))){
                b.setTag(R.id.huevia_dialog_styled,true);b.setAllCaps(false);b.setTextSize(13);
                b.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));b.setStateListAnimator(null);b.setElevation(0);b.setTranslationZ(0);
                b.setMinWidth(dp(context,64));b.setMinimumWidth(dp(context,64));b.setMinHeight(dp(context,48));b.setMinimumHeight(dp(context,48));
                b.setPadding(dp(context,12),dp(context,8),dp(context,12),dp(context,8));
                boolean primary=which==AlertDialog.BUTTON_POSITIVE;
                String label=b.getText().toString();boolean danger=label.contains("删除")||label.contains("清空");
                int foreground=primary?(danger?p.error:p.onPrimaryContainer):p.secondary;
                b.setTextColor(new ColorStateList(new int[][]{{-android.R.attr.state_enabled},{}},new int[]{alpha(foreground,.4f),foreground}));
                StateListDrawable fill=new StateListDrawable();fill.addState(new int[]{-android.R.attr.state_enabled},shape(context,p.container,12));
                GradientDrawable activeFill=shape(context,primary?(danger?p.card:p.primaryContainer):Color.TRANSPARENT,12);
                if(primary&&danger)activeFill.setStroke(dp(context,1),alpha(p.error,.35f));
                fill.addState(new int[]{},activeFill);
                b.setBackground(new RippleDrawable(ColorStateList.valueOf(alpha(p.primary,.14f)),fill,shape(context,Color.WHITE,12)));
            }
        }
        fitButtons(buttons,context);styleChoices(dialog);
    }
    private static void fitWindow(Window window,View decor,Context context){
        Rect visible=new Rect();Context owner=context;
        while(owner instanceof android.content.ContextWrapper&&!(owner instanceof android.app.Activity)){
            Context next=((android.content.ContextWrapper)owner).getBaseContext();if(next==owner)break;owner=next;
        }
        if(owner instanceof android.app.Activity)((android.app.Activity)owner).getWindow().getDecorView().getWindowVisibleDisplayFrame(visible);
        int screen=context.getResources().getDisplayMetrics().widthPixels;
        if(!visible.isEmpty()&&visible.width()>dp(context,200))screen=visible.width();
        int width=Math.max(dp(context,48),Math.min(dp(context,520),screen-dp(context,32)));
        WindowManager.LayoutParams params=window.getAttributes();if(params.width!=width)window.setLayout(width,WindowManager.LayoutParams.WRAP_CONTENT);
    }
    private static void fitButtons(List<Button> buttons,Context context){
        if(buttons.isEmpty()||!(buttons.get(0).getParent() instanceof LinearLayout))return;
        LinearLayout panel=(LinearLayout)buttons.get(0).getParent();
        int available=panel.getWidth()-panel.getPaddingLeft()-panel.getPaddingRight();
        if(available<=0)return;float desired=0;
        for(Button b:buttons)desired+=Math.max(dp(context,64),b.getPaint().measureText(b.getText().toString())+dp(context,32));
        boolean vertical=buttons.size()>2||desired>available;
        int orientation=vertical?LinearLayout.VERTICAL:LinearLayout.HORIZONTAL;
        if(panel.getOrientation()==orientation&&Boolean.TRUE.equals(panel.getTag(R.id.huevia_dialog_buttons)))return;
        panel.setTag(R.id.huevia_dialog_buttons,true);panel.setOrientation(orientation);panel.setGravity(android.view.Gravity.END|android.view.Gravity.CENTER_VERTICAL);
        if(vertical){
            for(int i=panel.getChildCount()-1;i>=0;i--)if(!(panel.getChildAt(i) instanceof Button))panel.getChildAt(i).setVisibility(View.GONE);
            for(Button b:buttons){panel.removeView(b);LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,-2);lp.topMargin=dp(context,4);panel.addView(b,lp);}
        }else for(Button b:buttons){LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-2,-2);lp.leftMargin=dp(context,4);b.setLayoutParams(lp);}
    }
    private static void fields(View view,UiPalette palette){
        if(view instanceof EditText){EditText field=(EditText)view;field.setTextColor(palette.text);field.setHintTextColor(palette.secondary);field.setTextSize(Math.min(14,field.getTextSize()/field.getResources().getDisplayMetrics().scaledDensity));field.setMinHeight(dp(view.getContext(),48));}
        else if(view instanceof android.widget.CompoundButton){android.widget.CompoundButton control=(android.widget.CompoundButton)view;control.setTextSize(Math.min(14,control.getTextSize()/control.getResources().getDisplayMetrics().scaledDensity));control.setMinHeight(dp(view.getContext(),48));}
        if(view instanceof ViewGroup){ViewGroup group=(ViewGroup)view;for(int i=0;i<group.getChildCount();i++)fields(group.getChildAt(i),palette);}
    }
    private static void styleChoices(AlertDialog dialog){
        ListView list=dialog.getListView();if(list==null)return;UiPalette p=UiPalette.forTheme(dialog.getContext());
        if(!Boolean.TRUE.equals(list.getTag(R.id.huevia_dialog_styled))){list.setTag(R.id.huevia_dialog_styled,true);list.setDivider(null);list.setDividerHeight(0);list.setSelector(new RippleDrawable(ColorStateList.valueOf(alpha(p.primary,.12f)),null,shape(dialog.getContext(),Color.WHITE,12)));}
        for(int i=0;i<list.getChildCount();i++)choiceText(list.getChildAt(i),p,list.getChoiceMode());
    }
    private static void choiceText(View view,UiPalette p,int choiceMode){
        if(view instanceof TextView&&!Boolean.TRUE.equals(view.getTag(R.id.huevia_dialog_styled))){view.setTag(R.id.huevia_dialog_styled,true);TextView label=(TextView)view;label.setTextSize(14);label.setTextColor(new ColorStateList(new int[][]{{-android.R.attr.state_enabled},{}},new int[]{alpha(p.text,.4f),p.text}));label.setMinHeight(dp(view.getContext(),48));label.setMaxLines(3);label.setGravity(android.view.Gravity.CENTER_VERTICAL);}
        if(view instanceof android.widget.CheckedTextView){android.widget.CheckedTextView label=(android.widget.CheckedTextView)view;android.graphics.drawable.Drawable[] marks=label.getCompoundDrawablesRelative();if(marks[0]!=null||marks[2]!=null){if(label.getCheckMarkDrawable()!=null)label.setCheckMarkDrawable(null);}else if(label.getCheckMarkDrawable()==null&&choiceMode!=ListView.CHOICE_MODE_NONE)label.setCheckMarkDrawable(choiceMode==ListView.CHOICE_MODE_MULTIPLE?R.drawable.huevia_check:R.drawable.huevia_radio);}
        if(view instanceof ViewGroup){ViewGroup group=(ViewGroup)view;for(int i=0;i<group.getChildCount();i++)choiceText(group.getChildAt(i),p,choiceMode);}
    }
    private static void insetForm(AlertDialog dialog){
        View custom=named(dialog,"custom");if(!(custom instanceof ViewGroup)||((ViewGroup)custom).getChildCount()!=1)return;
        View child=((ViewGroup)custom).getChildAt(0),content=child;
        if(child instanceof android.widget.ScrollView&&((android.widget.ScrollView)child).getChildCount()==1)content=((android.widget.ScrollView)child).getChildAt(0);
        if((content instanceof EditText||(content instanceof LinearLayout&&content.getPaddingLeft()<dp(content.getContext(),12)))&&custom.getPaddingLeft()<dp(custom.getContext(),12))custom.setPadding(dp(custom.getContext(),12),dp(custom.getContext(),8),dp(custom.getContext(),12),dp(custom.getContext(),8));
    }
    private static View named(AlertDialog dialog,String name){int id=dialog.getContext().getResources().getIdentifier(name,"id","android");return id==0?null:dialog.findViewById(id);}
    private static GradientDrawable shape(Context context,int color,int radius){GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(dp(context,radius));return d;}
    private static int alpha(int color,float alpha){return(color&0xffffff)|(Math.round(255*alpha)<<24);}
    private static int dp(Context context,float dp){return Math.round(dp*context.getResources().getDisplayMetrics().density);}
}
