package cc.huevia.ncp;

import java.io.IOException;
import java.io.InterruptedIOException;
import java.util.ArrayList;
import java.util.function.BooleanSupplier;
import java.util.function.DoubleConsumer;

/** Face-local colour, edge-preserving texture and donor healing with bounded row storage. */
public final class PortraitPreviewFilter {
    private static final long MAX_WORKING_BYTES = 64L * 1024 * 1024;
    private static final int MAX_HEAL_PIXELS = 4 * 1024 * 1024;
    private PortraitPreviewFilter() { }

    public static void apply(SpatialPreviewFilter.Pixels pixels, PhotoPortrait portrait,
            BooleanSupplier cancel, DoubleConsumer progress) throws IOException {
        if (pixels == null) throw new IllegalArgumentException("人像编辑照片无效。");
        apply(pixels, portrait, pixels.exifOrientation(), cancel, progress);
    }

    /** The explicit orientation is used by the local-edit wrapper's frozen source orientation. */
    public static void apply(SpatialPreviewFilter.Pixels pixels, PhotoPortrait portrait, int exif,
            BooleanSupplier cancel, DoubleConsumer progress) throws IOException {
        if (pixels == null || portrait == null || exif < 1 || exif > 8) throw new IllegalArgumentException("人像编辑照片无效。");
        int width = pixels.width(), height = pixels.height();
        if (width < 1 || height < 1 || width > 65535 || height > 65535) throw new IllegalArgumentException("人像照片尺寸无效。");
        check(cancel); report(progress, 0);
        if (portrait.isNeutral()) { report(progress, 1); return; }
        PhotoPortrait colours = portrait.bodyShape.isNeutral()?portrait:portrait.withBodyShape(PhotoBodyShape.NONE);
        if (!colours.isNeutral()) applyColour(pixels, colours, exif, cancel, progress == null ? null : v -> progress.accept(v*.6));
        if (!portrait.bodyShape.isNeutral()) PhotoBodyWarp.apply(pixels, portrait.bodyShape, exif, cancel, progress == null ? null : v -> progress.accept(.6+.4*v));
        check(cancel); report(progress, 1);
    }
    private static void applyColour(SpatialPreviewFilter.Pixels pixels, PhotoPortrait portrait, int exif, BooleanSupplier cancel, DoubleConsumer progress) throws IOException {
        GlobalTone global = portrait.globalTone.isNeutral() || portrait.globalSkinMask == null ? null : compileGlobal(pixels,portrait,exif,cancel);
        int operations = 0;
        for (PhotoPortrait.Face face : portrait.faces()) if (active(face)) operations++;
        if (global != null) operations++;
        int skinStrength=Math.max(portrait.skinSmoothing,portrait.retouch.get(PortraitRetouch.Parameter.NATURAL)*30/100);
        boolean smoothing = skinStrength > 0 && portrait.globalSkinMask != null;
        boolean retouch=portrait.retouch.hasSkinEffect();for(PhotoPortrait.Face f:portrait.faces())if(f.enabled&&f.retouch.hasFaceEffect())retouch=true;
        if(retouch)operations++;
        if (smoothing) operations++;
        for (PhotoPortrait.Heal heal : portrait.heals()) if (active(heal)) operations++;
        int done = 0;
        for (PhotoPortrait.Face face : portrait.faces()) if (active(face)) {
            final int operation = done++; final int total = operations;
            face(pixels, face, exif, cancel, progress == null ? null : v -> progress.accept((operation + v) / total));
        }
        if (global != null) {
            final int operation = done++; final int total = operations;
            global(pixels,global,exif,cancel,progress == null ? null : v -> progress.accept((operation + v) / total));
        }
        if (smoothing) {
            final int operation = done++; final int total = operations;
            SkinSmoothingFilter.apply(pixels,portrait.globalSkinMask,skinStrength,portrait.retouch.get(PortraitRetouch.Parameter.TEXTURE),exif,cancel,
                    progress == null ? null : v -> progress.accept((operation + v) / total));
        }
        if(retouch){final int operation=done++;final int total=operations;PortraitRetouchFilter.apply(pixels,portrait,exif,cancel,progress==null?null:v->progress.accept((operation+v)/total));}
        for (PhotoPortrait.Heal heal : portrait.heals()) if (active(heal)) {
            final int operation = done++; final int total = operations;
            heal(pixels, heal, exif, cancel, progress == null ? null : v -> progress.accept((operation + v) / total));
        }
        check(cancel); report(progress, 1);
    }
    private static boolean active(PhotoPortrait.Face face) { return face.enabled && (!face.settings.isNeutral() || !face.tone.isNeutral()); }

    /** Compile once for both the editor's mask overlay and the full-resolution processor. */
    public static Mask mask(PhotoPortrait.Face face, int orientedWidth, int orientedHeight) {
        if (face == null || orientedWidth < 1 || orientedHeight < 1 || orientedWidth > 65535 || orientedHeight > 65535)
            throw new IllegalArgumentException("人像蒙版尺寸无效。");
        return new Mask(face, orientedWidth, orientedHeight);
    }
    public static double maskWeight(PhotoPortrait.Face face, int argb, double nx, double ny, int orientedWidth, int orientedHeight) {
        return mask(face, orientedWidth, orientedHeight).weight(argb, nx, ny);
    }
    /** Geometry-only feature protection: one outside features, zero on eyes/brows/lips/nostrils. */
    public static double featureProtection(PhotoPortrait.Face face,double nx,double ny,int width,int height) {
        if(width<1||height<1||width>65535||height>65535)throw new IllegalArgumentException("人像蒙版尺寸无效。");
        if(face==null||!Double.isFinite(nx)||!Double.isFinite(ny)||nx<0||nx>1||ny<0||ny>1)return 1;
        double angle=Math.toRadians(face.roll),cos=Math.cos(angle),sin=Math.sin(angle),dx=(nx-face.cx)*width,dy=(ny-face.cy)*height;
        double u=(cos*dx+sin*dy)/(face.rx*width),v=(-sin*dx+cos*dy)/(face.ry*height);
        return face.landmarks==null?Mask.featureProtection(u,v):meshRegion(face.landmarks).protection(u*.95,v*1.35);
    }

