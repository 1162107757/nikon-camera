package cc.huevia.legacyexport;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.os.Environment;
import android.view.View;
import android.widget.*;
import cc.huevia.shared.LegacyArchive;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;

/** Same-package, same-certificate maintenance overlay. All old data readers operate on copies. */
public final class LegacyExportActivity extends Activity {
    private static final int SAVE=49341;
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private final AtomicBoolean cancelled=new AtomicBoolean();
    private TextView status;private Button export;private File archive;private boolean busy;
    @Override public void onCreate(Bundle saved){super.onCreate(saved);
        LinearLayout page=new LinearLayout(this);page.setOrientation(LinearLayout.VERTICAL);int pad=(int)(24*getResources().getDisplayMetrics().density);page.setPadding(pad,pad,pad,pad);
        TextView title=new TextView(this);title.setText("导出旧版 Huevia 资料");title.setTextSize(24);page.addView(title);
        TextView help=new TextView(this);help.setText("本维护版本仅用于从原安装导出资料。导出本机可见预设、照片、当前账号草稿和项目分类；账号只包含公开资料，不包含密码或登录凭据。\n\n导出后请保留 ZIP，在新版“设置 → 旧版资料迁入”中预检并迁入。请保留原安装，切勿卸载清空数据。");help.setTextSize(16);help.setPadding(0,pad,0,pad);page.addView(help);
        export=new Button(this);export.setText("导出并选择保存位置");export.setOnClickListener(view->prepare());page.addView(export);
        status=new TextView(this);status.setTextSize(15);page.addView(status);setContentView(page);
    }
    private void prepare(){if(busy)return;busy=true;export.setEnabled(false);status.setText("正在核对并生成导出包…");
        worker.execute(()->{
            try{
                File files=getFilesDir();File parent=getExternalFilesDir(Environment.DIRECTORY_PICTURES);if(parent==null)parent=new File(files,"pictures");File photos=new File(parent,"camera-album");
                Map<String,Object> account=LegacyAccountProfile.read(getNoBackupFilesDir());String owner=(String)account.getOrDefault("id","");
                File output=new File(getCacheDir(),"Huevia-legacy-"+UUID.randomUUID()+".zip");
                try{LegacyArchive.exportAndroid(files,photos,owner,account,output,cancelled::get);}
                catch(Exception failure){output.delete();throw failure;}
                runOnUiThread(()->{if(isFinishing()||cancelled.get()){output.delete();return;}archive=output;status.setText("导出包已核对，请选择保存位置。");
                    try{startActivityForResult(new Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("application/zip").putExtra(Intent.EXTRA_TITLE,"Huevia-legacy-data.zip"),SAVE);}
                    catch(RuntimeException failure){finishExport("无法打开保存位置，请稍后重试。");}});
            }catch(Exception failure){runOnUiThread(()->finishExport(failure instanceof IOException&&failure.getMessage()!=null?failure.getMessage():"导出未完成，旧版资料保持原样。请检查空间后重试。"));}
        });
    }
    @Override protected void onActivityResult(int request,int result,Intent data){super.onActivityResult(request,result,data);if(request!=SAVE)return;
        if(result!=RESULT_OK||data==null||data.getData()==null){finishExport("已取消保存。旧版资料仍保留，可重新导出。");return;}
        status.setText("正在保存导出包，请保持页面打开…");worker.execute(()->{
            try(InputStream input=new FileInputStream(archive);OutputStream output=getContentResolver().openOutputStream(data.getData(),"wt")){
                if(output==null)throw new IOException();byte[] block=new byte[65536];int count;while((count=input.read(block))!=-1){if(cancelled.get())throw new InterruptedIOException();output.write(block,0,count);}output.flush();
                runOnUiThread(()->finishExport("导出包已保存。请在新版预检并核对所有资料后，再决定如何处理旧安装。"));
            }catch(IOException failure){runOnUiThread(()->finishExport("保存未完成，请删除目标位置的不完整 ZIP 后重新导出。旧版资料仍保留。"));}
        });
    }
    private void finishExport(String message){busy=false;export.setEnabled(true);status.setText(message);if(archive!=null){archive.delete();archive=null;}}
    @Override protected void onDestroy(){cancelled.set(true);worker.shutdownNow();if(archive!=null)archive.delete();super.onDestroy();}
}
