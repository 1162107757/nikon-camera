package cc.huevia.album;

/** Named quick-save ceilings. Resolve independently per composition and never upscale. */
public enum PhotoExportQuality {
    COMPACT("轻量",1280,80), BALANCED("均衡",2048,85), HIGH("高清",4096,92), ORIGINAL("原画",0,95);
    public final String label;
    public final int longEdge,quality;
    PhotoExportQuality(String label,int longEdge,int quality){this.label=label;this.longEdge=longEdge;this.quality=quality;}
    public PhotoExportSpec spec(){return this==ORIGINAL?PhotoExportSpec.full():PhotoExportSpec.custom(longEdge,quality);}
    public String detail(){return (this==ORIGINAL?"原尺寸":"长边 ≤ "+longEdge+" px")+" · JPEG "+quality;}
}