    /** A global mask never needs a face selection. Faces, when known, protect only their features. */
    private static final class GlobalMask {
        final PhotoPortrait.BodySkinMask skin;
        final GlobalFeature[] features;
        GlobalMask(PhotoPortrait portrait,int width,int height) {
            skin=portrait.globalSkinMask;ArrayList<GlobalFeature> known=new ArrayList<>();
            for(PhotoPortrait.Face face:portrait.faces())if(face.landmarks!=null)known.add(new GlobalFeature(face,width,height));
            features=known.toArray(new GlobalFeature[0]);
        }
        double weight(double nx,double ny) {
            double value=skin.weight(nx,ny);if(value<=0)return 0;
            // A baked feature limit remains unchanged on a second pass; it is not squared.
            for(GlobalFeature feature:features){value=Math.min(value,feature.protection(nx,ny));if(value<=0)return 0;}
            return value;
        }
    }
    private static final class GlobalFeature {
        final double cx,cy,rx,ry,cos,sin,left,top,right,bottom;
        final int width,height;
        final MeshRegion mesh;
        GlobalFeature(PhotoPortrait.Face face,int width,int height) {
            this.width=width;this.height=height;cx=face.cx;cy=face.cy;rx=face.rx*width;ry=face.ry*height;
            double angle=Math.toRadians(face.roll);cos=Math.cos(angle);sin=Math.sin(angle);
            mesh=meshRegion(face.landmarks);
            double l=Double.POSITIVE_INFINITY,t=l,r=Double.NEGATIVE_INFINITY,b=r;
            double[] xs={mesh.protectionLeft/.95,mesh.protectionRight/.95};
            double[] ys={mesh.protectionTop/1.35,mesh.protectionBottom/1.35};
            for(double u:xs)for(double v:ys){double x=u*rx,y=v*ry,nx=cx+(cos*x-sin*y)/width,ny=cy+(sin*x+cos*y)/height;l=Math.min(l,nx);r=Math.max(r,nx);t=Math.min(t,ny);b=Math.max(b,ny);}
            left=l;right=r;top=t;bottom=b;
        }
        double protection(double nx,double ny) {
            if(nx<left||nx>right||ny<top||ny>bottom)return 1;
            double dx=(nx-cx)*width,dy=(ny-cy)*height,u=(cos*dx+sin*dy)/rx,v=(-sin*dx+cos*dy)/ry;
            return mesh.protection(u*.95,v*1.35);
        }
    }
    private static final class GlobalTone {
        final GlobalMask mask;final SkinTone.Transform transform;
        GlobalTone(GlobalMask mask,SkinTone.Transform transform){this.mask=mask;this.transform=transform;}
    }
    /** Freeze a bounded, canonical-oriented sample before any portrait pixels are changed. */
    private static GlobalTone compileGlobal(SpatialPreviewFilter.Pixels pixels,PhotoPortrait portrait,int exif,BooleanSupplier cancel)throws IOException {
        int width=pixels.width(),height=pixels.height(),ow=exif>=5?height:width,oh=exif>=5?width:height;
        GlobalMask mask=new GlobalMask(portrait,ow,oh);
        int columns=Math.min(256,ow),rows=Math.min(256,oh),rawColumns=exif>=5?rows:columns,rawRows=exif>=5?columns:rows;
        int[] sampled=new int[columns*rows],row=new int[width];
        for(int y=0;y<rawRows;y++) {
            check(cancel);int loaded=-1;
            for(int x=0;x<rawColumns;x++) {
                int gx=orientedPixelX(x,y,rawColumns,rawRows,exif),gy=orientedPixelY(x,y,rawColumns,rawRows,exif);
                int ox=((2*gx+1)*ow)/(2*columns),oy=((2*gy+1)*oh)/(2*rows),ry=rawPixelY(ox,oy,width,height,exif);
                if(ry!=loaded){pixels.read(row,ry,1);loaded=ry;}
                sampled[gy*columns+gx]=row[rawPixelX(ox,oy,width,height,exif)];
            }
        }
        double red=0,green=0,blue=0,weights=0;
        for(int y=0;y<rows;y++) {
            check(cancel);int oy=((2*y+1)*oh)/(2*rows);
            for(int x=0;x<columns;x++) {
                int value=sampled[y*columns+x];if((value>>>24)==0)continue;
                int ox=((2*x+1)*ow)/(2*columns);
                double weight=mask.weight((ox+.5)/ow,(oy+.5)/oh)*((value>>>24)/255.0);
                if(weight<=0)continue;
                red+=((value>>>16)&255)*weight;green+=((value>>>8)&255)*weight;blue+=(value&255)*weight;weights+=weight;
            }
        }
        if(weights<=0)return null;
        return new GlobalTone(mask,new SkinTone.Transform(portrait.globalTone,channel(red/weights),channel(green/weights),channel(blue/weights)));
    }
    private static void global(SpatialPreviewFilter.Pixels pixels,GlobalTone tone,int exif,BooleanSupplier cancel,DoubleConsumer progress)throws IOException {
        int width=pixels.width(),height=pixels.height();int[] row=new int[width];
        for(int y=0;y<height;y++) {
            check(cancel);pixels.read(row,y,1);
            for(int x=0;x<width;x++) {
                if((x&255)==0)check(cancel);int value=row[x];if((value>>>24)==0)continue;
                double nx=orientedX((x+.5)/width,(y+.5)/height,exif),ny=orientedY((x+.5)/width,(y+.5)/height,exif);
                double weight=tone.mask.weight(nx,ny);if(weight>0)row[x]=tone.transform.apply(value,weight);
            }
            check(cancel);pixels.write(row,y,1);report(progress,(y+1.0)/height);
        }
    }

