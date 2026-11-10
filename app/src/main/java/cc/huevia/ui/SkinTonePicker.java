package cc.huevia.ui;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.res.ColorStateList;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.ComposeShader;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PorterDuff;
import android.graphics.RectF;
import android.graphics.Shader;
import android.os.Build;
import android.text.InputFilter;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.SeekBar;
import android.widget.TextView;
import java.util.Locale;

/** Focused HSV colour selection. It never edits a photograph until Use is pressed. */
final class SkinTonePicker {
    interface Listener { void use(int colorRGB); void sample(int colorRGB); void saved(); void cancel(); default void interaction(boolean active){} }
    private static final int TEXT=0xfff4f5f7,MUTED=PhotoPrismaStyle.MUTED,ACCENT=PhotoPrismaStyle.YELLOW;
    private final Activity activity;
    private final SkinToneSwatches swatches;
    private final Listener listener;
    private final float[] hsv=new float[3];
    private final SeekBar[] sliders=new SeekBar[3];
    private final TextView[] values=new TextView[3];
    private AlertDialog dialog,nameDialog;
    private TextView preview,message;
    private SaturationValueView palette;
    private boolean syncing,interacting;
    private void interaction(boolean active){if(interacting==active)return;interacting=active;listener.interaction(active);}

    SkinTonePicker(Activity activity,int colorRGB,SkinToneSwatches swatches,Listener listener) {
        this.activity=activity;this.swatches=swatches;this.listener=listener;
        Color.colorToHSV(0xff000000|colorRGB,hsv);
    }

