package cc.huevia.shared;

/** Exact three-pass 7x7 clamped blur from original EditorGlassDrawable.sample. */
public final class SharedAtmosphere {
    private SharedAtmosphere(){}
    public static int[] blur(int[] source,int width,int height){
        if(source==null||width<1||height<1||width>64||height>64||source.length!=width*height)throw new IllegalArgumentException("编辑背景样本尺寸无效。");
        int[] pixels=source.clone(),out=new int[source.length];
        for(int pass=0;pass<3;pass++){
            for(int y=0;y<height;y++)for(int x=0;x<width;x++){
                int red=0,green=0,blue=0,count=0;
                for(int dy=-3;dy<=3;dy++)for(int dx=-3;dx<=3;dx++){
                    int sx=Math.max(0,Math.min(width-1,x+dx)),sy=Math.max(0,Math.min(height-1,y+dy)),pixel=pixels[sy*width+sx];
                    red+=(pixel>>16)&255;green+=(pixel>>8)&255;blue+=pixel&255;count++;
                }
                out[y*width+x]=0xff000000|(red/count<<16)|(green/count<<8)|blue/count;
            }
            int[] old=pixels;pixels=out;out=old;
        }
        return pixels;
    }
}