    private static final int[] FACE_OVAL={10,338,297,332,284,251,389,356,454,323,361,288,397,365,379,378,400,377,152,148,176,149,150,136,172,58,132,93,234,127,162,21,54,103,67,109};
    private static final int[] LEFT_EYE={33,7,163,144,145,153,154,155,133,173,157,158,159,160,161,246};
    private static final int[] RIGHT_EYE={263,249,390,373,374,380,381,382,362,398,384,385,386,387,388,466};
    private static final int[] LEFT_BROW={46,53,52,65,55,107,66,105,63,70};
    private static final int[] RIGHT_BROW={276,283,282,295,285,336,296,334,293,300};
    private static final int[] LIPS={61,146,91,181,84,17,314,405,321,375,291,409,270,269,267,0,37,39,40,185};
    // Values contain only copied polygon/raster data, never a reference back to the weak key.
    private static final java.util.Map<PhotoPortrait.Landmarks,MeshRegion> MESH_REGIONS=new java.util.WeakHashMap<>();
    private static MeshRegion meshRegion(PhotoPortrait.Landmarks landmarks){
        synchronized(MESH_REGIONS){MeshRegion ready=MESH_REGIONS.get(landmarks);if(ready==null){ready=new MeshRegion(landmarks);MESH_REGIONS.put(landmarks,ready);}return ready;}
    }
    /** Selection hit-testing uses the detected outline, including the visible forehead. */
    public static boolean faceContains(PhotoPortrait.Face face,double nx,double ny,int width,int height){
        if(face==null||!Double.isFinite(nx)||!Double.isFinite(ny)||nx<0||nx>1||ny<0||ny>1||width<1||height<1)return false;
        double angle=Math.toRadians(face.roll),dx=(nx-face.cx)*width,dy=(ny-face.cy)*height;
        double u=(Math.cos(angle)*dx+Math.sin(angle)*dy)/(face.rx*width),v=(-Math.sin(angle)*dx+Math.cos(angle)*dy)/(face.ry*height);
        if(face.skinMask!=null&&face.skinMask.weight(u,v)>.06)return true;
        if(face.landmarks==null)return Math.hypot(u,v)<1.15;
        Polygon outline=new Polygon(face.landmarks,FACE_OVAL);double x=u*.95,y=v*1.35;
        return outline.contains(x,y)||outline.distance(x,y)<.04;
    }

