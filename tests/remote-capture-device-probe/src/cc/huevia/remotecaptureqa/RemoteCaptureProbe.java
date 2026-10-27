package cc.huevia.remotecaptureqa;

import android.app.*;
import android.content.*;
import android.graphics.*;
import android.os.*;
import android.view.*;
import android.widget.*;
import cc.huevia.*;
import cc.huevia.album.*;
import cc.huevia.connection.CameraConnectionRuntime;
import cc.huevia.remote.*;
import cc.huevia.ui.PhotoFilterEditor;
import cc.huevia.ptp.*;
import java.io.*;
import java.lang.reflect.*;
import java.nio.file.*;
import java.security.*;
import java.util.*;
import java.util.concurrent.atomic.*;
import java.util.function.*;
import org.json.*;

/** Native UI and full PTP/IP fixture path on an owned emulator, never a physical camera. */
public final class RemoteCaptureProbe extends Instrumentation {
    private Bundle args;
    private Context context;
    private RemoteCaptureActivity activity;
    private RemoteCaptureController controller;
    private CameraConnectionRuntime runtime;
    private FakeNikonPeer peer;
    private PtpIpClient ptp;
    private File output;
    private final JSONObject report=new JSONObject();
    private final JSONArray assertions=new JSONArray();
    private final List<File> ownDownloads=new ArrayList<>();
    @Override public void onCreate(Bundle args){super.onCreate(args);this.args=args==null?new Bundle():args;start();}
    @Override public void onStart(){Bundle result=new Bundle();boolean passed=false;
        try{
            require(Build.HARDWARE.equals("ranchu")||Build.HARDWARE.equals("goldfish"),"emulator-only");context=getTargetContext();
            String apk=sha(new File(context.getApplicationInfo().sourceDir));require(apk.equals(args.getString("apkSha256")),"exact-installed-APK");
            String runId=args.getString("runId","");require(runId.matches("[a-f0-9]{32}"),"owned-run-id");
            String evidenceGroup=args.getString("evidenceGroup","remote-capture-95");require(evidenceGroup.matches("remote-capture-\\d+"),"owned-evidence-group");
            output=new File(context.getExternalFilesDir(null),evidenceGroup+"/"+runId);require(output.mkdirs(),"owned-evidence-directory");
            report.put("apkSha256",apk).put("scope","Native Android + synthetic PTP/IP peer; no real Nikon connection").put("mode",args.getString("mode","phone"));
            Bitmap sample;try(InputStream in=getContext().getAssets().open("live-view.png")){sample=BitmapFactory.decodeStream(in);}require(sample!=null,"existing-synthetic-sample-loaded");
            Bitmap frame=Bitmap.createScaledBitmap(sample,960,720,true);ByteArrayOutputStream jpeg=new ByteArrayOutputStream();require(frame.compress(Bitmap.CompressFormat.JPEG,90,jpeg),"synthetic-live-JPEG-encoded");if(frame!=sample)frame.recycle();sample.recycle();long vendor=Long.parseLong(args.getString("vendorId","10"));require(vendor==10||vendor==6||vendor==0xffffffffL,"known-Nikon-identity-fixture");peer=new FakeNikonPeer(jpeg.toByteArray(),960,720,vendor);report.put("vendorId",vendor);
            ptp=new PtpIpClient(peer);ptp.connect("fixture-only",15740,new byte[16],"Remote QA");
            policyBoundaries();
            runtime=onMain(()->CameraConnectionRuntime.get(context));inject(ptp);
            Activity mainActivity=startActivitySync(new Intent().setClassName("cc.huevia","cc.huevia.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            boolean landscape="landscape".equals(args.getString("mode"));onMain(()->{mainActivity.setRequestedOrientation(landscape?android.content.pm.ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE:android.content.pm.ActivityInfo.SCREEN_ORIENTATION_PORTRAIT);return null;});
            await(()->{try{return onMain(()->Boolean.TRUE.equals(field(mainActivity,"ready")));}catch(Exception error){return false;}},15000,"main-shell-ready");
            onMain(()->{View sync=findDescription(mainActivity.getWindow().getDecorView(),"同步");if(sync==null)throw new AssertionError("Sync navigation missing");sync.performClick();return null;});waitForIdleSync();
            ActivityMonitor monitor=addMonitor(RemoteCaptureActivity.class.getName(),null,false);
            await(()->{try{return onMain(()->findDescription(mainActivity.getWindow().getDecorView(),"遥控拍摄，查看实时画面、机身参数并拍照")!=null);}catch(Exception error){return false;}},10000,"sync-remote-entry-present");capture("entry.png");
            onMain(()->{findDescription(mainActivity.getWindow().getDecorView(),"遥控拍摄，查看实时画面、机身参数并拍照").performClick();return null;});activity=(RemoteCaptureActivity)waitForMonitorWithTimeout(monitor,10000);removeMonitor(monitor);require(activity!=null,"sync-entry-opens-native-remote-activity");
            onMain(()->{activity.setRequestedOrientation(landscape?android.content.pm.ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE:android.content.pm.ActivityInfo.SCREEN_ORIENTATION_PORTRAIT);return null;});
            await(()->{try{return onMain(()->(activity.getResources().getConfiguration().orientation==android.content.res.Configuration.ORIENTATION_LANDSCAPE)==landscape);}catch(Exception error){return false;}},5000,"requested-native-orientation-confirmed");
            report.put("nativeOrientation",landscape?"landscape":"portrait");
            controller=onMain(()->RemoteCaptureController.get(context));
            await(()->state().canCapture&&state().histogramFresh(),15000,"connected-current-frame-and-parameters");
            require(state().value(0x500d).equals("1/250")&&state().value(0x5007).equals("F2.8")&&state().value(0x500f).equals("320"),"parameters-from-wire-datasets");
            require(state().frame.histogram.pixelCount()==(long)state().frame.bitmap.getWidth()*state().frame.bitmap.getHeight(),"histogram-pixels-match-displayed-frame");
            require(peer.shutters==0,"no-shutter-during-connect-or-preview");
            nativeBounds();capture("ready.png");
            if("toolbar".equals(args.getString("scope"))){toolbarStates();report.put("verificationScope","toolbar-states-only");passed=true;return;}
            if("status".equals(args.getString("scope"))){statusStates();report.put("verificationScope","compact-status-and-detail-disclosure-only");passed=true;return;}
            editorGridIcon();
            View surface=onMain(()->activity.getWindow().getDecorView());View stage=findClass(surface,"FrameStage");View histogram=findDescription(surface,"取景直方图，点按放大，拖动调整位置");
            require(onMain(()->findText(surface,"拍后传入 App")==null&&findText(surface,"照片保存到相机")==null),"save-options-do-not-occupy-shooting-footer");
            require(onMain(()->{int[] gear=new int[2],chart=new int[2];findDescription(surface,"拍摄设置").getLocationOnScreen(gear);findDescription(surface,"显示或收起直方图").getLocationOnScreen(chart);return gear[0]<chart[0]&&gear[1]==chart[1];}),"settings-gear-is-left-of-histogram");
            if(landscape){int w=onMain(()->stage.getWidth()),h=onMain(()->stage.getHeight());Bitmap bright=Bitmap.createBitmap(w,h,Bitmap.Config.ARGB_8888);bright.eraseColor(0xfffff7e8);ByteArrayOutputStream brightBytes=new ByteArrayOutputStream();require(bright.compress(Bitmap.CompressFormat.JPEG,90,brightBytes),"bright-overlay-fixture-encoded");bright.recycle();long oldSequence=state().frame.sequence;peer.preview(brightBytes.toByteArray(),w,h);await(()->state().frame.sequence>oldSequence&&state().frame.wire.width==w,5000,"wide-bright-frame-beneath-tools");capture("landscape-bright-tools.png");peer.preview(null,0,0);await(()->state().frame.wire.width==960,5000,"original-frame-restored-after-contrast-evidence");}
            RectF before=onMain(()->new RectF((RectF)field(stage,"image")));onMain(()->{findDescription(surface,"显示或收起直方图").performClick();return null;});waitForIdleSync();
            RectF after=onMain(()->new RectF((RectF)field(stage,"image")));require(before.equals(after),"histogram-hide-preserves-image-rectangle");onMain(()->{findDescription(surface,"显示或收起直方图").performClick();return null;});
            drag(histogram,65,-75);require(onMain(()->histogram.getX())>0,"histogram-drag-moves-native-widget");capture("histogram-moved.png");
            onMain(()->{histogram.performClick();return null;});waitForIdleSync();clickText("RGB");capture("histogram.png");pressBack();
            onMain(()->{findDescription(surface,"拍摄设置").performClick();return null;});require(onMain(()->findText(currentRoot(),"相机存储卡")!=null),"gear-explains-camera-storage");capture("options.png");clickText("拍后传入 App");require(state().transfer,"gear-transfer-switch-enables-existing-controller");pressBack();clickDescription("拍摄设置");require(onMain(()->((Switch)findText(currentRoot(),"拍后传入 App")).isChecked()),"gear-transfer-choice-survives-sheet-reopen");clickText("拍后传入 App");require(!state().transfer,"gear-transfer-switch-can-disable");pressBack();
            peer.rejectFocus=true;long focusSequence=state().frame.sequence;clickDescription("自动对焦");await(()->state().message.contains("不允许"),5000,"AF-rejection-is-readable");String focusError=state().message;SystemClock.sleep(1200);require(state().message.equals(focusError)&&state().frame.sequence>focusSequence,"AF-rejection-survives-active-preview-polling");capture("rejected-focus.png");peer.rejectFocus=false;
            int focusBefore=peer.focuses;clickDescription("自动对焦");await(()->peer.focuses==focusBefore+1,5000,"focus-button-command");
            await(()->state().canPointFocus,5000,"validated-tap-AF-geometry");RectF target=onMain(()->new RectF((RectF)field(stage,"image")));int[] location=new int[2];onMain(()->{stage.getLocationOnScreen(location);return null;});tap(location[0]+target.left+target.width()*.6f,location[1]+target.top+target.height()*.4f);await(()->!peer.areas.isEmpty(),5000,"tap-AF-request");long[] af=peer.areas.get(peer.areas.size()-1);require(Math.abs(af[0]-Math.round(.6*959))<=2&&Math.abs(af[1]-Math.round(.4*719))<=2,"tap-AF-mapped-only-through-image-rectangle");
            await(()->state().canCapture,5000,"ready-after-focus");onMain(()->{controller.setTransfer(true);View shutter=findDescription(activity.getWindow().getDecorView(),"拍照");shutter.performClick();shutter.performClick();return null;});
            await(()->state().imported!=null,15000,"confirmed-photo-imported-through-existing-download-store");require(peer.shutters==1&&peer.shots==1,"double-click-sends-one-card-shutter");
            require(Arrays.equals(Files.readAllBytes(state().imported.file().toPath()),peer.jpeg),"imported-original-is-byte-identical-peer-JPEG");ownDownloads.add(state().imported.file());capture("captured.png");
            peer.viewFailure=true;await(()->state().viewPaused,10000,"live-view-interruption-independent-from-session");require(state().connected&&!state().histogramFresh(),"interrupted-view-does-not-claim-current-histogram");capture("view-lost.png");peer.viewFailure=false;onMain(()->{controller.retryView();return null;});await(()->state().histogramFresh(),10000,"explicit-live-view-recovery");
            onMain(()->{controller.setLiveEnabled(false);return null;});await(()->!peer.live,10000,"view-off-sends-end-liveview");require(!state().histogramFresh(),"view-off-pauses-histogram");await(()->state().canCapture,5000,"view-off-keeps-current-parameter-shutter-path");onMain(()->{controller.setLiveEnabled(true);controller.retryView();return null;});await(()->state().histogramFresh(),10000,"view-on-restarts-frame-path");
            peer.rawFirst=true;await(()->Long.valueOf(7).equals(state().parameters.get(0x5004))&&state().canCapture,6000,"RAW-JPEG-mode-read-from-camera");onMain(()->{controller.capture();return null;});await(()->state().message.contains("等待配套 JPEG"),6000,"RAW-first-arrival-waits-for-JPEG-sibling");require(state().outcome==RemoteCaptureController.Outcome.CAPTURING,"RAW-first-does-not-prematurely-enable-shutter");await(()->state().outcome==RemoteCaptureController.Outcome.CONFIRMED&&state().recent!=null&&state().recent.jpeg()&&state().recent.object.filename().contains("0012")&&state().imported!=null,12000,"delayed-JPEG-sibling-imports-after-RAW");require(Arrays.equals(Files.readAllBytes(state().imported.file().toPath()),peer.jpeg),"JPEG-sibling-reuses-valid-original-with-content-dedup");ownDownloads.add(state().imported.file());require(peer.shutters==2,"RAW-JPEG-pair-still-one-explicit-shutter");peer.rawFirst=false;
            await(()->state().canCapture,5000,"ready-before-rejected-shutter");peer.busyCapture=true;int shotsBeforeRejection=peer.shots;long rejectSequence=state().frame.sequence;onMain(()->{controller.capture();return null;});await(()->state().outcome==RemoteCaptureController.Outcome.IDLE&&state().message.contains("忙"),5000,"shutter-busy-rejection-is-readable");String shutterError=state().message;SystemClock.sleep(1200);require(state().message.equals(shutterError)&&state().frame.sequence>rejectSequence,"shutter-rejection-survives-active-preview-polling");require(peer.shutters==3&&peer.shots==shotsBeforeRejection&&!context.getSharedPreferences("remote-capture-journal",Context.MODE_PRIVATE).getBoolean("pending",false),"definitive-rejection-clears-journal-without-taking-photo");capture("rejected-shutter.png");peer.busyCapture=false;
            await(()->state().canCapture,5000,"ready-before-unknown-result");peer.cutCapture=true;onMain(()->{controller.setTransfer(false);controller.capture();return null;});await(()->state().outcome==RemoteCaptureController.Outcome.UNKNOWN&&!state().connected,10000,"lost-response-keeps-unknown-outcome");require(peer.shutters==4&&!state().canCapture,"unknown-outcome-blocks-repeat-shutter");capture("unknown.png");
            require(context.getSharedPreferences("remote-capture-journal",Context.MODE_PRIVATE).getBoolean("pending",false),"unknown-outcome-is-durable");
            onMain(()->{controller.capture();return null;});SystemClock.sleep(200);require(peer.shutters==4,"disconnected-unknown-never-auto-resends");
            await(()->!runtime.album.isRemoteCaptureReserved(),10000,"lost-session-releases-album-reservation");peer.cutCapture=false;ptp=new PtpIpClient(peer);ptp.connect("fixture-only",15740,new byte[16],"Remote QA");inject(ptp);onMain(()->{controller.start();return null;});await(()->state().connected&&state().frame!=null,10000,"new-session-can-reacquire-capabilities");require(state().outcome==RemoteCaptureController.Outcome.UNKNOWN&&!state().canCapture,"reconnect-does-not-clear-unknown-shutter");onMain(()->{controller.verifyUnknown();return null;});await(()->state().outcome==RemoteCaptureController.Outcome.CONFIRMED,10000,"explicit-check-finds-shot-after-lost-response");require(peer.shutters==4,"result-verification-never-resends-capture");
            onMain(()->{controller.disconnect();return null;});require(!state().connected&&!state().canCapture&&!state().canFocus,"disconnect-disables-controls-and-current-values");require(state().value(0x500d).equals("—"),"disconnect-clears-current-parameters");capture("offline.png");
            require(state().recent!=null&&state().recent.jpeg()&&state().imported==null,"offline-recent-JPEG-is-retained-and-unimported");clickDescription("查看最近拍摄");View unavailableImport=onMain(()->findText(currentRoot(),"重连后可传入 App"));require(unavailableImport!=null&&!unavailableImport.isEnabled(),"offline-recent-import-is-explained-and-disabled");capture("offline-recent.png");pressBack();
            passed=true;
        }catch(Throwable error){try{report.put("failure",error.toString());StringWriter stack=new StringWriter();error.printStackTrace(new PrintWriter(stack));report.put("stack",stack.toString());if(output!=null)capture("failure.png");}catch(Exception ignored){}result.putString("failure",error.toString());}
        finally{
            boolean cleaned=true;try{if(controller!=null)onMain(()->{controller.setVisible(false);controller.stop();return null;});if(activity!=null)onMain(()->{activity.finish();return null;});if(peer!=null)peer.close();if(ptp!=null)ptp.close();for(File file:ownDownloads)if(file.exists())cleaned&=file.delete();}catch(Exception error){cleaned=false;}
            try{report.put("status",passed&&cleaned?"PASS":"FAIL").put("assertions",assertions).put("fixtureCleanup",cleaned).put("shutterCommands",peer==null?0:peer.shutters);if(output!=null)Files.writeString(new File(output,"report.json").toPath(),report.toString(2));}catch(Exception error){passed=false;}
            result.putString("stream",passed&&cleaned?"Remote capture PASS\n":"Remote capture FAIL\n");if(output!=null)result.putString("evidence",output.getAbsolutePath());finish(passed&&cleaned?-1:0,result);
        }
    }
    private void policyBoundaries()throws Exception{
        int before=peer.operations.size();rejects(()->ptp.getData(0x9203,100),"generic-album-cannot-start-remote-read");require(peer.operations.size()==before,"generic-rejection-before-wire");
        PtpIpClient.RemoteOperations remote=ptp.openRemoteOperations();before=peer.operations.size();
        rejects(()->remote.command(0x1016,0x5007),"remote-cannot-set-properties");rejects(()->remote.command(0x9207,0xfffffffeL,1),"remote-cannot-trigger-AF-SDRAM-capture");rejects(()->remote.data(0x1009,1024,10),"remote-generic-data-cannot-buffer-original");rejects(ptp::transferToPictureControl,"capture-grant-blocks-preset-handoff");require(peer.operations.size()==before,"remote-rejections-before-wire");remote.close();rejects(()->remote.command(0x9201),"revoked-token-cannot-restart-view");require(ptp.isOpen(),"token-close-retains-physical-connection");
    }
    private void toolbarStates()throws Exception {
        View stage=onMain(()->findClass(activity.getWindow().getDecorView(),"FrameStage"));
        RectF before=onMain(()->new RectF((RectF)field(stage,"image")));
        clickDescription("切换构图网格");capture("grid-on.png");
        clickDescription("切换构图网格");capture("grid-off.png");
        clickDescription("显示或收起直方图");capture("histogram-off.png");
        clickDescription("显示或收起直方图");
        require(before.equals(onMain(()->new RectF((RectF)field(stage,"image")))),"toolbar-toggles-preserve-image-rectangle");
        require(state().histogramFresh()&&peer.shutters==0,"toolbar-only-preview-stays-current-without-shutter");
    }
    private void statusStates()throws Exception {
        Object surface=field(activity,"surface");
        TextView status=(TextView)field(surface,"status");
        nativeBounds();
        onMain(()->{((Handler)field(controller,"main")).removeCallbacks((Runnable)field(controller,"polling"));set(controller,"workPending",true);set(controller,"userWork",true);set(controller,"importing",true);PhotoTransferProgress progress=(PhotoTransferProgress)field(controller,"importProgress");long now=PhotoTransferProgress.now();progress.start(13672454L,now-4000);progress.update(2831155L,13672454L,now);((cc.huevia.ui.RemoteCaptureView)surface).update();return null;});
        capture("status-speed.png");
        require(onMain(()->status.getText().toString().contains("/s")&&status.getText().toString().contains("秒")),"remote-receive-rate-and-eta");
        require(onMain(()->status.getLineCount()==1&&status.getLayout().getEllipsisCount(0)==0),"remote-rate-single-line-untruncated");
        onMain(()->{PhotoTransferProgress progress=(PhotoTransferProgress)field(controller,"importProgress");long now=PhotoTransferProgress.now();progress.start(13672454L,now-12000);progress.update(2831155L,13672454L,now-7000);((cc.huevia.ui.RemoteCaptureView)surface).update();return null;});
        capture("status-wait.png");require(onMain(()->status.getText().toString().equals("等待相机")),"remote-wait-short-with-no-new-callback");
        onMain(()->{status.performClick();return null;});capture("status-details.png");
        require(onMain(()->field(surface,"sheet") instanceof Dialog&&((Dialog)field(surface,"sheet")).isShowing()),"remote-details-explicit");
        onMain(()->{((Dialog)field(surface,"sheet")).dismiss();set(controller,"importing",false);set(controller,"userWork",false);set(controller,"workPending",false);set(controller,"viewPaused",true);set(controller,"viewMessage","测试：实时画面暂停，连接仍有效。");((cc.huevia.ui.RemoteCaptureView)surface).update();return null;});
        capture("status-view-paused.png");
        require(state().connected&&onMain(()->findText(activity.getWindow().getDecorView(),"取景已暂停")!=null),"paused-view-does-not-claim-connection-loss");
        onMain(()->{controller.stop();((cc.huevia.ui.RemoteCaptureView)surface).update();return null;});capture("status-disconnected.png");
        require(!state().connected&&state().connectionStatus.equals("连接已断开"),"unobserved-wifi-does-not-invent-disconnect-cause");
        require(onMain(()->findText(activity.getWindow().getDecorView(),"重连")!=null),"disconnect-has-short-reconnect-action");
        onMain(()->{set(controller,"outcome",RemoteCaptureController.Outcome.UNKNOWN);((cc.huevia.ui.RemoteCaptureView)surface).update();return null;});
        require(onMain(()->status.getText().toString().equals("拍摄待确认 · 核对")),"unknown-shutter-remains-explicit");
        require(peer.shutters==0,"status-verification-never-releases-shutter");
        onMain(()->{set(controller,"outcome",RemoteCaptureController.Outcome.IDLE);return null;});
    }
    private void editorGridIcon()throws Exception {
        PhotoFilterEditor editor=onMain(()->new PhotoFilterEditor(activity,null,new PhotoFilterEditor.Host(){public void changed(){}public void export(List<PhotoPresetBatch.Edit> edits){}public void raw(){}public boolean canExportRaw(){return false;}public void download(){}public void addFilters(){}public void error(String error){throw new AssertionError(error);}}));
        Dialog dialog=onMain(()->{Dialog d=new Dialog(activity);d.setContentView(editor.createDock());d.show();d.getWindow().setLayout(-1,-2);d.getWindow().setGravity(Gravity.BOTTOM);return d;});
        try {
            waitForIdleSync();View button=onMain(()->findDescription(dialog.getWindow().getDecorView(),"查看全部滤镜"));require(button!=null&&button.getWidth()>0,"real-editor-grid-button-laid-out");
            for(int direction:new int[]{View.LAYOUT_DIRECTION_LTR,View.LAYOUT_DIRECTION_RTL}) {
                double[] offset=onMain(()->{button.setLayoutDirection(direction);Bitmap bitmap=Bitmap.createBitmap(button.getWidth(),button.getHeight(),Bitmap.Config.ARGB_8888);button.draw(new Canvas(bitmap));int minX=bitmap.getWidth(),maxX=-1,minY=bitmap.getHeight(),maxY=-1;for(int y=0;y<bitmap.getHeight();y++)for(int x=0;x<bitmap.getWidth();x++){int pixel=bitmap.getPixel(x,y);if(Color.alpha(pixel)>240&&Color.red(pixel)>200&&Color.green(pixel)>200&&Color.blue(pixel)>200){minX=Math.min(minX,x);maxX=Math.max(maxX,x);minY=Math.min(minY,y);maxY=Math.max(maxY,y);}}bitmap.recycle();if(maxX<minX)throw new AssertionError("Missing drawn grid glyph");return new double[]{(minX+maxX+1)/2.0-button.getWidth()/2.0,(minY+maxY+1)/2.0-button.getHeight()/2.0};});
                require(Math.abs(offset[0])<=1&&Math.abs(offset[1])<=1,"editor-grid-ink-centered-within-one-pixel-"+direction);report.put(direction==View.LAYOUT_DIRECTION_LTR?"gridLtrOffset":"gridRtlOffset",new JSONArray(offset));
            }
            onMain(()->{button.setLayoutDirection(View.LAYOUT_DIRECTION_LTR);return null;});capture("editor-grid.png");
        } finally {onMain(()->{dialog.dismiss();editor.close();return null;});}
    }
    private void inject(PtpIpClient client)throws Exception{onMain(()->{set(runtime.album,"active",client);Constructor<ConnectionInfo> constructor=ConnectionInfo.class.getDeclaredConstructor(String.class,String.class,int.class,int.class,CameraProtocol.class);constructor.setAccessible(true);ConnectionInfo info=constructor.newInstance("NIKON Z 6_2","fixture-only",15740,peer.shots+1,CameraProtocol.NIKON);set(runtime.album,"sessionConnectionInfo",info);set(runtime.album,"cachedConnectionInfo",info);set(runtime.album,"deviceInfo",PtpDeviceInfo.parse(peer.info));set(runtime.album,"session","remote-qa-session");long[] handles=new long[peer.shots+1];for(int i=0;i<handles.length;i++)handles[i]=10+i;set(runtime.album,"handles",handles);return null;});}
    private RemoteCaptureController.State state(){try{return onMain(()->controller.state());}catch(Exception error){throw new RuntimeException(error);}}
    private void nativeBounds()throws Exception{View root=onMain(()->activity.getWindow().getDecorView());float density=context.getResources().getDisplayMetrics().density;List<View> controls=new ArrayList<>();walk(root,controls);int count=0;for(View v:controls)if(v.isShown()&&v.isClickable()){require(v.getWidth()+1>=48*density&&v.getHeight()+1>=48*density,"48dp-target-"+v.getClass().getSimpleName()+"-"+(count++));}require(count>=9,"native-controls-present");View shutter=findDescription(root,"拍照");int[] pos=new int[2];onMain(()->{shutter.getLocationOnScreen(pos);return null;});require(pos[1]+shutter.getHeight()<=root.getHeight(),"shutter-within-screen");}
    private void capture(String name)throws Exception{waitForIdleSync();SystemClock.sleep(180);Bitmap b=getUiAutomation().takeScreenshot();require(b!=null&&!b.isRecycled(),"capture-"+name);try(FileOutputStream out=new FileOutputStream(new File(output,name))){if(!b.compress(Bitmap.CompressFormat.PNG,100,out))throw new IOException("screenshot encode");}finally{b.recycle();}}
    private void clickDescription(String description)throws Exception{onMain(()->{View view=findDescription(activity.getWindow().getDecorView(),description);if(view==null)throw new AssertionError("Missing "+description);view.performClick();return null;});waitForIdleSync();}
    private void clickText(String value)throws Exception{onMain(()->{View view=findText(currentRoot(),value);if(view==null)throw new AssertionError("Missing text "+value);view.performClick();return null;});waitForIdleSync();}
    private View currentRoot()throws Exception{Object view=field(activity,"surface");Object dialog=field(view,"sheet");return dialog instanceof Dialog?((Dialog)dialog).getWindow().getDecorView():activity.getWindow().getDecorView();}
    private void pressBack(){sendKeyDownUpSync(KeyEvent.KEYCODE_BACK);waitForIdleSync();}
    private void drag(View view,float dx,float dy)throws Exception{int[] pos=new int[2];onMain(()->{view.getLocationOnScreen(pos);return null;});float x=pos[0]+view.getWidth()/2f,y=pos[1]+view.getHeight()/2f;long down=SystemClock.uptimeMillis();pointer(down,down,MotionEvent.ACTION_DOWN,x,y);pointer(down,down+80,MotionEvent.ACTION_MOVE,x+dx,y+dy);pointer(down,down+150,MotionEvent.ACTION_UP,x+dx,y+dy);waitForIdleSync();}
    private void tap(float x,float y){long time=SystemClock.uptimeMillis();pointer(time,time,MotionEvent.ACTION_DOWN,x,y);pointer(time,time+80,MotionEvent.ACTION_UP,x,y);waitForIdleSync();}
    private void pointer(long down,long time,int action,float x,float y){MotionEvent e=MotionEvent.obtain(down,time,action,x,y,0);try{sendPointerSync(e);}finally{e.recycle();}}
    private void await(BooleanSupplier condition,long timeout,String name)throws Exception{long end=SystemClock.elapsedRealtime()+timeout;while(SystemClock.elapsedRealtime()<end){if(condition.getAsBoolean()){require(true,name);return;}SystemClock.sleep(80);}throw new AssertionError(name+" timed out; "+(controller==null?"":state().message));}
    private void require(boolean value,String name)throws Exception{if(!value)throw new AssertionError(name);assertions.put(name);}
    private interface Throwing{void run()throws Exception;}
    private void rejects(Throwing action,String name)throws Exception{try{action.run();throw new AssertionError(name);}catch(IOException expected){require(true,name);}}
    private interface Work<T>{T run()throws Exception;}
    private <T>T onMain(Work<T> work)throws Exception{AtomicReference<T> result=new AtomicReference<>();AtomicReference<Throwable> error=new AtomicReference<>();runOnMainSync(()->{try{result.set(work.run());}catch(Throwable e){error.set(e);}});if(error.get()!=null){if(error.get() instanceof Exception)throw(Exception)error.get();throw new AssertionError(error.get());}return result.get();}
    private static Object field(Object object,String name)throws Exception{Class<?> type=object.getClass();while(type!=null)try{Field f=type.getDeclaredField(name);f.setAccessible(true);return f.get(object);}catch(NoSuchFieldException absent){type=type.getSuperclass();}throw new NoSuchFieldException(name);}
    private static void set(Object object,String name,Object value)throws Exception{Field f=object.getClass().getDeclaredField(name);f.setAccessible(true);f.set(object,value);}
    private static void walk(View view,List<View> out){out.add(view);if(view instanceof ViewGroup)for(int i=0;i<((ViewGroup)view).getChildCount();i++)walk(((ViewGroup)view).getChildAt(i),out);}
    private static View findDescription(View root,String value){List<View> all=new ArrayList<>();walk(root,all);for(View v:all)if(value.contentEquals(v.getContentDescription()==null?"":v.getContentDescription()))return v;return null;}
    private static View findClass(View root,String name){List<View> all=new ArrayList<>();walk(root,all);for(View v:all)if(v.getClass().getSimpleName().equals(name))return v;return null;}
    private static View findText(View root,String value){List<View> all=new ArrayList<>();walk(root,all);for(View v:all)if(v instanceof TextView&&value.contentEquals(((TextView)v).getText()))return v;return null;}
    private static String sha(File file)throws Exception{MessageDigest digest=MessageDigest.getInstance("SHA-256");try(InputStream input=new FileInputStream(file)){byte[] b=new byte[65536];for(int n;(n=input.read(b))>0;)digest.update(b,0,n);}StringBuilder out=new StringBuilder();for(byte b:digest.digest())out.append(String.format(Locale.ROOT,"%02x",b&255));return out.toString();}
}
