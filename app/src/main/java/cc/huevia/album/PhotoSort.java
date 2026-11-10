package cc.huevia.album;

import java.util.Objects;

/** Source-independent date semantics; unknown dates remain last in both directions. */
public final class PhotoSort {
    public static final PhotoSort DEFAULT = new PhotoSort(false, false);
    public final boolean added, oldest;
    public PhotoSort(boolean added, boolean oldest) { this.added = added; this.oldest = oldest; }
    public long date(long taken, long addedAt) { long value=added?addedAt:taken>0&&taken<=253402300799999L?taken:addedAt;return value>0&&value<=253402300799999L?value:0; }
    public int compare(long takenA,long addedA,String idA,long takenB,long addedB,String idB) {
        long a=date(takenA,addedA),b=date(takenB,addedB);
        int order=a<=0||b<=0?(a<=0?(b<=0?0:1):-1):(oldest?Long.compare(a,b):Long.compare(b,a));
        return order!=0?order:idA.compareTo(idB);
    }
    public PhotoSort withBasis(boolean value) { return new PhotoSort(value,oldest); }
    public PhotoSort withDirection(boolean value) { return new PhotoSort(added,value); }
    public String token() { return (added?"added":"taken")+"-"+(oldest?"oldest":"newest"); }
    public String label() { return (added?"添加时间":"拍摄时间")+"，"+(oldest?"旧到新":"新到旧"); }
    public static PhotoSort parse(String token) {
        if("added-oldest".equals(token))return new PhotoSort(true,true);
        if("added-newest".equals(token))return new PhotoSort(true,false);
        if("taken-oldest".equals(token))return new PhotoSort(false,true);
        return DEFAULT;
    }
    @Override public boolean equals(Object other) { return other instanceof PhotoSort&&added==((PhotoSort)other).added&&oldest==((PhotoSort)other).oldest; }
    @Override public int hashCode() { return Objects.hash(added,oldest); }
}