    void show() {
        LinearLayout content=column();content.setPadding(dp(20),dp(8),dp(20),dp(4));
        preview=text("",14,TEXT);preview.setTag("skin-tone-preview");preview.setGravity(Gravity.CENTER);
        content.addView(preview,new LinearLayout.LayoutParams(-1,dp(52)));
        palette=new SaturationValueView();palette.setTag("skin-tone-sv");
        palette.setContentDescription("饱和度和明度色盘，横向调整饱和度，纵向调整明度");
        content.addView(palette,new LinearLayout.LayoutParams(-1,dp(152)));
        String[] names={"色相","饱和度","明度"},tags={"skin-tone-hue","skin-tone-saturation","skin-tone-value"};
        for(int i=0;i<3;i++) {
            final int axis=i;LinearLayout row=row();TextView label=text(names[i],12,TEXT);
            row.addView(label,new LinearLayout.LayoutParams(dp(56),dp(48)));
            SeekBar slider=new SeekBar(activity);sliders[i]=slider;slider.setTag(tags[i]);slider.setMax(i==0?360:100);
            slider.setThumbTintList(ColorStateList.valueOf(ACCENT));slider.setProgressTintList(ColorStateList.valueOf(ACCENT));
            row.addView(slider,new LinearLayout.LayoutParams(0,dp(48),1));
            values[i]=text("",12,MUTED);values[i].setGravity(Gravity.END|Gravity.CENTER_VERTICAL);
            row.addView(values[i],new LinearLayout.LayoutParams(dp(44),dp(48)));content.addView(row);
            slider.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){
                public void onProgressChanged(SeekBar seek,int progress,boolean user){if(user&&!syncing){hsv[axis]=axis==0?progress:progress/100f;refresh();}}
                public void onStartTrackingTouch(SeekBar seek){interaction(true);}
                public void onStopTrackingTouch(SeekBar seek){interaction(false);}
            });
        }
        LinearLayout actions=row();
        actions.addView(action("照片取色","skin-tone-sample",()->{int color=color();dialog.dismiss();listener.sample(color);}),new LinearLayout.LayoutParams(0,dp(48),1));
        actions.addView(action("保存色卡","skin-tone-save",this::save),new LinearLayout.LayoutParams(0,dp(48),1));content.addView(actions);
        message=text("保存的色卡可在其他照片中使用。",12,MUTED);message.setPadding(0,dp(8),0,dp(8));content.addView(message,new LinearLayout.LayoutParams(-1,-2));
        ScrollView scroll=new ScrollView(activity);scroll.setFillViewport(false);scroll.addView(content);
        dialog=new AppDialog.Builder(activity,cc.huevia.R.style.AppThemeDark).setTitle("自定义肤色").setView(scroll)
                .setNegativeButton("取消",(d,w)->listener.cancel()).setPositiveButton("预览效果",(d,w)->listener.use(color())).create();
        dialog.setOnCancelListener(d->listener.cancel());
        dialog.setOnDismissListener(d->interaction(false));
        dialog.setOnShowListener(d->{dialog.getButton(AlertDialog.BUTTON_POSITIVE).setTag("skin-tone-use");dialog.getButton(AlertDialog.BUTTON_POSITIVE).setTextColor(ACCENT);refresh();});
        dialog.show();
        dialog.getWindow().getDecorView().getViewTreeObserver().addOnWindowFocusChangeListener(focused->{if(!focused)interaction(false);});
        if(dialog.getWindow()!=null){dialog.getWindow().setGravity(Gravity.BOTTOM);dialog.getWindow().setLayout(Math.min(dp(520),activity.getResources().getDisplayMetrics().widthPixels-dp(24)),Math.min(dp(560),Math.round(activity.getResources().getDisplayMetrics().heightPixels*.68f)));}
    }

    void dismiss(){interaction(false);if(nameDialog!=null)nameDialog.dismiss();if(dialog!=null)dialog.dismiss();}

    private int color(){return Color.HSVToColor(hsv)&0xffffff;}
    private void refresh(){
        if(preview==null)return;syncing=true;
        for(int i=0;i<3;i++){int p=Math.round(i==0?hsv[i]:hsv[i]*100);sliders[i].setProgress(p);values[i].setText(p+(i==0?"°":"%"));sliders[i].setContentDescription((i==0?"色相":i==1?"饱和度":"明度")+" "+values[i].getText());}
        int color=0xff000000|color();preview.setBackgroundColor(color);
        double luminance=.2126*linear(Color.red(color))+.7152*linear(Color.green(color))+.0722*linear(Color.blue(color));
        preview.setTextColor(luminance>.179?Color.BLACK:Color.WHITE);preview.setText(String.format(Locale.ROOT,"预览  #%06X",color&0xffffff));
        palette.invalidate();syncing=false;
    }

    private void save(){
        EditText name=new EditText(new android.view.ContextThemeWrapper(activity,cc.huevia.R.style.AppThemeDark));name.setSingleLine(true);name.setTextColor(TEXT);name.setHintTextColor(MUTED);name.setHint("例如：日常暖肤");name.setTextSize(14);name.setFilters(new InputFilter[]{new InputFilter.LengthFilter(12)});name.setTag("skin-tone-name");
        LinearLayout box=column();box.setPadding(dp(24),dp(8),dp(24),0);box.addView(name,new LinearLayout.LayoutParams(-1,dp(56)));
        nameDialog=new AppDialog.Builder(activity,cc.huevia.R.style.AppThemeDark).setTitle("保存个人色卡").setMessage("仅保存在这台设备，最多 12 张。").setView(box).setNegativeButton("取消",null).setPositiveButton("保存",null).create();
        nameDialog.setOnShowListener(d->{Button save=nameDialog.getButton(AlertDialog.BUTTON_POSITIVE);save.setTag("skin-tone-name-save");save.setTextColor(ACCENT);save.setOnClickListener(v->{try{swatches.save(name.getText().toString(),color());nameDialog.dismiss();message.setText("已保存，可在肤色栏中重复使用。");message.announceForAccessibility(message.getText());listener.saved();}catch(Exception error){name.setError(error.getMessage());}});});nameDialog.show();
    }

    private Button action(String title,String tag,Runnable run){Button button=new Button(activity);button.setText(title);button.setTag(tag);button.setTextSize(13);button.setTextColor(ACCENT);button.setAllCaps(false);button.setMinHeight(dp(48));button.setPadding(dp(4),0,dp(4),0);button.setBackgroundColor(Color.TRANSPARENT);button.setOnClickListener(v->run.run());return button;}
    private LinearLayout column(){LinearLayout view=new LinearLayout(activity);view.setOrientation(LinearLayout.VERTICAL);return view;}
    private LinearLayout row(){LinearLayout view=new LinearLayout(activity);view.setOrientation(LinearLayout.HORIZONTAL);view.setGravity(Gravity.CENTER_VERTICAL);return view;}
    private TextView text(String text,int size,int color){TextView view=new TextView(activity);view.setText(text);view.setTextSize(size);view.setTextColor(color);view.setGravity(Gravity.CENTER_VERTICAL);return view;}
    private int dp(float value){return Math.round(value*activity.getResources().getDisplayMetrics().density);}
    private static double linear(int channel){double value=channel/255.0;return value<=.04045?value/12.92:Math.pow((value+.055)/1.055,2.4);}

    private final class SaturationValueView extends View {
        private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);
        SaturationValueView(){super(activity);if(Build.VERSION.SDK_INT<28)setLayerType(View.LAYER_TYPE_SOFTWARE,null);setFocusable(true);setClickable(true);}
        @Override protected void onDraw(Canvas canvas){
            float pad=dp(4),width=getWidth()-2*pad,height=getHeight()-2*pad;if(width<=0||height<=0)return;
            RectF area=new RectF(pad,pad,pad+width,pad+height);Path clip=new Path();clip.addRoundRect(area,dp(10),dp(10),Path.Direction.CW);canvas.save();canvas.clipPath(clip);
            int hue=Color.HSVToColor(new float[]{hsv[0],1,1});
            paint.setShader(new ComposeShader(new LinearGradient(pad,pad,pad+width,pad,Color.WHITE,hue,Shader.TileMode.CLAMP),new LinearGradient(pad,pad,pad,pad+height,Color.WHITE,Color.BLACK,Shader.TileMode.CLAMP),PorterDuff.Mode.MULTIPLY));
            paint.setStyle(Paint.Style.FILL);canvas.drawRect(area,paint);paint.setShader(null);
            float x=pad+hsv[1]*width,y=pad+(1-hsv[2])*height;paint.setStyle(Paint.Style.STROKE);paint.setStrokeWidth(dp(4));paint.setColor(0x99000000);canvas.drawCircle(x,y,dp(8),paint);paint.setStrokeWidth(dp(2));paint.setColor(Color.WHITE);canvas.drawCircle(x,y,dp(8),paint);canvas.restore();
        }
        @Override public boolean onTouchEvent(MotionEvent event){
            int action=event.getActionMasked();if(action==MotionEvent.ACTION_DOWN)interaction(true);if(action==MotionEvent.ACTION_UP||action==MotionEvent.ACTION_CANCEL){interaction(false);getParent().requestDisallowInterceptTouchEvent(false);}
            if(event.getActionMasked()==MotionEvent.ACTION_DOWN||event.getActionMasked()==MotionEvent.ACTION_MOVE||event.getActionMasked()==MotionEvent.ACTION_UP){getParent().requestDisallowInterceptTouchEvent(true);float pad=dp(4);hsv[1]=Math.max(0,Math.min(1,(event.getX()-pad)/Math.max(1,getWidth()-2*pad)));hsv[2]=1-Math.max(0,Math.min(1,(event.getY()-pad)/Math.max(1,getHeight()-2*pad)));refresh();if(event.getActionMasked()==MotionEvent.ACTION_UP)performClick();return true;}return true;
        }
        @Override public boolean performClick(){return super.performClick();}
    }
}
