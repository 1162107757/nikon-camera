package cc.huevia.ncp;

import java.io.IOException;
import java.util.Arrays;

public final class SkinBodyRegionsTest {
    private static int checks;
    public static void main(String[] args)throws Exception{
        int n=24;byte[] c=new byte[n*n];
        // Two people with clothes connecting face to hands; an unseeded person stays out.
        rect(c,n,2,2,6,5,3);rect(c,n,2,5,6,18,4);rect(c,n,1,9,2,13,2);
        rect(c,n,14,2,18,5,3);rect(c,n,14,5,18,18,4);rect(c,n,18,9,20,13,2);
        rect(c,n,9,19,12,23,2);
        int[] owner=SkinBodyRegions.owners(c,n,new double[]{4.5/n,3.5/n,16.5/n,3.5/n},()->false);
        check("first hand attached through clothing",owner[10*n+1]==0);
        check("second hand belongs to second person",owner[10*n+19]==1);
        check("unseeded skin not assigned",owner[21*n+10]==-1);
        check("background unassigned",owner[10*n+10]==-1);
        // A foreground bridge still partitions rather than assigning both people to face one.
        rect(c,n,6,12,14,14,4);owner=SkinBodyRegions.owners(c,n,new double[]{4.5/n,3.5/n,16.5/n,3.5/n},()->false);
        check("touching people keep first hand",owner[10*n+1]==0);
        check("touching people keep second hand",owner[10*n+19]==1);
        check("bridge is partitioned",owner[12*n+7]!=owner[12*n+12]);
        int[] reversed=SkinBodyRegions.owners(c,n,new double[]{16.5/n,3.5/n,4.5/n,3.5/n},()->false);
        check("person order does not swap actual subject",reversed[10*n+19]==0&&reversed[10*n+1]==1);
        int[] empty=SkinBodyRegions.owners(c,n,new double[0],()->false);check("no face means no changes",Arrays.stream(empty).allMatch(x->x==-1));
        byte[] blank=new byte[n*n];check("empty categories safe",Arrays.stream(SkinBodyRegions.owners(blank,n,new double[]{.5,.5},()->false)).allMatch(x->x==-1));
        try{SkinBodyRegions.owners(c,n,new double[]{.5,.5},()->true);throw new AssertionError("cancel not honored");}catch(IOException expected){checks++;}
        try{SkinBodyRegions.owners(c,n,new double[]{Double.NaN,.5},()->false);throw new AssertionError("invalid seed");}catch(IllegalArgumentException expected){checks++;}
        try{SkinBodyRegions.owners(c,n,new double[]{.5},()->false);throw new AssertionError("odd seed");}catch(IllegalArgumentException expected){checks++;}
        blank[0]=6;try{SkinBodyRegions.owners(blank,n,new double[0],()->false);throw new AssertionError("invalid category");}catch(IllegalArgumentException expected){checks++;}
        System.out.println("SkinBodyRegionsTest: "+checks+" checks passed");
    }
    private static void rect(byte[] c,int n,int l,int t,int r,int b,int category){for(int y=t;y<b;y++)for(int x=l;x<r;x++)c[y*n+x]=(byte)category;}
    private static void check(String name,boolean pass){checks++;if(!pass)throw new AssertionError(name);}
}
