package cc.huevia.ui;

import android.app.AlertDialog;
import android.app.Dialog;
import android.content.Context;
import android.graphics.Typeface;
import android.view.View;
import android.view.ViewGroup;
import android.widget.EditText;
import android.widget.TextView;

/** Shared text scale for the photo editor's native secondary dialogs. */
final class PhotoEditorTypography {
    private PhotoEditorTypography() {}
    static void apply(Dialog dialog) {
        if (!(dialog instanceof AlertDialog) || dialog.getWindow() == null) return;
        AlertDialog alert = (AlertDialog) dialog;
        int titleId = dialog.getContext().getResources().getIdentifier("alertTitle", "id", "android");
        View title = dialog.findViewById(titleId);
        if (title instanceof TextView) {
            TextView text = (TextView) title;
            text.setTextSize(14);
            text.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
            text.setMaxLines(2);
        }
        TextView message = dialog.findViewById(android.R.id.message);
        if (message != null) message.setTextSize(13);
        for (int which : new int[]{-1, -2, -3}) {
            TextView button = alert.getButton(which);
            if (button != null) {
                button.setTextSize(12);
                button.setAllCaps(false);
                button.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
            }
        }
        inputs(dialog.getWindow().getDecorView());
    }
    private static void inputs(View view) {
        if (view instanceof EditText) ((EditText) view).setTextSize(13);
        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            for (int i = 0; i < group.getChildCount(); i++) inputs(group.getChildAt(i));
        }
    }
    static final class Builder extends AlertDialog.Builder {
        Builder(Context context) { super(context); }
        @Override public AlertDialog show() {
            AlertDialog dialog = super.show();
            apply(dialog);
            return dialog;
        }
    }
}