    /** A face-specific skin sample determines chroma acceptance independently of skin brightness. */
    public static final class Mask {
        private final PhotoPortrait.Face face;
        private final int width, height;
        private final double cos, sin, rx, ry, skinR, skinB, tolerance;
        private final StrokeMask[] strokes;
        private final MeshRegion mesh;
        private final double left, top, right, bottom;
        private Mask(PhotoPortrait.Face face, int width, int height) {
            this.face = face; this.width = width; this.height = height;
            double radians = Math.toRadians(face.roll); cos = Math.cos(radians); sin = Math.sin(radians);
            rx = face.rx * width; ry = face.ry * height;
            mesh = face.landmarks == null ? null : meshRegion(face.landmarks);
            double sum = Math.max(1, face.skinR + face.skinG + face.skinB);
            skinR = face.skinR / sum; skinB = face.skinB / sum;
            double luminance = (.2126 * face.skinR + .7152 * face.skinG + .0722 * face.skinB) / 255;
            tolerance = .055 + .025 * (1 - luminance);
            double extentX = Math.hypot(rx * cos, ry * sin) / width, extentY = Math.hypot(rx * sin, ry * cos) / height;
            double l = face.cx - extentX, r = face.cx + extentX, t = face.cy - extentY, b = face.cy + extentY;
            if(mesh!=null){
                l=Double.POSITIVE_INFINITY;r=Double.NEGATIVE_INFINITY;t=Double.POSITIVE_INFINITY;b=Double.NEGATIVE_INFINITY;
                for(int point:FACE_OVAL){double x=face.landmarks.x(point)*rx,y=face.landmarks.y(point)*ry;
                    double nx=face.cx+(cos*x-sin*y)/width,ny=face.cy+(sin*x+cos*y)/height;
                    l=Math.min(l,nx);r=Math.max(r,nx);t=Math.min(t,ny);b=Math.max(b,ny);}
            }
            if(face.skinMask!=null){
                l=Double.POSITIVE_INFINITY;r=Double.NEGATIVE_INFINITY;t=Double.POSITIVE_INFINITY;b=Double.NEGATIVE_INFINITY;
                double[] xs={face.skinMask.left,face.skinMask.right},ys={face.skinMask.top,face.skinMask.bottom};
                for(double u:xs)for(double v:ys){double x=u*rx,y=v*ry,nx=face.cx+(cos*x-sin*y)/width,ny=face.cy+(sin*x+cos*y)/height;
                    l=Math.min(l,nx);r=Math.max(r,nx);t=Math.min(t,ny);b=Math.max(b,ny);}
            }
            ArrayList<StrokeMask> compiled = new ArrayList<>();
            for (PhotoPortrait.Stroke stroke : face.strokes) {
                StrokeMask value = new StrokeMask(stroke, width, height); compiled.add(value);
                if (!stroke.erase) { l = Math.min(l, value.left); r = Math.max(r, value.right); t = Math.min(t, value.top); b = Math.max(b, value.bottom); }
            }
            strokes = compiled.toArray(new StrokeMask[0]);
            left = clamp(l); right = clamp(r); top = clamp(t); bottom = clamp(b);
        }
        public double weight(int argb, double nx, double ny) {
            if (!face.enabled || (argb >>> 24) == 0 || !Double.isFinite(nx) || !Double.isFinite(ny) || nx < 0 || nx > 1 || ny < 0 || ny > 1) return 0;
            double u = localX(nx, ny), v = localY(nx, ny);
            return manual(automatic(argb,u,v),nx,ny);
        }
        /** Facial feature tools keep their anatomical mask and honor authored erase/restore strokes. */
        public double authoredFeatureCoverage(double nx,double ny) { return face.enabled?manual(1,nx,ny):0; }
        /** Only the target-colour operation may extend to this person's body skin. */
        public double toneWeight(int argb, double nx, double ny) {
            if (!face.enabled || (argb >>> 24) == 0 || !Double.isFinite(nx) || !Double.isFinite(ny) || nx < 0 || nx > 1 || ny < 0 || ny > 1) return 0;
            double u = localX(nx, ny), v = localY(nx, ny), automatic = automatic(argb,u,v);
            if (face.tone.body && face.bodySkinMask != null) {
                double body = face.bodySkinMask.weight(nx,ny);
                if (body > 0) {
                    double protection = mesh == null ? featureProtection(u,v) : mesh.protection(u*.95,v*1.35);
                    automatic = Math.max(automatic, body * protection);
                }
            }
            return manual(automatic,nx,ny);
        }
        private double automatic(int argb,double u,double v) {
            double automatic;
            if(face.skinMask!=null){
                // Semantic face-skin coverage owns the hairline and occlusion boundary.
                // The mesh protects features only; its shorter forehead oval must not clip it.
                double skin = face.skinMask.weight(u,v);
                automatic=skin<=0?0:skin*(mesh==null?featureProtection(u,v):mesh.protection(u*.95,v*1.35));
            }else{
                double geometry=mesh==null?falloff(Math.hypot(u,v),.28)*protection(u,v):mesh.sample(mesh.coverage,u*.95,v*1.35);
                automatic=geometry*skinWeight(argb);
            }
            return automatic;
        }
        private double manual(double automatic,double nx,double ny) {
            for (StrokeMask stroke : strokes) {
                double amount = stroke.weight(nx, ny);
                automatic = stroke.erase ? automatic * (1 - amount) : automatic + (1 - automatic) * amount;
            }
            return clamp(automatic);
        }
        private double localX(double nx, double ny) { double dx = (nx - face.cx) * width, dy = (ny - face.cy) * height; return (cos * dx + sin * dy) / rx; }
        private double localY(double nx, double ny) { double dx = (nx - face.cx) * width, dy = (ny - face.cy) * height; return (-sin * dx + cos * dy) / ry; }
        private double skinWeight(int argb) {
            double r = (argb >>> 16) & 255, g = (argb >>> 8) & 255, b = argb & 255, sum = r + g + b;
            if (sum < 12) return 0;
            double distance = Math.hypot(r / sum - skinR, b / sum - skinB) / tolerance;
            return 1 - smooth(.5, 2, distance);
        }
        private static double protection(double u, double v) {
            return featureProtection(u,v)*smooth(-.91,-.72,v);
        }
        private static double featureProtection(double u,double v){
            if (u < -.82 || u > .82 || v < -.67 || v > .72) return 1;
            double eyes = Math.max(ellipse(u, v, -.526, -.407, .24, .135), ellipse(u, v, .526, -.407, .24, .135));
            double eyebrows = Math.max(ellipse(u, v, -.526, -.57, .29, .09), ellipse(u, v, .526, -.57, .29, .09));
            double mouth = ellipse(u, v, 0, .55, .42, .16), nostrils = ellipse(u, v, 0, .20, .18, .08);
            return 1-Math.max(Math.max(eyes,eyebrows),Math.max(mouth,nostrils));
        }
        private double underEyes(double u,double v){
            return mesh==null?Math.max(ellipse(u,v,-.526,-.19,.29,.18),ellipse(u,v,.526,-.19,.29,.18)):mesh.sample(mesh.underEyes,u*.95,v*1.35);
        }
    }

