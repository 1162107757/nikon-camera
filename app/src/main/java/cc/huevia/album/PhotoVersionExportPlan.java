package cc.huevia.album;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

/** Immutable saved-version choices. No fallback to another version, draft lookup or file writes. */
public final class PhotoVersionExportPlan {
    public static final class Entry {
        public final String id, groupId, label, outputFilename;
        public final DownloadedPhoto photo;
        public final boolean current, multiple;
        private Entry(String groupId, String label, DownloadedPhoto photo, boolean current, boolean multiple, String outputFilename) {
            this.groupId=groupId; this.id=groupId+":"+photo.file().getAbsolutePath(); this.label=label;
            this.photo=photo; this.current=current; this.multiple=multiple; this.outputFilename=outputFilename;
        }
    }
    public final List<Entry> entries;
    public final int photoCount;
    private PhotoVersionExportPlan(List<Entry> values, int photoCount) { entries=Collections.unmodifiableList(values); this.photoCount=photoCount; }
    public static PhotoVersionExportPlan create(List<PhotoLibraryCatalog.PhotoGroup> groups, List<DownloadedPhoto> selected) {
        List<Entry> result=new ArrayList<>(); Set<String> seen=new HashSet<>(), names=new HashSet<>();
        for(DownloadedPhoto current:selected) {
            if(current==null)throw new IllegalArgumentException("selected photo");
            PhotoLibraryCatalog.PhotoGroup group=PhotoLibraryCatalog.groupFor(groups,current);
            String id=group==null?current.file().getAbsolutePath():group.id;
            if(!seen.add(id))continue;
            if(group==null) { result.add(new Entry(id,"已保存版本",current,true,false,uniqueFilename(current.filename(),"",names))); continue; }
            PhotoLibraryCatalog.Version chosen=group.findByFile(current.file());
            if(chosen==null)throw new IllegalArgumentException("所选版本不在照片组中。");
            boolean multiple=group.versions.size()>1;
            String base=group.original==null?current.filename():group.original.filename();
            Set<String> labels=new HashSet<>();
            for(PhotoLibraryCatalog.Version version:group.versions) {
                String label=version.label(), unique=label; int suffix=2;
                while(!labels.add(unique))unique=label+" "+suffix++;
                result.add(new Entry(id,unique,version.photo,version.photo.file().equals(chosen.photo.file()),multiple,uniqueFilename(base,multiple?unique:"",names)));
            }
        }
        return new PhotoVersionExportPlan(result,seen.size());
    }
    public List<Entry> current() { List<Entry> result=new ArrayList<>(); for(Entry entry:entries)if(entry.current)result.add(entry); return Collections.unmodifiableList(result); }
    public Set<String> currentIds() { Set<String> ids=new LinkedHashSet<>(); for(Entry entry:current())ids.add(entry.id); return ids; }
    public boolean hasVersions() { return entries.size()>photoCount; }
    /** Keep both recognizable parts within the publisher's 32-character stem budget. */
    public static String uniqueFilename(String filename,String version,Set<String> used) {
        int dot=filename.lastIndexOf('.'); String base=part(dot>0?filename.substring(0,dot):filename,version.isEmpty()?26:14);
        String label=version.isEmpty()?"":"_"+part(version,12); String stem=base+label,candidate=stem;int n=2;
        while(!used.add(candidate.toLowerCase(Locale.ROOT)))candidate=stem+"_"+n++;
        return candidate+".jpg";
    }
    private static String part(String text,int max) {
        String value=text.replaceAll("[^\\p{L}\\p{N}_-]","_").replaceAll("_+","_");
        if(value.isEmpty())value="照片";
        return value.substring(0,Math.min(value.length(),max));
    }
}
