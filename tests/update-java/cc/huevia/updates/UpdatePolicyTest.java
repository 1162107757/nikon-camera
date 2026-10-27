package cc.huevia.updates;

/** Pure-Java policy boundaries only; APK verification and DownloadManager require Android runtime. */
public final class UpdatePolicyTest {
    private static int checks;
    public static void main(String[] args) {
        require(UpdatePolicy.MAX_APK_BYTES==33_554_432L,"approved APK capacity is exactly 32 MiB");
        // Metadata-size regression only; this does not inspect or install an actual APK.
        long fourAbiArtifactBytes=9_478_052L;
        require(fourAbiArtifactBytes>4_194_304L&&fourAbiArtifactBytes<=UpdatePolicy.MAX_APK_BYTES,"four-ABI release size exceeds the legacy limit and fits the new policy");
        require(UpdatePolicy.percent(16_777_216L,UpdatePolicy.MAX_APK_BYTES)==50,"32 MiB progress preserves byte-count ratios");
        require(UpdatePolicy.percent(33_554_432L,UpdatePolicy.MAX_APK_BYTES)==100&&UpdatePolicy.percent(33_554_433L,UpdatePolicy.MAX_APK_BYTES)==100,"progress saturates at capacity and capacity plus one; artifact rejection belongs to manager validation");
        String base="https://updates.example.test/preset-library",id="19bd1434-e597-4f27-808d-9b86eb8d983d",url=base+"/releases/"+id+"/file";
        require(UpdatePolicy.trustedUrl(base,url,id),"canonical product download allowed");
        for(String bad:new String[]{"http://updates.example.test/preset-library/releases/"+id+"/file","https://updates.example.test.evil.test/preset-library/releases/"+id+"/file","https://evil.test/preset-library/releases/"+id+"/file",url+"?token=secret",url+"#fragment",url.replace("https://","https://user:pass@"),url.replace("example.test/","example.test:443/"),url.replace("/releases/","/../releases/"),url.replace("/releases/","/%72eleases/"),url.replace("/file","/file/"),url.replace("/file","/file%2f..%2fphotos"),null,"",url+"\nInjected: value"})require(!UpdatePolicy.trustedUrl(base,bad,id),"untrusted destination rejected");
        for(String hash:new String[]{"a".repeat(64),"0".repeat(64),"0123456789abcdef".repeat(4)})require(UpdatePolicy.hash(hash),"valid content hash");
        for(String bad:new String[]{null,"","a".repeat(63),"a".repeat(65),"A".repeat(64),"g".repeat(64),"../"+"a".repeat(61),"a".repeat(63)+"\n"})require(!UpdatePolicy.hash(bad),"hash cannot construct other file paths");
        require(UpdatePolicy.newer(53,54),"strict upgrade");require(!UpdatePolicy.newer(54,54),"same version not reinstalled");require(!UpdatePolicy.newer(54,53),"downgrade rejected");require(!UpdatePolicy.newer(0,54),"unknown installed version fails closed");require(!UpdatePolicy.newer(54,0),"unknown candidate version rejected");
        require(UpdatePolicy.defaultChannel("0.21.0-beta").equals("beta"),"beta builds default to beta releases");
        require(UpdatePolicy.defaultChannel("0.21.0-BETA.2").equals("beta"),"beta marker is case insensitive");
        require(UpdatePolicy.defaultChannel("0.21.0").equals("stable"),"stable builds default to stable releases");
        require(UpdatePolicy.defaultChannel(null).equals("stable")&&UpdatePolicy.defaultChannel("").equals("stable"),"unknown version names use stable fallback");
        require(UpdatePolicy.mandatory(53,54,true),"required newer release blocks");
        require(!UpdatePolicy.mandatory(53,54,false),"ordinary release does not block");
        require(!UpdatePolicy.mandatory(54,54,true)&&!UpdatePolicy.mandatory(55,54,true),"installed required version releases gate");
        require(!UpdatePolicy.mandatory(0,54,true),"unknown installation cannot force an update");
        require(!UpdatePolicy.mandatoryField(null)&&!UpdatePolicy.mandatoryField(Boolean.FALSE)&&UpdatePolicy.mandatoryField(Boolean.TRUE),"missing metadata defaults to ordinary update");
        for(Object invalid:new Object[]{"true","false",1,0,new Object()}) {
            boolean rejected=false;try{UpdatePolicy.mandatoryField(invalid);}catch(IllegalArgumentException expected){rejected=true;}
            require(rejected,"malformed required flag rejected");
        }
        long now=10_000_000;
        require(UpdatePolicy.automaticDue(now,0,0,false,true),"first launch checks automatically");
        require(UpdatePolicy.automaticDue(now,now-120_000,now-120_000,false,true),"fresh process checks even within normal resume interval");
        require(!UpdatePolicy.automaticDue(now,now-30_000,now-30_000,false,true),"rapid relaunch does not hammer metadata service");
        require(!UpdatePolicy.automaticDue(now,now-120_000,now-120_000,false,false),"ordinary foreground checks are throttled");
        require(UpdatePolicy.automaticDue(now,now-UpdatePolicy.AUTOMATIC_INTERVAL_MS,now-UpdatePolicy.AUTOMATIC_INTERVAL_MS,false,false),"ordinary metadata refreshes after thirty minutes");
        require(UpdatePolicy.automaticDue(now,now-60_000,now-60_000,true,false),"required policy refreshes after a minute so withdrawal is visible");
        require(!UpdatePolicy.automaticDue(now,now-59_999,now-90_000,true,false),"required resume also respects retry throttle");
        require(UpdatePolicy.automaticDue(now,now-60_000,now-120_000,false,false),"failed ordinary checks retry after one minute");
        require(!UpdatePolicy.automaticDue(now,now-59_999,now-120_000,false,false),"failed checks do not retry on every foreground event");
        require(UpdatePolicy.automaticDue(now,now+60_000,now+60_000,false,false),"wall clock rollback permits one fresh check");
        require(UpdatePolicy.otherPackage("cc.huevia","com.nikonpreset.usbprobe"),"a pre-migration server's old-package response cannot provide an update");
        require(!UpdatePolicy.otherPackage("cc.huevia","cc.huevia"),"same-package releases still receive normal validation");
        require(UpdatePolicy.otherPackage("cc.huevia","another.app"),"other applications cannot provide an update");
        require(UpdatePolicy.otherPackage("com.nikonpreset.usbprobe","cc.huevia"),"a new install ID cannot update a different installed application");
        require(!UpdatePolicy.otherPackage(null,null),"missing package identities still fail normal validation");
        require(!UpdatePolicy.otherPackage("cc.huevia",""),"an empty identity is not treated as a valid other application");
        require(UpdatePolicy.compatible(35,26)&&UpdatePolicy.compatible(35,35),"supported Android SDK accepted");require(!UpdatePolicy.compatible(25,26)&&!UpdatePolicy.compatible(35,36)&&!UpdatePolicy.compatible(35,0),"unsupported SDK rejected");
        require(UpdatePolicy.percent(0,100)==0&&UpdatePolicy.percent(-1,100)==0&&UpdatePolicy.percent(1,0)==0,"unknown and negative progress bounded");require(UpdatePolicy.percent(51,100)==51&&UpdatePolicy.percent(1000,100)==100,"normal progress bounded at 100");require(UpdatePolicy.percent(Long.MAX_VALUE,Long.MAX_VALUE)==100,"large byte counts do not overflow");
        System.out.println("Update policy: "+checks+" checks passed (host-only).");
    }
    private static void require(boolean value,String name){if(!value)throw new AssertionError(name);checks++;}
}
