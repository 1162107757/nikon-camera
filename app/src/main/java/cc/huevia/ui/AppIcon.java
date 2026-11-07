package cc.huevia.ui;

import android.graphics.Canvas;
import android.graphics.ColorFilter;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PixelFormat;
import android.graphics.RectF;
import android.graphics.drawable.Drawable;

/** One family of compact vector pictograms, no font/emoji-dependent navigation. */
public final class AppIcon extends Drawable {
    public enum Kind { PRESETS, ALBUM, CAMERA, FILE, DOWNLOAD, BACK, HELP, CHECK, WIFI, ADJUST, REFRESH,
        SETTINGS, PLUS, USB, CHEVRON, CHEVRON_DOWN, INFO, LINK, DELETE, STAR, STAR_FILLED, RECEIPTS, PERSON, EXPAND, GRID, CLOSE, SEARCH,
        UNDO, REDO, COMPARE, MORE, BRIGHTNESS, EXPOSURE, CONTRAST, HIGHLIGHTS, SHADOWS, WHITES, BLACKS, TEMPERATURE, TINT, SATURATION, VIBRANCE, CLARITY, SHARPENING,
        CROP, ROTATE, STRAIGHTEN, PERSPECTIVE, RECIPE, SAVE, HISTOGRAM, DETAIL, CURVE, STACK, BRUSH, PALETTE, CLEANUP, BODY, MORE_HORIZONTAL, FILTER, FRAME, FLIP_HORIZONTAL, SPLIT_COMPARE }
    private final Kind kind;
    private final Paint ink = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final int size;
    public AppIcon(Kind kind, int color, float density) {
        this.kind = kind; size = Math.round(24 * density);
        ink.setColor(color); ink.setStyle(Paint.Style.STROKE); ink.setStrokeWidth(1.8f);
        ink.setStrokeCap(Paint.Cap.ROUND); ink.setStrokeJoin(Paint.Join.ROUND);
    }
    @Override public void draw(Canvas canvas) {
        int save = canvas.save(); canvas.translate(getBounds().left, getBounds().top);
        canvas.scale(getBounds().width()/24f, getBounds().height()/24f);
        switch (kind) {
            case SPLIT_COMPARE: line(canvas,12,3,12,21);Path split=new Path();split.moveTo(9,5);split.lineTo(5,5);split.quadTo(3,5,3,7);split.lineTo(3,17);split.quadTo(3,19,5,19);split.lineTo(9,19);split.moveTo(15,5);split.lineTo(19,5);split.quadTo(21,5,21,7);split.lineTo(21,17);split.quadTo(21,19,19,19);split.lineTo(15,19);canvas.drawPath(split,ink);line(canvas,16,9,19,12,16,15);break;
            case FILTER: canvas.drawCircle(9,9,5.5f,ink);canvas.drawCircle(15,9,5.5f,ink);canvas.drawCircle(12,15,5.5f,ink);break;
            case FRAME: canvas.drawRoundRect(new RectF(3,3,21,21),2,2,ink);canvas.drawRect(7,7,17,17,ink);break;
            case FLIP_HORIZONTAL: line(canvas,12,2,12,22);Path mirror=new Path();mirror.moveTo(8,5);mirror.lineTo(3,19);mirror.lineTo(8,19);mirror.close();canvas.drawPath(mirror,ink);Path reflected=new Path();reflected.moveTo(16,5);reflected.lineTo(21,19);reflected.lineTo(16,19);reflected.close();canvas.drawPath(reflected,ink);break;
            case BODY:
                Path body=new Path();body.moveTo(7,3);body.cubicTo(10,8,9,10,7,13);body.cubicTo(5,16,5,19,6,22);body.moveTo(17,3);body.cubicTo(14,8,15,10,17,13);body.cubicTo(19,16,19,19,18,22);canvas.drawPath(body,ink);line(canvas,2,11,5,11);line(canvas,3,9,5,11,3,13);line(canvas,22,11,19,11);line(canvas,21,9,19,11,21,13);break;
            case CLEANUP:
                canvas.drawArc(new RectF(8,5,16,13),180,180,false,ink);line(canvas,12,1,12,3);line(canvas,4,5,6,6);line(canvas,18,6,20,5);line(canvas,3,14,21,14);line(canvas,5,18,19,18);line(canvas,8,22,16,22);break;
            case PALETTE:
                canvas.drawRoundRect(new RectF(3,3,21,21),3,3,ink);line(canvas,7,12,17,12);line(canvas,12,7,12,17);canvas.drawCircle(15.5f,8.5f,2.5f,ink);break;
            case BRUSH:
                line(canvas,10,15,7,12,17,3,21,7,12,17,10,15);
                Path brush=new Path();brush.moveTo(7,14);brush.cubicTo(2,14,6,20,2,21);brush.cubicTo(8,23,12,19,9,16);canvas.drawPath(brush,ink);break;
            case HISTOGRAM: line(canvas,3,4,3,21,22,21);line(canvas,7,17,7,12);line(canvas,11,17,11,6);line(canvas,15,17,15,3);line(canvas,19,17,19,10);break;
            case CURVE: line(canvas,3,3,3,21,21,21);Path curve=new Path();curve.moveTo(4,19);curve.cubicTo(15,19,9,5,21,4);canvas.drawPath(curve,ink);break;
            case STACK: canvas.drawRoundRect(new RectF(3,3,16,16),1.5f,1.5f,ink);canvas.drawRoundRect(new RectF(8,8,21,21),1.5f,1.5f,ink);break;
            case DETAIL: canvas.drawCircle(10,10,6,ink);line(canvas,15,15,21,21);line(canvas,7,10,13,10);line(canvas,10,7,10,13);break;
            case CROP:
                line(canvas,7,3,7,17,21,17); line(canvas,3,7,17,7,17,21); break;
            case ROTATE:
                canvas.drawArc(new RectF(3,3,21,21),45,300,false,ink);
                line(canvas,16,10,21,10,21,5); line(canvas,12,7,17,12,12,17,7,12,12,7); break;
            case STRAIGHTEN:
                canvas.save(); canvas.rotate(-12,12,12);
                canvas.drawRoundRect(new RectF(3,8,21,16),1,1,ink);
                line(canvas,7,8,7,11); line(canvas,12,8,12,13); line(canvas,17,8,17,11);
                canvas.restore(); line(canvas,5,21,19,21); break;
            case PERSPECTIVE:
                line(canvas,7,4,17,4,21,20,3,20,7,4);
                line(canvas,12,7,12,17);line(canvas,7,12,17,12);break;
            case RECIPE:
                canvas.drawRoundRect(new RectF(5,3,19,21),2,2,ink);
                line(canvas,8,9,16,9); canvas.drawCircle(11,9,1.5f,ink);
                line(canvas,8,15,16,15); canvas.drawCircle(14,15,1.5f,ink); break;
            case SAVE:
                line(canvas,3,3,17,3,21,7,21,21,3,21,3,3);
                line(canvas,7,3,7,9,16,9,16,3); line(canvas,7,21,7,14,17,14,17,21); break;
            case UNDO: circularHistory(canvas,false);break;
            case REDO: circularHistory(canvas,true);break;
            case COMPARE: canvas.drawRect(3,5,21,19,ink);line(canvas,12,2,12,22);break;
            case MORE: for(int y:new int[]{5,12,19})canvas.drawCircle(12,y,1,ink);break;
            case MORE_HORIZONTAL: for(int x:new int[]{5,12,19})canvas.drawCircle(x,12,1,ink);break;
            case BRIGHTNESS: case EXPOSURE:
                canvas.drawCircle(12,12,5,ink);for(int i=0;i<8;i++){double a=i*Math.PI/4;line(canvas,12+(float)Math.cos(a)*8,12+(float)Math.sin(a)*8,12+(float)Math.cos(a)*10,12+(float)Math.sin(a)*10);}if(kind==Kind.EXPOSURE){line(canvas,10,12,14,12);line(canvas,12,10,12,14);}break;
            case CONTRAST: case WHITES: case BLACKS:
                canvas.drawCircle(12,12,9,ink);canvas.save();canvas.clipRect(kind==Kind.BLACKS?3:12,3,kind==Kind.BLACKS?12:21,21);ink.setStyle(Paint.Style.FILL);canvas.drawCircle(12,12,8,ink);ink.setStyle(Paint.Style.STROKE);canvas.restore();break;
            case HIGHLIGHTS: case SHADOWS:
                canvas.drawCircle(12,12,8,ink);for(int y=8;y<=16;y+=4)line(canvas,kind==Kind.HIGHLIGHTS?12:6,y,kind==Kind.HIGHLIGHTS?18:12,y);line(canvas,12,4,12,20);break;
            case TEMPERATURE: canvas.drawRoundRect(new RectF(9,3,15,17),3,3,ink);canvas.drawCircle(12,18,4,ink);line(canvas,12,7,12,18);break;
            case TINT: {Path drop=new Path();drop.moveTo(12,2);drop.cubicTo(10,7,4,11,5,16);drop.cubicTo(6,24,19,24,19,16);drop.cubicTo(19,11,14,6,12,2);canvas.drawPath(drop,ink);break;}
            case SATURATION: canvas.drawCircle(9,10,6,ink);canvas.drawCircle(15,10,6,ink);canvas.drawCircle(12,16,6,ink);break;
            case VIBRANCE: line(canvas,12,3,21,20,3,20,12,3);canvas.drawCircle(12,14,3,ink);break;
            case CLARITY: canvas.drawRect(4,4,20,20,ink);line(canvas,8,8,16,8,16,16,8,16,8,8);break;
            case SHARPENING: line(canvas,12,3,21,21,3,21,12,3);line(canvas,12,9,12,16);break;
            case CLOSE: line(canvas,6,6,18,18);line(canvas,18,6,6,18);break;
            case GRID: canvas.drawRoundRect(new RectF(3,3,10,10),1,1,ink);canvas.drawRoundRect(new RectF(14,3,21,10),1,1,ink);canvas.drawRoundRect(new RectF(3,14,10,21),1,1,ink);canvas.drawRoundRect(new RectF(14,14,21,21),1,1,ink);break;
            case SEARCH: canvas.drawCircle(10,10,6,ink);line(canvas,15,15,21,21);break;
            case EXPAND:
                line(canvas,8,3,3,3,3,8); line(canvas,16,3,21,3,21,8);
                line(canvas,3,16,3,21,8,21); line(canvas,16,21,21,21,21,16); break;
            case PERSON:
                canvas.drawCircle(12,7.5f,4,ink);
                canvas.drawArc(new RectF(4,13,20,27),180,180,false,ink); line(canvas,4,20,20,20); break;
            case PRESETS:
                canvas.drawRoundRect(new RectF(3,3,21,21),2,2,ink);
                canvas.drawCircle(8,8,1.6f,ink); line(canvas,4,18,10,12,14,16,17,12,21,17); break;
            case ALBUM:
                canvas.drawRoundRect(new RectF(6,6,22,22),2,2,ink);
                line(canvas,3,17,2,17,2,2,17,2,17,3); line(canvas,7,18,12,13,16,17,19,14,22,18); break;
            case CAMERA:
                line(canvas,3,7,7,7,9,4,15,4,17,7,21,7,21,21,3,21,3,7);
                canvas.drawCircle(12,13,4,ink); break;
            case FILE: line(canvas,5,2,14,2,20,8,20,22,5,22,5,2); line(canvas,14,2,14,8,20,8); break;
            case DOWNLOAD: line(canvas,12,3,12,16); line(canvas,7,11,12,16,17,11); line(canvas,4,16,4,21,20,21,20,16); break;
            case DELETE:
                line(canvas,4,6,20,6); line(canvas,9,6,9,3,15,3,15,6);
                line(canvas,6,6,7,21,17,21,18,6); line(canvas,10,10,10,17); line(canvas,14,10,14,17); break;
            case STAR: star(canvas, false); break;
            case STAR_FILLED: star(canvas, true); break;
            case RECEIPTS:
                canvas.drawRoundRect(new RectF(3,3,21,21),3,3,ink);
                canvas.drawPoint(7,8,ink); canvas.drawPoint(7,12,ink); canvas.drawPoint(7,16,ink);
                line(canvas,11,8,17,8); line(canvas,11,12,17,12); line(canvas,11,16,15,16); break;
            case BACK: line(canvas,14,4,6,12,14,20); line(canvas,6,12,22,12); break;
            case HELP:
                canvas.drawCircle(12,12,10,ink); canvas.drawArc(new RectF(8,6,16,14),190,210,false,ink);
                line(canvas,12,13,12,15); canvas.drawPoint(12,18,ink); break;
            case CHECK: line(canvas,4,12,9,17,21,5); break;
            case WIFI:
                canvas.drawArc(new RectF(1,4,23,22),210,120,false,ink);
                canvas.drawArc(new RectF(5,9,19,21),215,110,false,ink); canvas.drawCircle(12,19,1,ink); break;
            case ADJUST:
                line(canvas,3,6,21,6); line(canvas,3,12,21,12); line(canvas,3,18,21,18);
                canvas.drawCircle(8,6,2,ink); canvas.drawCircle(16,12,2,ink); canvas.drawCircle(9,18,2,ink); break;
            case REFRESH:
                drawRefresh(canvas,ink);break;
            case SETTINGS:
                gear(canvas); canvas.drawCircle(12,12,3.2f,ink); break;
            case PLUS: line(canvas,12,5,12,19); line(canvas,5,12,19,12); break;
            case USB:
                line(canvas,12,21,12,3); line(canvas,9,6,12,3,15,6);
                line(canvas,12,16,7,12,7,8); line(canvas,12,12,17,9,17,6);
                canvas.drawCircle(7,6.5f,1.5f,ink); canvas.drawRect(15.5f,3,18.5f,6,ink);
                canvas.drawCircle(12,21,1.2f,ink); break;
            case CHEVRON: line(canvas,9,5,16,12,9,19); break;
            case CHEVRON_DOWN: line(canvas,4,8,12,16,20,8); break;
            case INFO:
                canvas.drawCircle(12,12,9,ink); canvas.drawPoint(12,7,ink); line(canvas,12,11,12,17); break;
            case LINK:
                canvas.save(); canvas.rotate(-45,12,12);
                canvas.drawArc(new RectF(8,2,16,14),180,270,false,ink);
                canvas.drawArc(new RectF(8,10,16,22),0,270,false,ink);
                line(canvas,12,8,12,16); canvas.restore(); break;
        }
        canvas.restoreToCount(save);
    }
    private void line(Canvas canvas,float... xy) {
        Path path=new Path(); path.moveTo(xy[0],xy[1]); for(int i=2;i<xy.length;i+=2) path.lineTo(xy[i],xy[i+1]); canvas.drawPath(path,ink);
    }
    private void star(Canvas canvas, boolean filled) {
        Path path = new Path();
        for (int vertex = 0; vertex < 10; vertex++) {
            double angle = Math.toRadians(-90 + vertex * 36);
            float radius = vertex % 2 == 0 ? 10 : 4.5f;
            float x = 12 + (float) Math.cos(angle) * radius;
            float y = 12 + (float) Math.sin(angle) * radius;
            if (vertex == 0) path.moveTo(x,y); else path.lineTo(x,y);
        }
        path.close();
        Paint.Style previous = ink.getStyle();
        if (filled) ink.setStyle(Paint.Style.FILL);
        canvas.drawPath(path,ink);
        ink.setStyle(previous);
    }
    private void gear(Canvas canvas) {
        Path path = new Path();
        // Four vertices per tooth retain a quiet, mechanical outline at 24 dp.
        for (int tooth = 0; tooth < 8; tooth++) {
            for (int vertex = 0; vertex < 4; vertex++) {
                double angle = Math.toRadians(-101.25 + tooth * 45 + vertex * 11.25);
                float radius = vertex < 2 ? 10 : 8;
                float x = 12 + (float) Math.cos(angle) * radius;
                float y = 12 + (float) Math.sin(angle) * radius;
                if (tooth == 0 && vertex == 0) path.moveTo(x,y); else path.lineTo(x,y);
            }
        }
        path.close(); canvas.drawPath(path,ink);
    }
    /** Shared by primary and secondary photo tools; the head joins the circular arc continuously. */
    static void drawRefresh(Canvas canvas,Paint stroke){
        canvas.drawArc(new RectF(3.5f,3.5f,20.5f,20.5f),20,280,false,stroke);
        Path head=new Path();head.moveTo(16.25f,4.64f);head.lineTo(20.5f,9);head.moveTo(20.5f,3.5f);head.lineTo(20.5f,9);head.lineTo(15,9);canvas.drawPath(head,stroke);
    }
    /** Equal radii and a connected tangent arrowhead; redo is the exact horizontal mirror. */
    private void circularHistory(Canvas canvas,boolean redo){
        int saved=canvas.save();if(redo)canvas.scale(-1,1,12,12);
        canvas.drawArc(new RectF(3.5f,3.5f,20.5f,20.5f),225,300,false,ink);
        line(canvas,5.99f,1.89f,5.99f,5.99f,10.09f,5.99f);
        canvas.restoreToCount(saved);
    }
    @Override public int getIntrinsicWidth() { return size; }
    @Override public int getIntrinsicHeight() { return size; }
    @Override public void setAlpha(int alpha) { ink.setAlpha(alpha); invalidateSelf(); }
    @Override public void setColorFilter(ColorFilter filter) { ink.setColorFilter(filter); invalidateSelf(); }
    @Override public int getOpacity() { return PixelFormat.TRANSLUCENT; }
}
