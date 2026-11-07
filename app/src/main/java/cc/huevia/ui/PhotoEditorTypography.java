package cc.huevia.ui;

import android.app.AlertDialog;
import android.app.Dialog;
import android.content.Context;

/** Shared text scale for the photo editor's native secondary dialogs. */
final class PhotoEditorTypography {
    private PhotoEditorTypography() {}
    static void apply(Dialog dialog) {
        if (dialog instanceof AlertDialog) AppDialog.style((AlertDialog) dialog);
    }
    static final class Builder extends AppDialog.Builder {
        Builder(Context context) { super(context); }
    }
}