    /** Geometry-only, resolution-independent raster compiled once per immutable landmark set. */
    private static final class MeshRegion {
        private static final int GRID=192,STRIDE=GRID+1;
        final float[] coverage=new float[STRIDE*STRIDE],underEyes=new float[STRIDE*STRIDE];
        final double left,top,right,bottom;
        final Polygon leftEye,rightEye,leftBrow,rightBrow,lips;
        final double noseLeftX,noseLeftY,noseRightX,noseRightY;
        final double protectionLeft,protectionTop,protectionRight,protectionBottom;
        MeshRegion(PhotoPortrait.Landmarks points){
            Polygon outline=new Polygon(points,FACE_OVAL);leftEye=new Polygon(points,LEFT_EYE);rightEye=new Polygon(points,RIGHT_EYE);
            leftBrow=new Polygon(points,LEFT_BROW);rightBrow=new Polygon(points,RIGHT_BROW);lips=new Polygon(points,LIPS);
            noseLeftX=points.x(98)*.95;noseLeftY=points.y(98)*1.35;noseRightX=points.x(327)*.95;noseRightY=points.y(327)*1.35;
            double pl=Math.min(noseLeftX,noseRightX)-.065,pr=Math.max(noseLeftX,noseRightX)+.065;
            double pt=Math.min(noseLeftY,noseRightY)-.045,pb=Math.max(noseLeftY,noseRightY)+.045;
            for(Polygon feature:new Polygon[]{leftEye,rightEye,leftBrow,rightBrow,lips}){
                pl=Math.min(pl,feature.left-.035);pr=Math.max(pr,feature.right+.035);pt=Math.min(pt,feature.top-.035);pb=Math.max(pb,feature.bottom+.035);
            }
            protectionLeft=pl;protectionRight=pr;protectionTop=pt;protectionBottom=pb;
            left=outline.left;top=outline.top;right=Math.max(left+.001,outline.right);bottom=Math.max(top+.001,outline.bottom);
            for(int y=0;y<=GRID;y++)for(int x=0;x<=GRID;x++){
                double px=left+(right-left)*x/GRID,py=top+(bottom-top)*y/GRID;
                if(!outline.contains(px,py))continue;
                double edge=smooth(0,.07,outline.distance(px,py));
                coverage[y*STRIDE+x]=(float)(edge*protection(px,py));
                underEyes[y*STRIDE+x]=(float)Math.max(eyeShadow(px,py,leftEye),eyeShadow(px,py,rightEye));
            }
        }
        double protection(double x,double y){
            if(x<protectionLeft||x>protectionRight||y<protectionTop||y>protectionBottom)return 1;
            double excluded=Math.max(Math.max(leftEye.exclusion(x,y,.035),rightEye.exclusion(x,y,.035)),Math.max(leftBrow.exclusion(x,y,.025),rightBrow.exclusion(x,y,.025)));
            excluded=Math.max(excluded,lips.exclusion(x,y,.025));
            double nose=Math.max(ellipse(x,y,noseLeftX,noseLeftY,.065,.045),ellipse(x,y,noseRightX,noseRightY,.065,.045));
            return 1-Math.max(excluded,nose);
        }
        private static double eyeShadow(double x,double y,Polygon eye){
            double width=Math.max(.04,eye.right-eye.left),height=Math.max(.02,eye.bottom-eye.top);
            return ellipse(x,y,(eye.left+eye.right)/2,eye.bottom+height*.8,width*.7,width*.32);
        }
        double sample(float[] values,double x,double y){
            if(x<left||x>right||y<top||y>bottom)return 0;
            double gx=(x-left)/(right-left)*GRID,gy=(y-top)/(bottom-top)*GRID;
            int ix=Math.min(GRID-1,(int)gx),iy=Math.min(GRID-1,(int)gy);double tx=gx-ix,ty=gy-iy;
            int i=iy*STRIDE+ix;return (values[i]*(1-tx)+values[i+1]*tx)*(1-ty)+(values[i+STRIDE]*(1-tx)+values[i+STRIDE+1]*tx)*ty;
        }
    }
    private static final class Polygon {
        final double[] x,y;final double left,top,right,bottom;
        Polygon(PhotoPortrait.Landmarks points,int[] indices){
            x=new double[indices.length];y=new double[indices.length];double l=Double.POSITIVE_INFINITY,t=l,r=Double.NEGATIVE_INFINITY,b=r;
            for(int i=0;i<indices.length;i++){x[i]=points.x(indices[i])*.95;y[i]=points.y(indices[i])*1.35;l=Math.min(l,x[i]);r=Math.max(r,x[i]);t=Math.min(t,y[i]);b=Math.max(b,y[i]);}
            left=l;right=r;top=t;bottom=b;
        }
        boolean contains(double px,double py){
            boolean inside=false;
            for(int i=0,j=x.length-1;i<x.length;j=i++)if((y[i]>py)!=(y[j]>py)&&px<(x[j]-x[i])*(py-y[i])/(y[j]-y[i])+x[i])inside=!inside;
            return inside;
        }
        double distance(double px,double py){
            double best=Double.POSITIVE_INFINITY;
            for(int i=0,j=x.length-1;i<x.length;j=i++){
                double dx=x[i]-x[j],dy=y[i]-y[j],den=dx*dx+dy*dy;
                double t=den==0?0:Math.max(0,Math.min(1,((px-x[j])*dx+(py-y[j])*dy)/den));
                double ex=px-x[j]-t*dx,ey=py-y[j]-t*dy;best=Math.min(best,ex*ex+ey*ey);
            }
            return Math.sqrt(best);
        }
        double exclusion(double px,double py,double margin){
            if(px<left-margin||px>right+margin||py<top-margin||py>bottom+margin)return 0;
            return contains(px,py)?1:1-smooth(0,margin,distance(px,py));
        }
    }

