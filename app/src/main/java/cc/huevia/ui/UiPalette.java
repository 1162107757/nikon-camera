package cc.huevia.ui;

import android.content.Context;
import android.graphics.Color;

/** Orange light: warm photographic surfaces, terracotta selection and charcoal actions. */
public final class UiPalette {
    public final int surface, container, text, secondary, primary, onPrimary, primaryContainer, outline, success, error;
    public final int card, glass, rim, action, onAction, actionEnd, onPrimaryContainer, photoAccent, photoTrack;
    public final boolean dark, home;
    public UiPalette(Context context) { this(AppAppearance.isDark(context)); }
    private UiPalette(boolean dark) { this(dark, false); }
    public static UiPalette home(Context context) { return new UiPalette(AppAppearance.isDark(context), true); }
    private UiPalette(boolean dark, boolean home) {
        this.dark = dark; this.home = home;
        surface = color(home ? (dark ? "#201F1D" : "#F8F7F4") : (dark ? "#201F1D" : "#FAFAF8"));
        container = color(home ? (dark ? "#34312D" : "#EEECE6") : (dark ? "#33302C" : "#EFEDE9"));
        card = color(home ? (dark ? "#292724" : "#FFFFFF") : (dark ? "#292724" : "#FFFFFF"));
        text = color(home ? (dark ? "#F6F1EB" : "#242320") : (dark ? "#F6F1EB" : "#262320"));
        secondary = color(home ? (dark ? "#CAC2B8" : "#635D53") : (dark ? "#BAB1A7" : "#706A63"));
        primary = color(home ? (dark ? "#F1ECE4" : "#242420") : (dark ? "#F3B493" : "#B3432D"));
        onPrimary = color(home ? (dark ? "#29251F" : "#FFFFFF") : (dark ? "#352016" : "#FFFFFF"));
        primaryContainer = color(home ? (dark ? "#F1ECE4" : "#242420") : (dark ? "#51382D" : "#F4D6C0"));
        onPrimaryContainer = color(home ? (dark ? "#29251F" : "#FFFFFF") : (dark ? "#F3B493" : "#85311F"));
        photoAccent = color("#F3B493"); photoTrack = color("#635247");
        outline = color(dark ? "#4C4640" : "#E4DFD8");
        success = color(dark ? "#9AC8AE" : "#42735B");
        error = color(dark ? "#FFB4A7" : "#AD3B30");
        action = color(home ? (dark ? "#F1ECE4" : "#242420") : (dark ? "#F0E8DF" : "#46413B"));
        actionEnd = color(home ? (dark ? "#F1ECE4" : "#242420") : (dark ? "#DAD0C5" : "#27241F"));
        onAction = color(home ? (dark ? "#29251F" : "#FFFFFF") : (dark ? "#26211C" : "#FFFFFF"));
        // The substantial tint keeps navigation labels readable over photographs.
        glass = color(home ? (dark ? "#EE2C2A26" : "#EEFFFFFF") : (dark ? "#F0292724" : "#F5FAFAF8"));
        rim = color(dark ? "#30FFFFFF" : "#CFFFFFFF");
    }
    /** Secondary windows retain an explicitly themed editor context. */
    static UiPalette forTheme(Context context) {
        android.util.TypedValue value=new android.util.TypedValue();
        if(context.getTheme().resolveAttribute(android.R.attr.windowLightStatusBar,value,true)
                &&value.type==android.util.TypedValue.TYPE_INT_BOOLEAN)return new UiPalette(value.data==0);
        return new UiPalette(context);
    }
    private static int color(String hex) { return Color.parseColor(hex); }
}
