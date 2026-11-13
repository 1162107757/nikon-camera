package cc.huevia.album;

import cc.huevia.ptp.PtpObjectInfo;
import java.io.IOException;
import java.util.*;

/** Public migration facade for the original conservative, package-private pairing algorithm. */
public final class SharedRawPairing {
    private SharedRawPairing(){}
    public static long uniqueHandle(PtpObjectInfo jpeg,long[] handles,PtpObjectInfo[] raw,boolean trusted,int count)throws IOException {
        if(handles.length!=raw.length)throw new IOException("RAW 库存记录不完整。");
        List<PhotoItem> items=new ArrayList<>();for(int i=0;i<handles.length;i++)items.add(new PhotoItem("shared-pairing",handles[i],raw[i]));
        return RawPhotoPairing.unique(jpeg,items,trusted,count).handle();
    }
}
