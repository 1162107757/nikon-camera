package cc.huevia.ncp;

import java.io.IOException;

/** Dispatch by the binary record signature, never by an untrusted filename. */
public final class PresetPreviewProfiles {
    private PresetPreviewProfiles() {}

    /** Invalidate success and failure thumbnail caches when any preview approximation changes. */
    public static final String MODEL_VERSION = NcpPreviewProfile.MODEL_VERSION + ":" + Np3PreviewProfile.MODEL_VERSION
            + ":" + Np3MonochromePreviewProfile.MODEL_VERSION + ":" + Np3MonochromePreviewProfile.STANDARD_MODEL_VERSION
            + ":" + NcpMonochromePreviewProfile.MODEL_VERSION + ":" + Np2PreviewProfile.MODEL_VERSION
            + ":" + Np3RichTonePortraitProfile.MODEL_VERSION;

    public static PresetPreviewProfile fromPreset(byte[] bytes) throws IOException {
        if (Np2File.isNp2(bytes)) return Np2PreviewProfile.fromNp2(bytes);
        if (bytes != null && bytes.length >= 8 && bytes[0] == 'N' && bytes[1] == 'C'
                && bytes[2] == 'P' && bytes[3] == 0 && bytes[4] == 0 && bytes[5] == 0
                && bytes[6] == 1 && bytes[7] == 0) {
            // Routing hint only. The selected parser revalidates every record and
            // active control; unsupported/malformed data never falls through.
            int base = np3Base(bytes);
            if (base == Np3RichTonePortraitProfile.BASE_CODE) return Np3RichTonePortraitProfile.fromNp3(bytes);
            if (base == 0x064d || base == 0x0655) return Np3MonochromePreviewProfile.fromNp3(bytes);
            return Np3PreviewProfile.fromNp3(bytes);
        }
        if(legacyMonochrome(bytes))return NcpMonochromePreviewProfile.fromNcp(bytes);
        return NcpPreviewProfile.fromNcp(bytes);
    }

    /** Routing hint only; the selected legacy reader revalidates the complete bounded envelope. */
    private static boolean legacyMonochrome(byte[] bytes){
        return bytes!=null&&bytes.length>=38&&bytes[0]=='N'&&bytes[1]=='C'&&bytes[2]=='P'&&bytes[3]==0
                &&bytes[4]==0&&bytes[5]==0&&bytes[6]==0&&bytes[7]==1
                &&bytes[8]==0&&bytes[9]==0&&bytes[10]==0&&bytes[11]==36
                &&bytes[12]=='0'&&bytes[13]=='1'&&bytes[14]=='0'&&bytes[15]=='0'
                &&bytes[36]==6&&(bytes[37]&255)==0x4d;
    }

    private static int np3Base(byte[] bytes) {
        int offset = 4;
        for (int index = 1; index <= 3; index++) {
            int length = index == 1 ? 4 : index == 2 ? 20 : 2;
            if (bytes.length - offset < 8 + length || bytes[offset] != 0 || bytes[offset + 1] != 0
                    || (bytes[offset + 2] & 255) != index || bytes[offset + 3] != 0
                    || bytes[offset + 4] != 0 || bytes[offset + 5] != 0 || bytes[offset + 6] != 0
                    || (bytes[offset + 7] & 255) != length) return -1;
            offset += 8;
            if (index == 3) return ((bytes[offset] & 255) << 8) | (bytes[offset + 1] & 255);
            offset += length;
        }
        return -1;
    }
}
