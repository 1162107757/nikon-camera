package cc.huevia.ui;

import android.graphics.Bitmap;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.FrameLayout;

/** Shared display-only selection policy for adjustment subtools. Owns its small mask, not the photo. */
final class PhotoSelectionOverlay implements AutoCloseable {
    private Bitmap mask;
    private PhotoImageView photo;
    private Button toggle;
    private boolean shown=true,interacting,comparing;
    void setMask(Bitmap owned){if(mask!=null&&mask!=owned)mask.recycle();mask=owned;update();}
    void attach(FrameLayout stage,PhotoImageView photo,String tag){
        this.photo=photo;
        toggle=PhotoWorkspaceUi.icon(stage.getContext(),"eye","隐藏选区",tag,()->{shown=!shown;update();});
        int dp=Math.round(48*stage.getResources().getDisplayMetrics().density),margin=Math.round(8*stage.getResources().getDisplayMetrics().density);
        FrameLayout.LayoutParams position=new FrameLayout.LayoutParams(dp,dp,Gravity.TOP|Gravity.END);position.setMargins(margin,margin,margin,margin);stage.addView(toggle,position);update();
    }
    void setInteracting(boolean value){interacting=value;update();}
    void setComparing(boolean value){comparing=value;update();}
    private void update(){if(photo!=null){photo.setSelectionMask(mask);photo.setSelectionMaskVisible(shown&&!interacting&&!comparing);}if(toggle!=null){toggle.setVisibility(mask==null?View.GONE:View.VISIBLE);toggle.setSelected(shown);toggle.setContentDescription(shown?"隐藏选区，保留调整":"显示选区");toggle.setTooltipText(toggle.getContentDescription());}}
    @Override public void close(){if(photo!=null)photo.setSelectionMask(null);if(mask!=null){mask.recycle();mask=null;}}
}
