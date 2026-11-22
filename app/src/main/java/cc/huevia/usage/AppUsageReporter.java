package cc.huevia.usage;

import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageInfo;
import android.os.Build;
import cc.huevia.account.AccountHttpTransport;
import cc.huevia.account.AndroidAccounts;
import org.json.JSONObject;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.net.URL;
import java.util.UUID;
import java.util.concurrent.Executors;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.atomic.AtomicBoolean;

/** Anonymous usage for the original Android/transition app, independent of login. */
public final class AppUsageReporter {
    private static final String LAUNCH=UUID.randomUUID().toString();
    private static final double DRAW=Math.random();
    private static final AtomicBoolean OPTIONAL_SHOWN=new AtomicBoolean();
    private static final ExecutorService WORKER=Executors.newSingleThreadExecutor(r->{Thread t=new Thread(r,"app-usage");t.setDaemon(true);return t;});
    private static boolean sending,recorded;
    private static long lastAttempt,lastSuccess;
    private static Boolean lastLogin;
    private AppUsageReporter(){}
    public static boolean claimOptionalPrompt(Context context){
        double probability=context.getSharedPreferences("anonymous-app-usage",0).getFloat("promptProbability",.5f);
        return DRAW<probability&&OPTIONAL_SHOWN.compareAndSet(false,true);
    }
    public static synchronized void report(Context context){
        final Context app=context.getApplicationContext();
        // The shared app embeds legacy camera screens; its Dart reporter owns cc.huevia.next.
        if(!"cc.huevia".equals(app.getPackageName()))return;
        boolean login=AndroidAccounts.get(app).cachedSession()!=null;
        long now=android.os.SystemClock.elapsedRealtime();
        if(sending||lastAttempt>0&&now-lastAttempt<30_000||lastSuccess>0&&now-lastSuccess<15*60_000&&Boolean.valueOf(login).equals(lastLogin))return;
        sending=true;lastAttempt=now;
        WORKER.execute(()->{
            try{
                SharedPreferences prefs=app.getSharedPreferences("anonymous-app-usage",0);
                String installation=prefs.getString("installationId","");
                if(!installation.matches("[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}")){installation=UUID.randomUUID().toString();if(!prefs.edit().putString("installationId",installation).commit())return;}
                PackageInfo info=app.getPackageManager().getPackageInfo(app.getPackageName(),0);
                JSONObject body=new JSONObject().put("installationId",installation).put("launchId",LAUNCH).put("event",recorded?"heartbeat":"launch")
                    .put("platform","android").put("packageName",app.getPackageName()).put("versionCode",Build.VERSION.SDK_INT>=28?info.getLongVersionCode():info.versionCode)
                    .put("versionName",info.versionName).put("loggedIn",login);
                AccountHttpTransport.OpenedConnection opened=AccountHttpTransport.openPublicConnection(new URL(AccountHttpTransport.BASE_URL+"/app/usage"));
                try{
                    javax.net.ssl.HttpsURLConnection connection=opened.connection;
                    connection.setRequestMethod("POST");connection.setInstanceFollowRedirects(false);connection.setConnectTimeout(8000);connection.setReadTimeout(10000);
                    connection.setRequestProperty("Content-Type","application/json; charset=utf-8");connection.setRequestProperty("Accept","application/json");
                    byte[] bytes=body.toString().getBytes(StandardCharsets.UTF_8);connection.setDoOutput(true);connection.setFixedLengthStreamingMode(bytes.length);
                    try(OutputStream out=connection.getOutputStream()){out.write(bytes);}
                    if(connection.getResponseCode()!=200)return;
                    ByteArrayOutputStream response=new ByteArrayOutputStream();byte[] block=new byte[1024];int count;
                    try(InputStream input=connection.getInputStream()){while((count=input.read(block))!=-1){if(response.size()+count>8192)return;response.write(block,0,count);}}
                    JSONObject result=new JSONObject(response.toString(StandardCharsets.UTF_8.name()));
                    if(!result.optBoolean("recorded",false))return;
                    double probability=result.optDouble("promptProbability",.5);
                    if(Double.isFinite(probability)&&probability>=0&&probability<=1)prefs.edit().putFloat("promptProbability",(float)probability).apply();
                    synchronized(AppUsageReporter.class){recorded=true;lastSuccess=android.os.SystemClock.elapsedRealtime();lastLogin=login;}
                }finally{opened.close();}
            }catch(Exception ignored){/* Usage never blocks the original app, login or offline editing. */}
            finally{synchronized(AppUsageReporter.class){sending=false;}}
        });
    }
}