    private static final class StrokeMask {
        private static final int GRID = 16;
        final double[] ax, ay, vx, vy, length;
        final int[] starts, segments;
        final double radius, feather, left, top, right, bottom;
        final boolean erase;
        final int width, height;
        StrokeMask(PhotoPortrait.Stroke stroke, int width, int height) {
            double[] points = stroke.points(); radius = stroke.radius * Math.min(width, height); feather = stroke.feather; erase = stroke.erase; this.width = width; this.height = height;
            double l = 1, r = 0, t = 1, b = 0;
            for (int i = 0; i < points.length; i += 2) { l = Math.min(l, points[i]); r = Math.max(r, points[i]); t = Math.min(t, points[i + 1]); b = Math.max(b, points[i + 1]); }
            left = l - radius / width; right = r + radius / width; top = t - radius / height; bottom = b + radius / height;
            // Each cell stores just segments whose radius-expanded bounds intersect it.
            // The final degenerate segment is retained to match the exhaustive polyline exactly.
            int count = points.length / 2;
            ax = new double[count]; ay = new double[count]; vx = new double[count]; vy = new double[count]; length = new double[count];
            int[] cellLeft = new int[count], cellRight = new int[count], cellTop = new int[count], cellBottom = new int[count], counts = new int[GRID * GRID];
            for (int i = 0; i < count; i++) {
                int j = i * 2, k = Math.min(j + 2, points.length - 2);
                ax[i] = points[j] * width; ay[i] = points[j + 1] * height;
                vx[i] = points[k] * width - ax[i]; vy[i] = points[k + 1] * height - ay[i]; length[i] = vx[i] * vx[i] + vy[i] * vy[i];
                cellLeft[i] = cell((Math.min(ax[i], ax[i] + vx[i]) - radius) / width);
                cellRight[i] = cell((Math.max(ax[i], ax[i] + vx[i]) + radius) / width);
                cellTop[i] = cell((Math.min(ay[i], ay[i] + vy[i]) - radius) / height);
                cellBottom[i] = cell((Math.max(ay[i], ay[i] + vy[i]) + radius) / height);
                for (int y = cellTop[i]; y <= cellBottom[i]; y++) for (int x = cellLeft[i]; x <= cellRight[i]; x++) counts[y * GRID + x]++;
            }
            starts = new int[GRID * GRID + 1];
            for (int i = 0; i < counts.length; i++) starts[i + 1] = starts[i] + counts[i];
            segments = new int[starts[GRID * GRID]];
            int[] cursor = starts.clone();
            for (int i = 0; i < count; i++) for (int y = cellTop[i]; y <= cellBottom[i]; y++) for (int x = cellLeft[i]; x <= cellRight[i]; x++) {
                int destination = y * GRID + x; segments[cursor[destination]++] = i;
            }
        }
        double weight(double nx, double ny) {
            if (nx < left || nx > right || ny < top || ny > bottom) return 0;
            double x = nx * width, y = ny * height, distance = Double.POSITIVE_INFINITY;
            int cell = cell(ny) * GRID + cell(nx);
            for (int index = starts[cell]; index < starts[cell + 1]; index++) {
                int i = segments[index];
                double projection = length[i] == 0 ? 0 : clamp(((x - ax[i]) * vx[i] + (y - ay[i]) * vy[i]) / length[i]);
                double dx = x - ax[i] - projection * vx[i], dy = y - ay[i] - projection * vy[i];
                distance = Math.min(distance, dx * dx + dy * dy);
            }
            return falloff(Math.sqrt(distance) / radius, feather);
        }
        private static int cell(double value) { return Math.max(0, Math.min(GRID - 1, (int) Math.floor(value * GRID))); }
    }

    private static void face(SpatialPreviewFilter.Pixels pixels, PhotoPortrait.Face face, int exif,
            BooleanSupplier cancel, DoubleConsumer progress) throws IOException {
        int width = pixels.width(), height = pixels.height(), ow = exif >= 5 ? height : width, oh = exif >= 5 ? width : height;
        Mask mask = mask(face, ow, oh);
        boolean toneActive = !face.tone.isNeutral(), settingsActive = !face.settings.isNeutral();
        boolean body = toneActive && face.tone.body && face.bodySkinMask != null;
        int[] bounds = rawBounds(body ? 0 : mask.left, body ? 0 : mask.top, body ? 1 : mask.right, body ? 1 : mask.bottom, width, height, exif);
        int left = bounds[0], top = bounds[1], right = bounds[2], bottom = bounds[3];
        if (left >= right || top >= bottom) { report(progress, 1); return; }
        PhotoPortrait.Settings settings = face.settings;
        SkinTone.Transform tone = toneActive ? new SkinTone.Transform(face.tone,face.skinR,face.skinG,face.skinB) : null;
        int radius = settings.smoothing == 0 ? 0 : Math.max(1, Math.min(10, (int) Math.round(Math.min(ow, oh) * .003)));
        int slots = Math.min(height, radius * 2 + 1);
        if ((4L * slots + 4) * width > MAX_WORKING_BYTES) throw new IOException("人像处理行缓存超出内存上限。");
        int[][] ring = new int[slots][width]; int[] output = new int[width];
        int half = Math.max(1, radius / 2);
        int[] taps = {-radius, -half, 0, half, radius};
        int loaded = Math.max(0, top - radius) - 1;
        double smoothing = settings.smoothing / 100.0 * .85, texture = settings.texture / 100.0;
        for (int y = top; y < bottom; y++) {
            check(cancel);
            int through = Math.min(height - 1, y + radius);
            while (loaded < through) { check(cancel); loaded++; pixels.read(ring[loaded % slots], loaded, 1); }
            int[] original = ring[y % slots]; System.arraycopy(original, 0, output, 0, width);
            for (int x = left; x < right; x++) {
                if ((x & 255) == 0) check(cancel);
                int value = original[x]; if ((value >>> 24) == 0) continue;
                double nx = orientedX((x + .5) / width, (y + .5) / height, exif), ny = orientedY((x + .5) / width, (y + .5) / height, exif);
                double amount = settingsActive ? mask.weight(value, nx, ny) : 0;
                double toneAmount = toneActive ? mask.toneWeight(value,nx,ny) : 0;
                if (amount <= 0 && toneAmount <= 0) continue;
                int adjusted = value;
                if (amount > 0) {
                double r = (value >>> 16) & 255, g = (value >>> 8) & 255, b = value & 255;
                if (radius > 0) {
                    double red = 0, green = 0, blue = 0, weights = 0;
                    double sigma = 18 + settings.smoothing * .20, denominator = 3 * sigma * sigma;
                    for (int dy : taps) {
                        int yy = Math.max(0, Math.min(height - 1, y + dy)); int[] row = ring[yy % slots];
                        for (int dx : taps) {
                            int xx = Math.max(0, Math.min(width - 1, x + dx)), neighbor = row[xx];
                            double alpha = (neighbor >>> 24) / 255.0; if (alpha == 0) continue;
                            double nr = (neighbor >>> 16) & 255, ng = (neighbor >>> 8) & 255, nb = neighbor & 255;
                            double dr = nr - r, dg = ng - g, db = nb - b;
                            double spatial = 1 / (1 + (dx * dx + dy * dy) / (double) (radius * radius + 1));
                            double weight = spatial * alpha / (1 + (dr * dr + dg * dg + db * db) / denominator);
                            red += nr * weight; green += ng * weight; blue += nb * weight; weights += weight;
                        }
                    }
                    if (weights > 0) {
                        double strength = smoothing * (1 - .80 * texture);
                        r += (red / weights - r) * strength; g += (green / weights - g) * strength; b += (blue / weights - b) * strength;
                    }
                }
                double u = mask.localX(nx, ny), v = mask.localY(nx, ny);
                double light = settings.light / 100.0 * (.035 + .13 * Math.exp(-1.5 * u * u - 1.2 * (v + .15) * (v + .15)));
                double underEyes = mask.underEyes(u,v);
                double sourceY = (.2126 * r + .7152 * g + .0722 * b) / 255;
                double referenceY = (.2126 * face.skinR + .7152 * face.skinG + .0722 * face.skinB) / 255;
                double shadow = settings.shadows / 100.0 * .25 * underEyes * clamp((referenceY + .10 - sourceY) / .28);
                double lift = settings.brightness / 100.0 * .22 + light + shadow;
                r = liftChannel(r / 255, lift) + settings.warmth / 100.0 * .055 + settings.redness / 100.0 * .055;
                g = liftChannel(g / 255, lift) + settings.warmth / 100.0 * .008 - settings.redness / 100.0 * .018;
                b = liftChannel(b / 255, lift) - settings.warmth / 100.0 * .065 - settings.redness / 100.0 * .006;
                adjusted = mix(value, channel(r * 255), channel(g * 255), channel(b * 255), amount);
                }
                output[x] = toneAmount > 0 ? tone.apply(adjusted,toneAmount) : adjusted;
            }
            check(cancel); pixels.write(output, y, 1); report(progress, (y - top + 1.0) / (bottom - top));
        }
    }

