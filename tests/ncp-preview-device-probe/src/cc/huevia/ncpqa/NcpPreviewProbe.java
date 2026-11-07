package cc.huevia.ncpqa;

import android.app.*;
import android.content.*;
import android.content.pm.*;
import android.graphics.*;
import android.media.ExifInterface;
import android.os.*;
import android.util.LruCache;
import android.view.*;
import android.view.accessibility.AccessibilityNodeInfo;
import android.widget.*;
import java.io.*;
import java.lang.reflect.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.BooleanSupplier;
import org.json.*;

/** Reflection-only NCP batch regression: no application profile classes are packaged here. */
public final class NcpPreviewProbe extends Instrumentation {
    private static final String OLD_122_MODEL="encoded-rgb-tone-hsv-v1:np3-0310-encoded-hsl-zones-spatial-v3:np3-0310-deep-tone-monochrome-spatial-v1:np3-0310-monochrome-spatial-v1";
    private Bundle args; private Activity activity; private ClassLoader loader;
    private Object library,renderer,panel,editor,store; private File output,fixtureRoot,draftRoot;
    private String stage="start",owner; private Throwable failure; private int screenshotCount;
    private final JSONArray checks=new JSONArray(),recipes=new JSONArray(),measurements=new JSONArray();
    private final List<File> owned=new ArrayList<>(),originals=new ArrayList<>();
    private final List<String> sourceHashes=new ArrayList<>(); private final List<Object> photos=new ArrayList<>();
    private final List<Dialog> dialogs=new ArrayList<>();
    private final Map<String,byte[]> libraryFilesBefore=new LinkedHashMap<>();
    private final Set<String> importedIds=new LinkedHashSet<>();
    private JSONObject manifest,golden; private JSONArray items;
    private final Map<String,byte[]> presetBytes=new LinkedHashMap<>();
    private final Map<String,Object> records=new LinkedHashMap<>();
    private String oldModel,newModel; private boolean fixturesRemoved;
    private String transientId,unsupportedId;private File movedFixture,movedBackup;
    private SharedPreferences templatePreferences;private String priorTemplate;private boolean hadTemplate,templateRestored;
    private interface Work {void run()throws Exception;}
    private interface Condition {boolean test()throws Exception;}
    @Override public void onCreate(Bundle value){args=value==null?new Bundle():value;start();}
    @Override public void onStart(){try{
        loader=getTargetContext().getClassLoader();
        check("owned-emulator",Build.HARDWARE.equals("ranchu")||Build.HARDWARE.equals("goldfish"));
        check("exact-installed-apk",sha(new File(getTargetContext().getApplicationInfo().sourceDir)).equals(args.getString("candidateSha256")));
        String run=args.getString("runId");check("safe-run-id",run!=null&&run.matches("[a-zA-Z0-9.-]+"));
        output=new File(getTargetContext().getExternalFilesDir(null),"ncp-preview123/"+run);output.getParentFile().mkdirs();check("new-evidence-directory",output.mkdir());
        fixtureRoot=new File(getTargetContext().getFilesDir(),"ncp-qa-"+run);check("new-fixture-directory",fixtureRoot.mkdir());
        manifest=new JSONObject(new String(asset("fixtures.json"),StandardCharsets.UTF_8));items=manifest.getJSONArray("items");
        check("original-batch-count",items.length()==149);golden=new JSONObject(new String(asset("native-vectors.json"),StandardCharsets.UTF_8));
        newModel=(String)type("cc.huevia.ncp.PresetPreviewProfiles").getField("MODEL_VERSION").get(null);
        String mono=(String)type("cc.huevia.ncp.NcpMonochromePreviewProfile").getField("MODEL_VERSION").get(null);
        check("frozen-monochrome-model-version",mono.equals(golden.getString("modelVersion")));
        check("combined-key-includes-monochrome-model",newModel.endsWith(":"+mono));oldModel=OLD_122_MODEL;check("old122-prefix-unchanged",newModel.equals(oldModel+":"+mono));
        JSONObject prior=new JSONObject(new String(asset("cache-baseline.json"),StandardCharsets.UTF_8));check("sealed122-cache-baseline",prior.getString("apkSha256").equals("a8c765ec68debe11611011bb77a890ef695b2bef38f109bdc2657a56ecb60e47")&&prior.getString("modelVersion").equals(oldModel)&&prior.getBoolean("dexStringConfirmed"));
        templatePreferences=getTargetContext().getSharedPreferences("preset-preview-template",Context.MODE_PRIVATE);hadTemplate=templatePreferences.contains("custom-sha256");priorTemplate=templatePreferences.getString("custom-sha256",null);check("built-in-template-preference-staged",templatePreferences.edit().remove("custom-sha256").commit());
        renderer=type("cc.huevia.ui.PresetPreviewRenderer").getConstructor(Context.class).newInstance(getTargetContext());
        if(args.getString("scope","full").equals("full")){allFilesAndTemplates();monochromeBrushIntegration();}else{loadRepresentativeBytes();if(fullScope())monochromeBrushIntegration();}
        activity=startActivitySync(new Intent().setClassName("cc.huevia","cc.huevia.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        until(()->(Boolean)get(activity,"ready"),"main-ready");library=get(activity,"library");panel=get(activity,"album");
        owner=(String)staticCall(type("cc.huevia.ui.PhotoFilterEditor"),"accountOwner",new Class<?>[]{Context.class},activity);
        store=type("cc.huevia.album.PhotoEditStore").getConstructor(File.class,String.class).newInstance(activity.getFilesDir(),owner);draftRoot=(File)get(store,"root");
        String mode=args.getString("mode","phone");boolean landscape=mode.equals("landscape");
        ui(()->activity.setRequestedOrientation(landscape?ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE:ActivityInfo.SCREEN_ORIENTATION_PORTRAIT));
        until(()->activity.getResources().getConfiguration().orientation==(landscape?2:1),"requested-orientation");
        check("actual-font-scale",Math.abs(activity.getResources().getConfiguration().fontScale-(mode.equals("font1.3")?1.3f:1f))<.02);
        importRepresentatives(); galleryAndPicker(); importFaultFixtures(); editorAndExports();
        for(int i=0;i<originals.size();i++)check("original-jpeg-preserved-"+i,sha(originals.get(i)).equals(sourceHashes.get(i)));
        stage="complete";
    }catch(Throwable error){failure=unwrap(error);try{capture("failure");}catch(Throwable ignored){}}
    finally{cleanup();writeReport();Bundle result=new Bundle();result.putString("summary",failure==null?"PASS "+checks.length()+" checks; "+screenshotCount+" screenshots":"FAIL "+stage+" "+failure);finish(failure==null?Activity.RESULT_OK:Activity.RESULT_CANCELED,result);}}

    private void allFilesAndTemplates()throws Exception{
        stage="all149-originals-android-template";int monoCount=0;Bitmap fullOriginal=(Bitmap)call(renderer,"originalTemplate");
        int ow=fullOriginal.getWidth(),oh=fullOriginal.getHeight();float scale=Math.min(1,320f/Math.max(ow,oh));
        Bitmap small=Bitmap.createScaledBitmap(fullOriginal,Math.round(ow*scale),Math.round(oh*scale),true);
        int w=small.getWidth(),h=small.getHeight();int[] source=pixels(small);String originalHash=pixelHash(fullOriginal);
        try{for(int i=0;i<items.length();i++){
            JSONObject item=items.getJSONObject(i);String name=item.getString("name"),path=item.getString("asset"),sha=item.getString("sha256");
            byte[] bytes=asset(path);check("original-file-sha-"+i,bytes.length==item.getInt("byteLength")&&sha(bytes).equals(sha));presetBytes.put(name,bytes);
            boolean mono=item.getBoolean("monochrome");if(mono)monoCount++;
            Object profile=profile(bytes);check("expected-profile-family-"+i,profile.getClass().getName().equals("cc.huevia.ncp."+(mono?"NcpMonochromePreviewProfile":"NcpPreviewProfile")));
            int[] before=source.clone(),expected=(int[])call(profile,"render",new Class<?>[]{int[].class,int.class,int.class},source,w,h);
            check("profile-preserves-input-"+i,Arrays.equals(before,source));
            Bitmap actual=(Bitmap)call(renderer,"render",new Class<?>[]{byte[].class,int.class},bytes,320);
            try{check("native-template-profile-exact-"+i,actual.getWidth()==w&&actual.getHeight()==h&&Arrays.equals(expected,pixels(actual)));}
            finally{actual.recycle();}
            if(mono){
                int tone=item.getInt("toning");check("monochrome-parameter-bindings-"+i,((Integer)call(profile,"filterEffect"))==item.getInt("filterEffect")&&((Integer)call(profile,"toning"))==tone&&((Integer)call(profile,"toningDensity"))==item.getInt("density"));
                check("monochrome-gray-or-toning-"+i,tone==128?allGray(expected):someTint(expected));
                verifyGolden(profile,sha,i);
                for(int strength:new int[]{0,50,100}){
                    Object effect=staticCall(type("cc.huevia.ncp.StrengthPreviewProfile"),"of",new Class<?>[]{type("cc.huevia.ncp.PresetPreviewProfile"),int.class},profile,strength);
                    int[] result=(int[])call(effect,"render",new Class<?>[]{int[].class,int.class,int.class},source,w,h);
                    boolean equal=true;for(int p=0;p<result.length;p++)if(result[p]!=mix(source[p],expected[p],strength)){equal=false;break;}
                    check("monochrome-strength-completed-effect-exact-"+i+"-"+strength,equal);
                }
            }
            recipes.put(new JSONObject().put("name",name).put("sha256",sha).put("monochrome",mono).put("modelVersion",call(profile,"modelVersion")).put("templateArgbSha256",pixelHash(expected)));
        }
        check("original-batch-130-color-19-monochrome",monoCount==19);Bitmap after=(Bitmap)call(renderer,"originalTemplate");try{check("all149-template-source-preserved",originalHash.equals(pixelHash(after)));}finally{after.recycle();}
        }finally{small.recycle();if(fullOriginal!=small)fullOriginal.recycle();}
    }
    private boolean fullScope(){return !args.getString("scope","full").equals("ui");}
    private void loadRepresentativeBytes()throws Exception{for(int i=0;i<items.length();i++){JSONObject item=items.getJSONObject(i);if(Arrays.asList(representatives()).contains(item.getString("name"))){byte[] bytes=asset(item.getString("asset"));check("short-ui-original-sha-"+i,sha(bytes).equals(item.getString("sha256")));presetBytes.put(item.getString("name"),bytes);}}check("short-ui-representatives-ready",presetBytes.size()==5);}
    private void verifyGolden(Object profile,String sha,int index)throws Exception{
        JSONObject vector=golden.getJSONObject("outputs").getJSONObject(sha);JSONArray input=golden.getJSONArray("argb"),expected=vector.getJSONArray("argb");
        check("golden-vector-count-"+index,input.length()==expected.length()&&input.length()>8);
        for(int p=0;p<input.length();p++){int source=(int)Long.parseUnsignedLong(input.getString(p),16),result=(Integer)call(profile,"applyArgb",new Class<?>[]{int.class},source),want=(int)Long.parseUnsignedLong(expected.getString(p),16);check("frozen-independent-pixel-vector-"+index+"-"+p,result==want);}
    }
    @SuppressWarnings({"unchecked","rawtypes"}) private void monochromeBrushIntegration()throws Exception{
        stage="monochrome-existing-painted-region-integration";Bitmap source=texture();try{
            int w=source.getWidth(),h=source.getHeight();int[] input=pixels(source);Object mono=profile(presetBytes.get("B&W Portrait"));
            int[] baseline=(int[])call(mono,"render",new Class<?>[]{int[].class,int.class,int.class},input,w,h);
            Class<?> ac=type("cc.huevia.ncp.PhotoAdjustments"),rc=type("cc.huevia.ncp.AdjustmentRegion"),strokeClass=type("cc.huevia.ncp.PhotoPortrait$Stroke"),lc=type("cc.huevia.ncp.PhotoLocalEdits");
            Object parameter=Enum.valueOf((Class)type("cc.huevia.ncp.PhotoAdjustments$Parameter"),"BRIGHTNESS");Object adjustments=call(ac.getField("NONE").get(null),"with",new Class<?>[]{parameter.getClass(),int.class},parameter,35);
            Object stroke=strokeClass.getConstructor(double[].class,double.class,double.class,boolean.class).newInstance(new double[]{.22,.5,.78,.5},.13,.45,false);
            Object region=staticCall(rc,"create",new Class<?>[]{String.class},"NCP QA region");region=call(region,"addStroke",new Class<?>[]{strokeClass},stroke);region=call(region,"withAdjustments",new Class<?>[]{ac},adjustments);
            Object local=call(lc.getField("NONE").get(null),"addRegion",new Class<?>[]{rc},region);Object effect=staticCall(type("cc.huevia.ncp.LocalEditsPreviewProfile"),"of",new Class<?>[]{type("cc.huevia.ncp.PresetPreviewProfile"),lc},mono,local);
            int[] rendered=(int[])call(effect,"render",new Class<?>[]{int[].class,int.class,int.class},input,w,h);Object mask=call(region,"compileBrush",new Class<?>[]{int.class,int.class},w,h);Method sampler=method(mask.getClass(),"weight",new Class<?>[]{double.class,double.class});int protectedPixels=0,errors=0,changed=0;
            for(int y=0;y<h;y++)for(int x=0;x<w;x++){int at=y*w+x;double weight=((Number)sampler.invoke(mask,(x+.5)/w,(y+.5)/h)).doubleValue();if(weight==0){protectedPixels++;if(rendered[at]!=baseline[at])errors++;}else if(rendered[at]!=baseline[at])changed++;}
            check("new-monochrome-retains-brush-zero-packed-argb",protectedPixels>10000&&errors==0);check("new-monochrome-region-brightness-changes-selected-pixels",changed>100);check("new-monochrome-brightness-stays-neutral",allGray(rendered));
            measurements.put(new JSONObject().put("case","monochrome-existing-painted-region").put("protectedPixels",protectedPixels).put("outsideDifferences",errors).put("selectedChangedPixels",changed));
        }finally{source.recycle();}
    }
    private void importRepresentatives()throws Exception{
        stage="existing-library-record-preservation";File root=(File)get(library,"root");
        for(String name:representatives()){
            byte[] bytes=presetBytes.get(name);check("representative-original-exists-"+name,bytes!=null);String id=sha(bytes);
            Object existing=call(library,"findBySha256",new Class<?>[]{String.class},id);
            for(String suffix:new String[]{".json",".ncp"}){File path=new File(root,id+suffix);if(path.isFile())libraryFilesBefore.put(path.getPath(),Files.readAllBytes(path.toPath()));}
            File marker=new File(root,"removed-"+id+".json");check("representative-not-preexisting-removed-"+name,!marker.exists());
            Object record=existing;
            if(record==null){importedIds.add(id);Object added=call(library,"importFile",new Class<?>[]{String.class,byte[].class},"NCP-QA-"+name+".NCP",bytes);record=get(added,"record");check("temporary-record-imported-"+name,(Boolean)get(added,"added"));}
            records.put(name,record);check("representative-library-original-bytes-"+name,Arrays.equals(bytes,(byte[])call(library,"readPreset",new Class<?>[]{String.class},id)));
        }
    }
    private String[] representatives(){return new String[]{"Agfa Optima","B&W Portrait","Mono-no_eff-serp1","Mono-no_eff-serp7","SHING Nostalgia"};}
    private void importFaultFixtures()throws Exception{
        stage="owned-controlled-fault-fixtures";String nonce=UUID.randomUUID().toString().replace("-","").substring(0,8);
        transientId=importFaultFixture("QAR"+nonce,false);unsupportedId=importFaultFixture("QAU"+nonce,true);
    }
    private String importFaultFixture(String name,boolean unsupported)throws Exception{
        byte[] bytes=presetBytes.get("B&W Portrait").clone();Arrays.fill(bytes,16,36,(byte)0);byte[] label=name.getBytes(StandardCharsets.US_ASCII);System.arraycopy(label,0,bytes,16,label.length);if(unsupported){bytes[46]=(byte)0x82;bytes[47]=(byte)0x81;}
        String id=sha(bytes);check("owned-fault-record-is-new-"+name,call(library,"findBySha256",new Class<?>[]{String.class},id)==null);importedIds.add(id);
        Object result=call(library,"importFile",new Class<?>[]{String.class,byte[].class},name+".NCP",bytes);check("owned-fault-record-added-"+name,(Boolean)get(result,"added"));return id;
    }
    @SuppressWarnings("unchecked") private void galleryAndPicker()throws Exception{
        stage="old-error-cache-new-model-key-no-reimport";Object previews=get(activity,"presetPreviews");String version=(String)call(previews,"versionKey"),tail=version.substring(newModel.length());
        check("template-version-uses-new-model",version.startsWith(newModel+":"));
        for(String name:new String[]{"B&W Portrait","Mono-no_eff-serp7","SHING Nostalgia"}){
            Object record=records.get(name);String id=(String)get(record,"id");File metadata=new File((File)get(library,"root"),id+".json");String metaSha=sha(metadata),dataSha=sha((byte[])call(library,"readPreset",new Class<?>[]{String.class},id));
            List<String> oldKeys=new ArrayList<>();ui(()->{for(int edge:new int[]{320,480,720,960}){String key="sim:"+id+":"+oldModel+tail+":"+edge;oldKeys.add(key);((Set<String>)get(activity,"failedImages")).add(key);((Set<String>)get(activity,"unsupportedPreviews")).add(key);((Map<String,String>)get(activity,"previewFailures")).put(key,"此预设不支持模拟 · 122旧key");}set(activity,"albumTab",false);set(activity,"settingsTab",false);set(activity,"localTab",true);call(activity,"openPreset",new Class<?>[]{Object.class,boolean.class},record,false);});
            until(()->((LruCache<?,?>)get(activity,"imageCache")).snapshot().containsKey("sim:"+id+":"+version+":960"),"gallery-new-key-ready-"+name);
            check("old-error-key-remains-isolated-"+name,((Map<?,?>)get(activity,"previewFailures")).containsKey(oldKeys.get(0)));
            check("gallery-no-reimport-record-and-bytes-"+name,metadata.isFile()&&sha(metadata).equals(metaSha)&&sha((byte[])call(library,"readPreset",new Class<?>[]{String.class},id)).equals(dataSha));
            capture("01-gallery-"+(name.equals("B&W Portrait")?"black-white":name.equals("SHING Nostalgia")?"yellow-green":"sepia"));
        }
        stage="real-native-preset-selection";Object picker=type("cc.huevia.ui.PresetSelectionPage").getConstructor(Activity.class).newInstance(activity);
        Object cb=Proxy.newProxyInstance(loader,new Class<?>[]{type("cc.huevia.ui.PresetSelectionPage$Callback")},(proxy,m,a)->null);
        ui(()->call(picker,"show",new Class<?>[]{String.class,String.class,boolean.class,BooleanSupplier.class,type("cc.huevia.ui.PresetSelectionPage$Callback")},"NCP 预览专项",get(records.get("B&W Portrait"),"id"),false,(BooleanSupplier)()->true,cb));
        until(()->get(picker,"list")!=null&&!((List<?>)get(picker,"entries")).isEmpty(),"native-picker-loaded");
        for(String name:representatives()){
            String id=(String)get(records.get(name),"id");int[] at={-1};ui(()->{List<?> entries=(List<?>)get(picker,"entries");for(int i=0;i<entries.size();i++)if(id.equals(get(get(entries.get(i),"preset"),"id")))at[0]=i;check("picker-existing-record-"+name,at[0]>=0);((ListView)get(picker,"list")).setSelection(at[0]);});
            until(()->{for(Object e:(List<?>)get(picker,"entries"))if(id.equals(get(get(e,"preset"),"id")))return get(e,"state").toString().equals("READY");return false;},"native-picker-ready-"+name);
        }
        capture("02-native-picker-ready");ui(()->call(picker,"close"));
    }

    private void editorAndExports()throws Exception{
        stage="two-photo-local-filter-editor";Bitmap bitmap=texture();try{photos.add(fixture(bitmap,0,1));photos.add(fixture(bitmap,1,6));}finally{bitmap.recycle();}
        openPhoto(0);sourceRoundtrip();if(fullScope())controlledTransientAndUnsupported();chooseEditor("Mono-no_eff-serp7");int strength0=(Integer)get(editor,"strength");check("monochrome-select-starts-full-strength",strength0==100);sliderStrength(50);drain();Object monoDraft=readDraft(0);String identity0=(String)call(monoDraft,"identity");
        check("photo0-saved-monochrome-bytes",Arrays.equals((byte[])call(monoDraft,"presetBytes"),presetBytes.get("Mono-no_eff-serp7")));capture("03-editor-monochrome-50");
        if(fullScope())exportConsistency(0,monoDraft);
        openPhoto(1);chooseEditor("Agfa Optima");sliderStrength(50);drain();Object colorDraft=readDraft(1);String identity1=(String)call(colorDraft,"identity");capture("04-editor-color-independent");if(fullScope())exportConsistency(1,colorDraft);
        openPhoto(0);check("photo0-reopens-own-settings",identity0.equals(call(readDraft(0),"identity"))&&(Integer)get(editor,"strength")==50&&Arrays.equals((byte[])get(editor,"selectedBytes"),presetBytes.get("Mono-no_eff-serp7")));
        openPhoto(1);check("photo1-reopens-own-settings",identity1.equals(call(readDraft(1),"identity"))&&(Integer)get(editor,"strength")==50&&Arrays.equals((byte[])get(editor,"selectedBytes"),presetBytes.get("Agfa Optima")));
        if(fullScope()){openPhoto(0);detailUi();}
    }
    private void controlledTransientAndUnsupported()throws Exception{
        stage="owned-transient-read-fault-real-retry";Object entry=editorEntry(transientId);check("owned-transient-entry-present",entry!=null);
        until(()->{ThreadPoolExecutor worker=(ThreadPoolExecutor)get(editor,"thumbnails");return worker.getActiveCount()==0&&worker.getQueue().isEmpty();},"thumbnail-worker-settled-before-fault");
        File root=(File)get(library,"root");movedFixture=new File(root,transientId+".ncp");movedBackup=own("temporarily-missing-preset.ncp");String originalSha=sha(movedFixture),metadataSha=sha(new File(root,transientId+".json"));int recordCount=((List<?>)call(library,"list")).size();
        Files.move(movedFixture.toPath(),movedBackup.toPath());
        try{
            ui(()->{set(entry,"bytes",null);set(entry,"profile",null);set(entry,"image",null);set(entry,"error","");set(entry,"retryable",false);});
            Dialog picker=openEditorCard(transientId);until(()->!(Boolean)get(entry,"loading")&&!get(entry,"error").toString().isEmpty(),"actual-missing-local-read-reported");
            check("missing-local-read-is-retryable",(Boolean)get(entry,"retryable")&&get(entry,"profile")==null);
            View faultCard=visibleEditorCard(transientId);check("transient-accessibility-offers-retry",faultCard.getContentDescription().toString().contains("预览加载失败，点按重试")&&!faultCard.getContentDescription().toString().contains("暂不支持"));
            Files.move(movedBackup.toPath(),movedFixture.toPath());check("same-local-file-restored-before-retry",sha(movedFixture).equals(originalSha));
            ui(()->check("real-native-retry-card-click",faultCard.performClick()));
            until(()->transientId.equals(get(editor,"selected"))&&get(editor,"popup")==null,"same-record-retry-selects-after-file-restored");waitEditor();
            check("retry-succeeds-without-reimport",((List<?>)call(library,"list")).size()==recordCount&&sha(new File(root,transientId+".json")).equals(metadataSha)&&sha((byte[])get(editor,"selectedBytes")).equals(originalSha)&&get(entry,"error").toString().isEmpty());
        }finally{if(movedBackup.exists())Files.move(movedBackup.toPath(),movedFixture.toPath());movedFixture=null;movedBackup=null;}
        stage="owned-genuine-unsupported-parser-classification";Object unsupported=editorEntry(unsupportedId);Dialog picker=openEditorCard(unsupportedId);
        until(()->!(Boolean)get(unsupported,"loading")&&!get(unsupported,"error").toString().isEmpty(),"actual-unverified-toning-parse-rejection");
        check("genuine-parser-rejection-not-retryable",!(Boolean)get(unsupported,"retryable")&&get(unsupported,"profile")==null&&get(unsupported,"error").toString().contains("不支持"));
        View card=visibleEditorCard(unsupportedId);check("genuine-unsupported-accessibility",card.getContentDescription().toString().contains("暂不支持")&&!card.getContentDescription().toString().contains("点按重试"));
        String before=(String)get(editor,"selected");int undo=((Deque<?>)get(editor,"undo")).size();ui(()->check("real-genuine-unsupported-card-click",card.performClick()));SystemClock.sleep(150);
        check("unsupported-tap-cannot-change-selection-history",before.equals(get(editor,"selected"))&&undo==((Deque<?>)get(editor,"undo")).size()&&get(unsupported,"profile")==null&&!(Boolean)get(unsupported,"retryable"));dismissOwnedNotice();ui(()->call(editor,"dismissPopup"));
    }
    private Object editorEntry(String id)throws Exception{for(Object e:(List<?>)get(editor,"entries"))if(id.equals(get(e,"id")))return e;return null;}
    private Dialog openEditorCard(String id)throws Exception{
        ui(()->call(editor,"showAll"));until(()->get(editor,"grid")!=null&&get(editor,"popup") instanceof Dialog,"controlled-editor-picker-open");selectMineInPicker();Dialog picker=(Dialog)get(editor,"popup");dialogs.add(picker);GridView grid=(GridView)get(editor,"grid");
        ui(()->{ListAdapter adapter=grid.getAdapter();int at=-1;for(int i=0;i<adapter.getCount();i++){Object value=adapter.getItem(i);if(value!=null&&id.equals(get(value,"id"))){at=i;break;}}check("controlled-editor-card-in-current-library",at>=0);grid.setSelection(at);});until(()->visibleEditorCard(id)!=null,"controlled-editor-card-visible");return picker;
    }
    private View visibleEditorCard(String id)throws Exception{GridView grid=(GridView)get(editor,"grid");if(grid==null)return null;for(int i=0;i<grid.getChildCount();i++){View child=grid.getChildAt(i);Object entry=get(child,"entry");if(entry!=null&&id.equals(get(entry,"id")))return child;}return null;}
    private void sourceRoundtrip()throws Exception{stage="actual-popup-source-bidirectional-roundtrip";String selected=(String)get(editor,"selected");int history=((Deque<?>)get(editor,"undo")).size();ui(()->call(editor,"showAll"));switchPickerSource(false);switchPickerSource(true);switchPickerSource(false);check("source-roundtrip-preserves-editing-state",selected.equals(get(editor,"selected"))&&history==((Deque<?>)get(editor,"undo")).size());ui(()->call(editor,"dismissPopup"));}
    private void selectMineInPicker()throws Exception{switchPickerSource(false);}
    private void switchPickerSource(boolean online)throws Exception{if((Boolean)get(editor,"onlineSource")!=online)ui(()->{Dialog popup=(Dialog)get(editor,"popup");Button control=findButtonText(popup.getWindow().getDecorView(),online?"在线":"我的");check("active-picker-source-control-visible-"+online,control!=null&&control.isShown());check("real-native-filter-source-click-"+online,control.performClick());});until(()->(Boolean)get(editor,"onlineSource")==online&&get(editor,"grid")!=null&&get(editor,"popup") instanceof Dialog,"native-picker-source-selected-"+online);SystemClock.sleep(150);ui(()->check("new-popup-grid-survives-old-dismiss-callback-"+online,get(editor,"grid")!=null&&get(editor,"gridAdapter")!=null&&get(editor,"popup") instanceof Dialog));}
    private static Button findButtonText(View root,String text){if(root instanceof Button&&((Button)root).getText().toString().equals(text))return(Button)root;if(root instanceof ViewGroup)for(int i=0;i<((ViewGroup)root).getChildCount();i++){Button found=findButtonText(((ViewGroup)root).getChildAt(i),text);if(found!=null)return found;}return null;}
    private void dismissOwnedNotice()throws Exception{long end=SystemClock.uptimeMillis()+5000;while(SystemClock.uptimeMillis()<end){AccessibilityNodeInfo root=getUiAutomation().getRootInActiveWindow();if(root!=null){List<AccessibilityNodeInfo> buttons=root.findAccessibilityNodeInfosByText("知道了");for(AccessibilityNodeInfo button:buttons)if(button.isVisibleToUser()&&button.performAction(AccessibilityNodeInfo.ACTION_CLICK)){check("owned-unsupported-notice-dismissed",true);return;}}SystemClock.sleep(40);}check("owned-unsupported-notice-dismissed",false);}
    private void chooseEditor(String name)throws Exception{
        String id=(String)get(records.get(name),"id");ui(()->call(editor,"showAll"));
        until(()->get(editor,"grid")!=null&&get(editor,"popup") instanceof Dialog,"real-editor-picker-open");selectMineInPicker();Dialog dialog=(Dialog)get(editor,"popup");dialogs.add(dialog);
        GridView grid=(GridView)get(editor,"grid");int[] index={-1};ui(()->{android.widget.ListAdapter adapter=grid.getAdapter();for(int i=0;i<adapter.getCount();i++){Object e=adapter.getItem(i);if(e!=null&&id.equals(get(e,"id")))index[0]=i;}check("editor-picker-has-existing-original-"+name,index[0]>=0);grid.setSelection(index[0]);});
        until(()->{for(int i=0;i<grid.getChildCount();i++){View card=grid.getChildAt(i);Object e=get(card,"entry");if(e!=null&&id.equals(get(e,"id")))return get(e,"profile")!=null&&get(e,"error").toString().isEmpty();}return false;},"editor-original-filter-card-ready-"+name);
        ui(()->{for(int i=0;i<grid.getChildCount();i++){View card=grid.getChildAt(i);Object e=get(card,"entry");if(e!=null&&id.equals(get(e,"id"))){check("real-editor-card-click-"+name,card.performClick());return;}}throw new AssertionError("Missing visible card");});
        until(()->id.equals(get(editor,"selected"))&&get(editor,"popup")==null,"real-editor-selects-original-"+name);waitEditor();
        check("editor-monochrome-original-file-unchanged-"+name,Arrays.equals(presetBytes.get(name),(byte[])get(editor,"selectedBytes")));
    }
    private void sliderStrength(int strength)throws Exception{ui(()->{SeekBar slider=(SeekBar)get(editor,"slider");slider.requestFocus();int direction=slider.getProgress()>strength?KeyEvent.KEYCODE_DPAD_LEFT:KeyEvent.KEYCODE_DPAD_RIGHT;int guard=0;while(slider.getProgress()!=strength&&guard++<150)slider.onKeyDown(direction,new KeyEvent(KeyEvent.ACTION_DOWN,direction));});waitEditor();check("real-filter-strength-"+strength,(Integer)get(editor,"strength")==strength);}
    private Object fixture(Bitmap bitmap,int index,int orientation)throws Exception{
        File directory=new File(getTargetContext().getExternalFilesDir(Environment.DIRECTORY_PICTURES),"camera-album");directory.mkdirs();File file=new File(directory,"ncp123-qa-"+args.getString("runId")+"-"+index+"__NCP.JPG");owned.add(file);
        try(FileOutputStream stream=new FileOutputStream(file)){check("synthetic-jpeg-"+index,bitmap.compress(Bitmap.CompressFormat.JPEG,98,stream));}
        ExifInterface exif=new ExifInterface(file.getPath());exif.setAttribute("Orientation",String.valueOf(orientation));exif.setAttribute("Make","Huevia NCP QA");exif.setAttribute("ImageDescription","Owned NCP preview QA "+UUID.randomUUID());exif.saveAttributes();originals.add(file);sourceHashes.add(sha(file));
        Constructor<?> constructor=type("cc.huevia.album.DownloadedPhoto").getDeclaredConstructor(File.class,String.class);constructor.setAccessible(true);return constructor.newInstance(file,"NCP_"+index+".JPG");
    }
    private static Bitmap texture(){int w=640,h=480;int[] p=new int[w*h];int[] colors={0xffd94c3c,0xff44a367,0xff315eb5,0xffd6b64c,0xff94705a,0xff9674a6};for(int y=0;y<h;y++)for(int x=0;x<w;x++){int c=colors[Math.min(5,y*3/h*3+x*3/w)],r=(c>>16)&255,g=(c>>8)&255,b=c&255,n=((x*73+y*31)^x*y)%31-15;p[y*w+x]=Color.rgb(clamp(r*(x%213)/212+n),clamp(g*(x%213)/212+n),clamp(b*(x%213)/212+n));}return Bitmap.createBitmap(p,w,h,Bitmap.Config.ARGB_8888);}
    private static int clamp(int v){return Math.max(0,Math.min(255,v));}
    private Object profile(byte[] bytes)throws Exception{return staticCall(type("cc.huevia.ncp.PresetPreviewProfiles"),"fromPreset",new Class<?>[]{byte[].class},bytes);}
    private Object readDraft(int index)throws Exception{return call(store,"read",new Class<?>[]{String.class},sourceHashes.get(index));}
    private void openPhoto(int index)throws Exception{if(editor!=null)drain();ui(()->{set(activity,"albumTab",true);set(activity,"settingsTab",false);call(panel,"openLocalWorkspace",new Class<?>[]{List.class,int.class},photos,index);});until(()->{Object e=get(panel,"filterEditor");return e!=null&&(Boolean)call(e,"isReady")&&sourceHashes.get(index).equals(get(e,"sourceSha"));},"editor-ready-photo-"+index);editor=get(panel,"filterEditor");waitEditor();}
    private void waitEditor()throws Exception{until(()->{ThreadPoolExecutor worker=(ThreadPoolExecutor)get(editor,"previews");return (Boolean)call(get(editor,"previewQueue"),"isIdle")&&!(Boolean)get(editor,"interactivePreview")&&worker.getActiveCount()==0&&worker.getQueue().isEmpty();},"editor-latest-final-preview-ready");}
    private void drain()throws Exception{if(editor==null)return;CountDownLatch done=new CountDownLatch(1);ui(()->call(editor,"afterPendingSaves",new Class<?>[]{Runnable.class},(Runnable)done::countDown));check("editor-drafts-drained",done.await(15,TimeUnit.SECONDS));}

    // Filled from the already verified universal-brush harness: exact full/detail reference pipeline.
    private void exportConsistency(int index,Object draft)throws Exception{
        Object p=call(draft,"profile"),render=type("cc.huevia.album.PhotoPresetRenderer").getConstructor(android.content.res.AssetManager.class).newInstance(activity.getAssets());
        Class<?> pc=type("cc.huevia.ncp.PresetPreviewProfile"),sc=type("cc.huevia.album.PhotoExportSpec"),progress=type("cc.huevia.album.PhotoPresetRenderer$Progress");
        File jpeg=own("export-"+index+".jpg"),reference=own("reference-"+index+".png"),detail=own("detail-"+index+".png");
        call(render,"renderWithReference",new Class<?>[]{File.class,File.class,File.class,pc,sc,BooleanSupplier.class,progress},originals.get(index),jpeg,reference,p,staticCall(sc,"full",new Class<?>[0]),(BooleanSupplier)()->false,null);
        call(render,"renderDetail",new Class<?>[]{File.class,File.class,pc,boolean.class,BooleanSupplier.class,progress},originals.get(index),detail,p,false,(BooleanSupplier)()->false,null);
        ExifInterface metadata=new ExifInterface(jpeg.getPath());int orientation=metadata.getAttributeInt("Orientation",1);Bitmap a=orientedExact(BitmapFactory.decodeFile(reference.getPath()),orientation),b=BitmapFactory.decodeFile(detail.getPath());
        try{check("mono-color-full-detail-exact-"+index,a.getWidth()==b.getWidth()&&a.getHeight()==b.getHeight()&&Arrays.equals(pixels(a),pixels(b)));measurements.put(new JSONObject().put("case","full-detail-"+index).put("width",a.getWidth()).put("height",a.getHeight()).put("exactArgb",true).put("orientation",orientation));}finally{a.recycle();b.recycle();}
        check("full-export-exif-preserved-"+index,orientation==(index==0?1:6)&&"Huevia NCP QA".equals(metadata.getAttribute("Make")));
    }
    private void detailUi()throws Exception{
        ui(()->call(editor,"showDetails"));until(()->get(editor,"detailDialog") instanceof Dialog&&((Dialog)get(editor,"detailDialog")).isShowing(),"real-monochrome-detail-open");Dialog d=(Dialog)get(editor,"detailDialog");dialogs.add(d);Object view=get(d,"detail"),source=get(d,"source");ui(()->((Button)get(d,"one")).performClick());
        until(()->(Boolean)call(view,"hasFullPixels")&&(Integer)get(get(view,"frame"),"sample")==1,"real-monochrome-detail-100-percent");Bitmap expected=BitmapFactory.decodeFile(new File(fixtureRoot,"detail-0.png").getPath());int[] count={0,0};try{ui(()->{for(Object tile:(List<?>)get(get(view,"frame"),"tiles")){Rect bounds=(Rect)get(tile,"bounds");Bitmap actual=(Bitmap)get(tile,"bitmap");for(int y=0;y<actual.getHeight();y++)for(int x=0;x<actual.getWidth();x++){count[0]++;if(actual.getPixel(x,y)!=expected.getPixel(bounds.left+x,bounds.top+y))count[1]++;}}});}finally{expected.recycle();}
        check("real-detail-tiles-match-frozen-export",count[0]>10000&&count[1]==0);capture("05-monochrome-actual-detail");File directory=(File)get(source,"directory");ui(d::dismiss);check("detail-worker-cleanup",((ThreadPoolExecutor)get(source,"worker")).awaitTermination(10,TimeUnit.SECONDS)&&!directory.exists());
    }
    private void cleanup(){try{if(movedBackup!=null&&movedBackup.exists()&&movedFixture!=null)Files.move(movedBackup.toPath(),movedFixture.toPath());for(Dialog d:dialogs)if(d.isShowing())ui(d::dismiss);if(editor!=null){drain();ui(()->call(editor,"unbind"));drain();}for(String hash:sourceHashes)if(draftRoot!=null)Files.deleteIfExists(new File(draftRoot,hash+".draft").toPath());for(File f:owned)Files.deleteIfExists(f.toPath());if(fixtureRoot!=null)Files.deleteIfExists(fixtureRoot.toPath());
        if(library!=null){File root=(File)get(library,"root");for(String id:importedIds)for(String suffix:new String[]{".json",".ncp"}){File f=new File(root,id+suffix);byte[] previous=libraryFilesBefore.get(f.getPath());if(previous==null)Files.deleteIfExists(f.toPath());else Files.write(f.toPath(),previous);}for(Map.Entry<String,byte[]> e:libraryFilesBefore.entrySet())check("preexisting-library-file-preserved-"+new File(e.getKey()).getName(),Arrays.equals(e.getValue(),Files.readAllBytes(new File(e.getKey()).toPath())));}
        fixturesRemoved=fixtureRoot==null||!fixtureRoot.exists();check("owned-fixtures-and-drafts-removed",fixturesRemoved);
        if(activity!=null)ui(()->{activity.setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED);activity.finish();});
    }catch(Throwable error){if(failure==null)failure=unwrap(error);}finally{try{if(templatePreferences!=null){SharedPreferences.Editor e=templatePreferences.edit();if(hadTemplate)e.putString("custom-sha256",priorTemplate);else e.remove("custom-sha256");templateRestored=e.commit()&&templatePreferences.contains("custom-sha256")==hadTemplate&&Objects.equals(priorTemplate,templatePreferences.getString("custom-sha256",null));check("exact-template-preference-restored",templateRestored);}}catch(Throwable error){if(failure==null)failure=unwrap(error);}}}
    private void writeReport(){try{if(output==null)return;PackageInfo info=getTargetContext().getPackageManager().getPackageInfo("cc.huevia",0);JSONObject report=new JSONObject().put("pass",failure==null).put("stage",stage).put("candidateSha256",args.getString("candidateSha256")).put("versionCode",info.getLongVersionCode()).put("versionName",info.versionName).put("mode",args.getString("mode")).put("probeScope",args.getString("scope","full")).put("checks",checks).put("recipes",recipes).put("measurements",measurements).put("screenshots",screenshotCount).put("fixturesRemoved",fixturesRemoved).put("fixtureManifest",manifest).put("oldModelVersion",oldModel).put("newModelVersion",newModel).put("goldenSha256",sha(asset("native-vectors.json"))).put("failure",failure==null?JSONObject.NULL:failure.toString()).put("scope",(args.getString("scope","full").equals("full")?"Full matrix; ":fullScope()?"Core continuation after sealed profile-identical earlier all149 matrix: no149/template/vector rerun; current APK covers brush integration, actual popup source roundtrip, readretry/parser classification, same-record gallery, picker/editor, two-photo drafts, mono/color full/detail export EXIF1/6. ":"Short UI batch: original149 matrix, golden vectors, brush integration and full/detail export are covered only by the separate full run; this run covers representative existing-record gallery/picker/editor and two-photo drafts. ")+"Original149 SHA-bound files parsed and rendered via installed Android profile and native template; all19 legacy monochrome gray/toning, frozen independent vectors and exact completed-effect strengths0/50/100. Existing-record gallery old unsupported keys remain isolated from new model key without reimport; actual native picker/editor selection, two synthetic JPEG drafts, representative monochrome/color full+detail/EXIF1+6. No user image or physical-phone/Nikon pipeline equivalence claim.");Files.writeString(new File(output,"report.json").toPath(),report.toString(2)+"\n");}catch(Throwable error){failure=unwrap(error);}}
    private File own(String name){File file=new File(fixtureRoot,name);owned.add(file);return file;}
    private byte[] asset(String name)throws Exception{try(InputStream in=getContext().getAssets().open(name)){return in.readAllBytes();}}
    private static int[] pixels(Bitmap b){int[] p=new int[b.getWidth()*b.getHeight()];b.getPixels(p,0,b.getWidth(),0,0,b.getWidth(),b.getHeight());return p;}
    private static boolean allGray(int[] values){for(int c:values)if(((c>>16)&255)!=((c>>8)&255)||((c>>8)&255)!=(c&255))return false;return true;}
    private static boolean someTint(int[] values){return !allGray(values);}
    private static int mix(int before,int after,int strength){int c=before&0xff000000;for(int shift:new int[]{0,8,16})c|=(int)Math.round(((before>>>shift)&255)+(((after>>>shift)&255)-((before>>>shift)&255))*(strength/100.0))<<shift;return c;}
    private static String pixelHash(Bitmap bitmap)throws Exception{return pixelHash(pixels(bitmap));}
    private static String pixelHash(int[] pixels)throws Exception{MessageDigest d=MessageDigest.getInstance("SHA-256");for(int p:pixels){d.update((byte)(p>>>24));d.update((byte)(p>>>16));d.update((byte)(p>>>8));d.update((byte)p);}return hex(d.digest());}
    private static Bitmap orientedExact(Bitmap input,int exif){if(exif==1)return input;if(exif!=6)throw new AssertionError("Only EXIF1/6 scoped");try{int w=input.getWidth(),h=input.getHeight();int[] raw=pixels(input),out=new int[raw.length];for(int y=0;y<h;y++)for(int x=0;x<w;x++)out[x*h+h-1-y]=raw[y*w+x];return Bitmap.createBitmap(out,h,w,Bitmap.Config.ARGB_8888);}finally{input.recycle();}}
    private void capture(String name)throws Exception{if(output==null||activity==null)return;SystemClock.sleep(250);ui(()->{});Bitmap image=getUiAutomation().takeScreenshot();check("screenshot-"+name,image!=null);try(FileOutputStream out=new FileOutputStream(new File(output,name+".png"))){check("screenshot-saved-"+name,image.compress(Bitmap.CompressFormat.PNG,100,out));}finally{image.recycle();}screenshotCount++;}
    private void until(Condition condition,String label)throws Exception{long end=SystemClock.uptimeMillis()+30000;while(SystemClock.uptimeMillis()<end){boolean[] value={false};ui(()->value[0]=condition.test());if(value[0]){check(label,true);return;}SystemClock.sleep(40);}check(label,false);}
    private void check(String name,boolean pass){try{checks.put(new JSONObject().put("name",name).put("pass",pass));}catch(JSONException e){throw new AssertionError(e);}if(!pass)throw new AssertionError(name);}
    private void ui(Work work){Throwable[] error={null};runOnMainSync(()->{try{work.run();}catch(Throwable failure){error[0]=failure;}});if(error[0]!=null)throw new RuntimeException(error[0]);}
    private Class<?> type(String name)throws Exception{return Class.forName(name,true,loader);}
    private static Object get(Object target,String name)throws Exception{for(Class<?> c=target.getClass();c!=null;c=c.getSuperclass())try{Field f=c.getDeclaredField(name);f.setAccessible(true);return f.get(target);}catch(NoSuchFieldException missing){}throw new NoSuchFieldException(name);}
    private static void set(Object target,String name,Object value)throws Exception{Field f=target.getClass().getDeclaredField(name);f.setAccessible(true);f.set(target,value);}
    private static Method method(Class<?> type,String name,Class<?>[] parameters)throws Exception{for(Class<?> c=type;c!=null;c=c.getSuperclass())try{Method m=c.getDeclaredMethod(name,parameters);m.setAccessible(true);return m;}catch(NoSuchMethodException missing){}Method m=type.getMethod(name,parameters);m.setAccessible(true);return m;}
    private static Object call(Object target,String name)throws Exception{return call(target,name,new Class<?>[0]);}
    private static Object call(Object target,String name,Class<?>[] parameters,Object...args)throws Exception{return method(target.getClass(),name,parameters).invoke(target,args);}
    private static Object staticCall(Class<?> type,String name,Class<?>[] parameters,Object...args)throws Exception{return method(type,name,parameters).invoke(null,args);}
    private static Throwable unwrap(Throwable e){while(e.getCause()!=null&&(e instanceof InvocationTargetException||e instanceof RuntimeException))e=e.getCause();return e;}
    private static String sha(File f)throws Exception{return sha(Files.readAllBytes(f.toPath()));}
    private static String sha(byte[] data)throws Exception{return hex(MessageDigest.getInstance("SHA-256").digest(data));}
    private static String hex(byte[] bytes){StringBuilder s=new StringBuilder();for(byte b:bytes)s.append(Character.forDigit((b>>>4)&15,16)).append(Character.forDigit(b&15,16));return s.toString();}
}
