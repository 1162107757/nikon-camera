package cc.huevia.ui;

import android.content.Context;
import android.content.SharedPreferences;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.UUID;
import org.json.JSONArray;
import org.json.JSONObject;

/** Personal colour cards only; independent of photo drafts and portrait undo history. */
final class SkinToneSwatches {
    static final String PREFERENCES = "portrait_skin_swatches", KEY = "swatches_v1";
    static final int LIMIT = 12;
    private final SharedPreferences preferences;

    static final class Entry {
        final String id, name;
        final int colorRGB;
        Entry(String id, String name, int colorRGB) { this.id=id;this.name=name;this.colorRGB=colorRGB&0xffffff; }
    }

    SkinToneSwatches(Context context) {
        preferences=context.getApplicationContext().getSharedPreferences(PREFERENCES,Context.MODE_PRIVATE);
    }

    List<Entry> load() {
        ArrayList<Entry> entries=new ArrayList<>();
        try {
            JSONArray array=new JSONArray(preferences.getString(KEY,"[]"));
            for(int i=0;i<array.length()&&entries.size()<LIMIT;i++) {
                JSONObject item=array.getJSONObject(i);
                String id=item.getString("id"),name=item.getString("name").trim();
                if(!id.isEmpty()&&!name.isEmpty()&&name.length()<=12) entries.add(new Entry(id,name,item.getInt("rgb")));
            }
        } catch(Exception ignored) { return Collections.emptyList(); }
        return Collections.unmodifiableList(entries);
    }

    void save(String name,int colorRGB) throws IOException {
        name=name==null?"":name.trim();
        if(name.isEmpty()||name.length()>12) throw new IllegalArgumentException("请为色卡填写 1–12 个字的名称。");
        List<Entry> entries=load();
        if(entries.size()>=LIMIT) throw new IllegalArgumentException("个人色卡已满（12 张），请先删除一张再保存。");
        for(Entry entry:entries) {
            if(entry.colorRGB==(colorRGB&0xffffff)) throw new IllegalArgumentException("这个颜色已经保存在个人色卡中。");
            if(entry.name.equalsIgnoreCase(name)) throw new IllegalArgumentException("已有同名色卡，请换一个名称。");
        }
        ArrayList<Entry> next=new ArrayList<>(entries);
        next.add(new Entry(UUID.randomUUID().toString(),name,colorRGB));
        store(next);
    }

    void remove(String id) throws IOException {
        ArrayList<Entry> next=new ArrayList<>();
        for(Entry entry:load())if(!entry.id.equals(id))next.add(entry);
        store(next);
    }

    private void store(List<Entry> entries) throws IOException {
        JSONArray array=new JSONArray();
        try {
            for(Entry entry:entries)array.put(new JSONObject().put("id",entry.id).put("name",entry.name).put("rgb",entry.colorRGB));
            if(!preferences.edit().putString(KEY,array.toString()).commit()) throw new IOException("色卡未能保存，请重试。");
        } catch(IOException failure) { throw failure; }
        catch(Exception failure) { throw new IOException("色卡未能保存，请重试。",failure); }
    }
}