    /** Snapshot donors before writing, then match the surrounding target colour rather than cloning a hard patch. */
    private static void heal(SpatialPreviewFilter.Pixels pixels, PhotoPortrait.Heal heal, int exif,
            BooleanSupplier cancel, DoubleConsumer progress) throws IOException {
        int width = pixels.width(), height = pixels.height();
        int ow = exif >= 5 ? height : width, oh = exif >= 5 ? width : height;
        double canonicalDX = (heal.sx - heal.tx) * ow, canonicalDY = (heal.sy - heal.ty) * oh;
        double radius = heal.radius * Math.min(width, height);
        double tx = rawX(heal.tx, heal.ty, exif) * width - .5, ty = rawY(heal.tx, heal.ty, exif) * height - .5;
        double sx = rawX(heal.sx, heal.sy, exif) * width - .5, sy = rawY(heal.sx, heal.sy, exif) * height - .5;
        double dx = sx - tx, dy = sy - ty;
        int left = Math.max(0, (int) Math.floor(tx - radius)), right = Math.min(width - 1, (int) Math.ceil(tx + radius));
        int top = Math.max(0, (int) Math.floor(ty - radius)), bottom = Math.min(height - 1, (int) Math.ceil(ty + radius));
        int sl = Math.max(0, (int) Math.floor(left + dx)), sr = Math.min(width - 1, (int) Math.ceil(right + dx));
        int st = Math.max(0, (int) Math.floor(top + dy)), sb = Math.min(height - 1, (int) Math.ceil(bottom + dy));
        if (left > right || top > bottom || sl > sr || st > sb) { report(progress, 1); return; }
        int patchWidth = sr - sl + 1, patchHeight = sb - st + 1;
        long count = (long) patchWidth * patchHeight;
        if (count > MAX_HEAL_PIXELS || count * 4 + width * 4L > MAX_WORKING_BYTES) throw new IOException("修复范围过大，请缩小修复画笔。");
        int[] patch = new int[(int) count], row = new int[width];
        for (int y = st; y <= sb; y++) { check(cancel); pixels.read(row, y, 1); System.arraycopy(row, sl, patch, (y - st) * patchWidth, patchWidth); }
        double sourceR = 0, sourceG = 0, sourceB = 0, targetR = 0, targetG = 0, targetB = 0, weights = 0;
        for (int y = top; y <= bottom; y++) {
            check(cancel); pixels.read(row, y, 1);
            for (int x = left; x <= right; x++) {
                if ((x & 255) == 0) check(cancel);
                double distance = Math.hypot(x - tx, y - ty) / radius; if (distance < .65 || distance > 1) continue;
                long donor = donor(x, y, width, height, exif, canonicalDX, canonicalDY); if (donor < 0) continue;
                int xx = (int) donor, yy = (int) (donor >>> 32);
                if (xx < sl || xx > sr || yy < st || yy > sb) continue;
                int source = patch[(yy - st) * patchWidth + xx - sl], target = row[x];
                double weight = Math.min(source >>> 24, target >>> 24) / 255.0; if (weight <= 0) continue;
                sourceR += ((source >>> 16) & 255) * weight; sourceG += ((source >>> 8) & 255) * weight; sourceB += (source & 255) * weight;
                targetR += ((target >>> 16) & 255) * weight; targetG += ((target >>> 8) & 255) * weight; targetB += (target & 255) * weight; weights += weight;
            }
        }
        double correctionR = weights == 0 ? 0 : limit((targetR - sourceR) / weights, -64, 64);
        double correctionG = weights == 0 ? 0 : limit((targetG - sourceG) / weights, -64, 64);
        double correctionB = weights == 0 ? 0 : limit((targetB - sourceB) / weights, -64, 64);
        for (int y = top; y <= bottom; y++) {
            check(cancel); pixels.read(row, y, 1);
            for (int x = left; x <= right; x++) {
                if ((x & 255) == 0) check(cancel);
                double amount = falloff(Math.hypot(x - tx, y - ty) / radius, heal.feather); if (amount <= 0) continue;
                long donor = donor(x, y, width, height, exif, canonicalDX, canonicalDY); if (donor < 0) continue;
                int xx = (int) donor, yy = (int) (donor >>> 32); if (xx < sl || xx > sr || yy < st || yy > sb) continue;
                int source = patch[(yy - st) * patchWidth + xx - sl], target = row[x];
                if ((source >>> 24) == 0 || (target >>> 24) == 0) continue;
                amount *= (source >>> 24) / 255.0;
                row[x] = mix(target, channel(((source >>> 16) & 255) + correctionR), channel(((source >>> 8) & 255) + correctionG), channel((source & 255) + correctionB), amount);
            }
            check(cancel); pixels.write(row, y, 1); report(progress, (y - top + 1.0) / (bottom - top));
        }
    }

