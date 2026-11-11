package cc.huevia.shared;

import java.util.Arrays;

/** Constant images, alpha, ownership and allocation limits are cross-runtime contracts. */
public final class AtmosphereChecks {
    private AtmosphereChecks() {}
    public static int run() {
        int[] source=new int[64*43];Arrays.fill(source,0xffd7c3ab);
        int[] blurred=SharedAtmosphere.blur(source,64,43);
        if(!Arrays.equals(source,blurred))throw new AssertionError("Flat atmosphere changed colour");
        if(source==blurred)throw new AssertionError("Atmosphere aliases caller pixels");
        blurred[0]=0;if(source[0]!=0xffd7c3ab)throw new AssertionError("Atmosphere mutates original");
        if(SharedAtmosphere.blur(new int[]{0x00aabbcc},1,1)[0]!=0xffaabbcc)throw new AssertionError("Atmosphere alpha is not opaque");
        try{SharedAtmosphere.blur(new int[65],65,1);throw new AssertionError("Oversized sample accepted");}catch(IllegalArgumentException expected){}
        try{SharedAtmosphere.blur(new int[2],1,1);throw new AssertionError("Mismatched sample accepted");}catch(IllegalArgumentException expected){}
        System.out.println("PASS 6 shared atmosphere checks; colour, alpha, ownership and bounded allocation");
        return 6;
    }
}
