package cc.huevia.shareqa;
import android.app.Activity;
import android.os.Bundle;
import android.content.Intent;
import android.net.Uri;
import android.graphics.BitmapFactory;
import android.widget.TextView;
import android.widget.ScrollView;
import org.json.*;
import java.io.*;
import java.security.MessageDigest;
import java.util.*;
public final class ShareReceiver extends Activity {
 @Override public void onCreate(Bundle state){super.onCreate(state);receive(getIntent());}
 private void receive(Intent intent){
  TextView view=new TextView(this);view.setTextSize(16);view.setPadding(24,24,24,24);ScrollView scroll=new ScrollView(this);scroll.addView(view);setContentView(scroll);
  new Thread(()->{JSONObject result=new JSONObject();
   try{
    ArrayList<Uri> files=Intent.ACTION_SEND_MULTIPLE.equals(intent.getAction())?intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM):new ArrayList<>();
    if(Intent.ACTION_SEND.equals(intent.getAction()))files.add(intent.getParcelableExtra(Intent.EXTRA_STREAM));
    if(files==null||files.isEmpty()||files.size()>100)throw new IOException("Invalid share file count");
    JSONArray receipts=new JSONArray();
    for(Uri uri:files){
     if(uri==null||!"content".equals(uri.getScheme())||uri.getAuthority()==null||!uri.getAuthority().startsWith("cc.huevia.next."))throw new IOException("Unexpected provider");
     String type=getContentResolver().getType(uri);boolean json="application/json".equals(type)||"application/json".equals(intent.getType());
     MessageDigest digest=MessageDigest.getInstance("SHA-256");long length=0;ByteArrayOutputStream text=json?new ByteArrayOutputStream():null;
     try(InputStream input=getContentResolver().openInputStream(uri)){byte[] bytes=new byte[65536];int n;while((n=input.read(bytes))!=-1){length+=n;if(length>(json?128*1024:128L*1024*1024))throw new IOException("Share exceeds QA bound");digest.update(bytes,0,n);if(json)text.write(bytes,0,n);}}
     StringBuilder hash=new StringBuilder();for(byte b:digest.digest())hash.append(String.format(Locale.ROOT,"%02x",b&255));
     JSONObject row=new JSONObject().put("bytes",length).put("sha256",hash).put("mime",type==null?"unknown":type);
     if(json){JSONObject report=new JSONObject(text.toString("UTF-8"));if(report.getInt("schema")!=1||report.getJSONObject("application").getInt("build")!=200)throw new IOException("Unexpected diagnostic report");row.put("report",report);}
     else{BitmapFactory.Options o=new BitmapFactory.Options();o.inJustDecodeBounds=true;try(InputStream input=getContentResolver().openInputStream(uri)){BitmapFactory.decodeStream(input,null,o);}if(o.outWidth<1||o.outHeight<1)throw new IOException("Invalid shared image");row.put("width",o.outWidth).put("height",o.outHeight);}
     receipts.put(row);
    }
    result.put("success",true).put("action",intent.getAction()).put("files",receipts);
   }catch(Exception error){try{result.put("success",false).put("error",error.toString());}catch(Exception ignored){}}
   final String output=result.toString();try(FileOutputStream file=openFileOutput("last.json",MODE_PRIVATE)){file.write(output.getBytes("UTF-8"));file.getFD().sync();}catch(Exception ignored){}
   runOnUiThread(()->view.setText(output));
  },"qa-share-reader").start();
 }
}
