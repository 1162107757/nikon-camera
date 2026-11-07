package cc.huevia.ncp;

/** Friendly, reversible bundles of existing edit parameters; no new recipe or pixel format. */
public final class PhotoQuickPreset {
    public static final int ORIGINAL=0,NATURAL=1,CLEAR=2,PORTRAIT=3;
    private PhotoQuickPreset(){}
    public static PhotoAdjustments adjustments(PhotoAdjustments base,int style,int amount,PhotoCleanup.Analysis analysis){
        check(style,amount);if(style==ORIGINAL)return base;
        int haze=style==CLEAR?100:style==NATURAL?45:25;
        int noise=style==CLEAR?75:style==NATURAL?85:65;
        int cleanup=style==PORTRAIT?Math.round(amount*.45f):amount;
        PhotoAdjustments next=base.withCleanup(amount==0?PhotoCleanup.NONE:new PhotoCleanup(cleanup,haze,noise,analysis));
        next=add(next,base,PhotoAdjustments.Parameter.BRIGHTNESS,amount*(style==NATURAL?.06:style==PORTRAIT?.03:.015));
        next=add(next,base,PhotoAdjustments.Parameter.CONTRAST,amount*(style==CLEAR?.09:style==NATURAL?.025:0));
        return add(next,base,PhotoAdjustments.Parameter.VIBRANCE,amount*(style==CLEAR?.06:.025));
    }
    public static PhotoPortrait portrait(PhotoPortrait prepared,int style,int amount){
        check(style,amount);if(style!=PORTRAIT)return prepared;
        return prepared.withRetouch(prepared.retouch.with(PortraitRetouch.Parameter.NATURAL,amount));
    }
    /** A preset owns these controls absolutely, so reopening/reapplying never stacks another correction. */
    private static PhotoAdjustments add(PhotoAdjustments next,PhotoAdjustments base,PhotoAdjustments.Parameter p,double delta){return next.with(p,Math.max(p.min,Math.min(p.max,(int)Math.round(delta))));}
    public static int detect(PhotoAdjustments current,PhotoPortrait portrait){
        if(current.cleanup.analysis==null)return -1;
        for(int style=1;style<=3;style++){int amount=amount(current,portrait,style);if(amount>0&&adjustments(current,style,amount,current.cleanup.analysis).equals(current))return style;}
        return -1;
    }
    public static int amount(PhotoAdjustments current,PhotoPortrait portrait,int style){return style==PORTRAIT?portrait.retouch.get(PortraitRetouch.Parameter.NATURAL):current.cleanup.amount;}
    private static void check(int style,int amount){if(style<ORIGINAL||style>PORTRAIT||amount<0||amount>100)throw new IllegalArgumentException("快速优化参数无效。");}
}
