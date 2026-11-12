package cc.huevia.album;

import java.io.File;
import java.io.IOException;

/** Narrow bridge to the preserved package-private completed-JPEG model. */
public final class SharedProjectPhoto {
    private SharedProjectPhoto(){}
    public static DownloadedPhoto completed(File file,String filename)throws IOException {
        if(file==null||filename==null||filename.isEmpty())throw new IOException("项目照片记录无效。");
        PhotoPreviewCache.validateJpeg(file,file.length());
        return new DownloadedPhoto(file,filename);
    }
}
