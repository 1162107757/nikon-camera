package cc.huevia.ncp;
import java.util.*;

/** Regressions for parameter bundles used by the new common editor path. */
public final class PhotoQuickPresetTest {
    private static int checks;
    private static void check(boolean value,String name){checks++;if(!value)throw new AssertionError(name);}
    public static void main(String[] args)throws Exception{
        PhotoCleanup.Analysis analysis=new PhotoCleanup.Analysis(1200,800,1,32,20,80,70,30,220,225,230,8,10);
        PhotoAdjustments base=PhotoAdjustments.NONE.with(PhotoAdjustments.Parameter.TEMPERATURE,-17).with(PhotoAdjustments.Parameter.EXPOSURE,-2).with(PhotoAdjustments.Parameter.HIGHLIGHTS,-31).with(PhotoAdjustments.Parameter.CONTRAST,99).with(PhotoAdjustments.Parameter.VIBRANCE,98).withCleanup(new PhotoCleanup(28,60,30,analysis));
        for(int style=1;style<=3;style++)for(int amount=0;amount<=100;amount++){
            PhotoAdjustments next=PhotoQuickPreset.adjustments(base,style,amount,analysis);
            check(next.equals(PhotoQuickPreset.adjustments(base,style,amount,analysis)),"same baseline never accumulates");
            check(next.get(PhotoAdjustments.Parameter.TEMPERATURE)==-17&&next.get(PhotoAdjustments.Parameter.EXPOSURE)==-2&&next.get(PhotoAdjustments.Parameter.HIGHLIGHTS)==-31,"independent controls retained");
            for(PhotoAdjustments.Parameter p:PhotoAdjustments.Parameter.values())check(next.get(p)>=p.min&&next.get(p)<=p.max,"bounded compound controls");
            if(amount==0)check(next.cleanup.equals(PhotoCleanup.NONE)&&next.get(PhotoAdjustments.Parameter.BRIGHTNESS)==0&&next.get(PhotoAdjustments.Parameter.CONTRAST)==0&&next.get(PhotoAdjustments.Parameter.VIBRANCE)==0,"zero disables preset-owned controls");
            check(next.equals(PhotoQuickPreset.adjustments(next,style,amount,analysis)),"reapplying a saved preset never accumulates");
            if(amount>0&&style!=3)check(PhotoQuickPreset.detect(next,PhotoPortrait.NONE)==style,"saved colour preset recognized from parameters");
            int pixel=0x786f887c,result=AdjustedPreviewProfile.of(null,next).applyArgb(pixel);
            check((result>>>24)==(pixel>>>24),"alpha retained");
        }
        check(PhotoQuickPreset.adjustments(base,0,100,analysis).equals(base),"original bundle leaves baseline unchanged");
        check(PhotoQuickPreset.adjustments(base,2,55,analysis).cleanup.haze>PhotoQuickPreset.adjustments(base,1,55,analysis).cleanup.haze,"clear emphasizes haze removal");
        PortraitRetouch manual=PortraitRetouch.NONE.with(PortraitRetouch.Parameter.TEXTURE,82).with(PortraitRetouch.Parameter.TEETH,34).with(PortraitRetouch.Parameter.NATURAL,62);
        PhotoPortrait person=PhotoPortrait.NONE.withSkinSmoothing(27).withRetouch(manual);
        for(int amount:new int[]{0,20,70,100}){
            PhotoPortrait next=PhotoQuickPreset.portrait(person,3,amount);
            check(next.retouch.get(PortraitRetouch.Parameter.NATURAL)==amount,"natural amount can decrease and turn off");
            check(next.skinSmoothing==27&&next.retouch.get(PortraitRetouch.Parameter.TEXTURE)==82&&next.retouch.get(PortraitRetouch.Parameter.TEETH)==34,"manual retouch retained");
            if(amount>0){PhotoAdjustments tone=PhotoQuickPreset.adjustments(base,3,amount,analysis);check(PhotoQuickPreset.detect(tone,next)==3&&PhotoQuickPreset.amount(tone,next,3)==amount,"saved portrait shortcut recognized");}
        }
        check(PhotoQuickPreset.portrait(person,1,70).equals(person),"colour style does not touch portrait");
        for(int[] bad:new int[][]{{-1,40},{4,40},{1,-1},{1,101}}){try{PhotoQuickPreset.adjustments(base,bad[0],bad[1],analysis);throw new AssertionError("invalid accepted");}catch(IllegalArgumentException expected){checks++;}}
        System.out.println("PASS PhotoQuickPresetTest "+checks+" checks");
    }
}