    private static int[] rawBounds(double left, double top, double right, double bottom, int width, int height, int exif) {
        double x0 = rawX(left, top, exif), x1 = rawX(right, bottom, exif), y0 = rawY(left, top, exif), y1 = rawY(right, bottom, exif);
        return new int[]{Math.max(0, (int) Math.floor(Math.min(x0, x1) * width)), Math.max(0, (int) Math.floor(Math.min(y0, y1) * height)),
                Math.min(width, (int) Math.ceil(Math.max(x0, x1) * width)), Math.min(height, (int) Math.ceil(Math.max(y0, y1) * height))};
    }
    private static boolean active(PhotoPortrait.Heal heal) { return heal.enabled && (heal.sx != heal.tx || heal.sy != heal.ty); }
    /** Resolve half-pixel donor ties in the canonical oriented frame, including reflected EXIF. */
    private static long donor(int x, int y, int width, int height, int exif, double dx, double dy) {
        int ow = exif >= 5 ? height : width, oh = exif >= 5 ? width : height;
        double px = orientedPixelX(x, y, width, height, exif) + dx, py = orientedPixelY(x, y, width, height, exif) + dy;
        if (px < -.5 || py < -.5 || px > ow - .5 || py > oh - .5) return -1;
        int ox = Math.max(0, Math.min(ow - 1, (int) Math.round(px))), oy = Math.max(0, Math.min(oh - 1, (int) Math.round(py)));
        int ix = rawPixelX(ox, oy, width, height, exif), iy = rawPixelY(ox, oy, width, height, exif);
        return ((long) iy << 32) | ix;
    }
    private static int mix(int original, int r, int g, int b, double amount) {
        return (original & 0xff000000) | channel(((original >>> 16) & 255) + (r - ((original >>> 16) & 255)) * amount) << 16
                | channel(((original >>> 8) & 255) + (g - ((original >>> 8) & 255)) * amount) << 8 | channel((original & 255) + (b - (original & 255)) * amount);
    }
    private static double liftChannel(double value, double amount) { return amount >= 0 ? value + amount * (1 - value) : value * (1 + amount); }
    private static double ellipse(double x, double y, double cx, double cy, double rx, double ry) { return 1 - smooth(.55, 1, Math.hypot((x - cx) / rx, (y - cy) / ry)); }
    private static double falloff(double distance, double feather) { if (distance >= 1) return 0; if (distance <= 1 - feather || feather == 0) return 1; return 1 - smooth(1 - feather, 1, distance); }
    private static double smooth(double a, double b, double value) { double x = clamp((value - a) / (b - a)); return x * x * (3 - 2 * x); }
    private static double clamp(double value) { return limit(value, 0, 1); }
    private static double limit(double value, double lo, double hi) { return Math.max(lo, Math.min(hi, value)); }
    private static int channel(double value) { return (int) Math.round(limit(value, 0, 255)); }
    private static void report(DoubleConsumer progress, double value) { if (progress != null) progress.accept(value); }
    private static void check(BooleanSupplier cancel) throws InterruptedIOException { if (Thread.currentThread().isInterrupted() || cancel != null && cancel.getAsBoolean()) throw new InterruptedIOException("人像编辑处理已取消。"); }
    private static double orientedX(double x, double y, int exif) { switch (exif) { case 2: case 3: return 1 - x; case 5: case 8: return y; case 6: case 7: return 1 - y; default: return x; } }
    private static double orientedY(double x, double y, int exif) { switch (exif) { case 3: case 4: return 1 - y; case 5: case 6: return x; case 7: case 8: return 1 - x; default: return y; } }
    private static double rawX(double x, double y, int exif) { switch (exif) { case 2: case 3: return 1 - x; case 5: case 6: return y; case 7: case 8: return 1 - y; default: return x; } }
    private static double rawY(double x, double y, int exif) { switch (exif) { case 3: case 4: return 1 - y; case 5: case 8: return x; case 6: case 7: return 1 - x; default: return y; } }
    private static int orientedPixelX(int x, int y, int w, int h, int exif) { switch (exif) { case 2: case 3: return w - 1 - x; case 5: case 8: return y; case 6: case 7: return h - 1 - y; default: return x; } }
    private static int orientedPixelY(int x, int y, int w, int h, int exif) { switch (exif) { case 3: case 4: return h - 1 - y; case 5: case 6: return x; case 7: case 8: return w - 1 - x; default: return y; } }
    private static int rawPixelX(int x, int y, int w, int h, int exif) { switch (exif) { case 2: case 3: return w - 1 - x; case 5: case 6: return y; case 7: case 8: return w - 1 - y; default: return x; } }
    private static int rawPixelY(int x, int y, int w, int h, int exif) { switch (exif) { case 3: case 4: return h - 1 - y; case 5: case 8: return x; case 6: case 7: return h - 1 - x; default: return y; } }
}
