param([ValidateSet('phone','font1.3','landscape','dark')][string]$Mode='phone',[string]$CandidateApk='dist/huevia-0.20.0-beta-debug.apk',[ValidateSet('emulator-5588')][string]$Serial='emulator-5588',[string]$AdbPath='D:/dev/Android/Sdk/platform-tools/adb.exe',[ValidatePattern('^remote-capture-\d+$')][string]$EvidenceGroup='remote-capture-95',[ValidateSet('10','6','4294967295')][string]$VendorId='10',[ValidateSet('full','toolbar','status')][string]$Scope='full')
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$candidate=[IO.Path]::GetFullPath((Join-Path $projectRoot $CandidateApk))
$sha=(Get-FileHash -Algorithm SHA256 -LiteralPath $candidate).Hash.ToLowerInvariant()
$runId=[Guid]::NewGuid().ToString('N')
$evidence=Join-Path $projectRoot ('docs/validation/'+$EvidenceGroup+'/'+$sha.Substring(0,8)+'/'+$Mode+'-vendor'+$VendorId+'-'+$runId.Substring(0,8))
New-Item -ItemType Directory -Force -Path $evidence|Out-Null
function Adb([string[]]$Arguments){$r=& $AdbPath -s $Serial @Arguments;if($LASTEXITCODE -ne 0){throw ('Owned emulator command failed: '+($Arguments -join ' '))};return $r}
function Setting([string]$Name){return((Adb @('shell','settings','get','system',$Name))-join '').Trim()}
function Restore([string]$Name,[string]$Value){if($Value -eq 'null'){Adb @('shell','settings','delete','system',$Name)|Out-Null}else{Adb @('shell','settings','put','system',$Name,$Value)|Out-Null}}
$old=[ordered]@{font_scale=(Setting 'font_scale');accelerometer_rotation=(Setting 'accelerometer_rotation');user_rotation=(Setting 'user_rotation')}
$night=((Adb @('shell','cmd','uimode','night'))-join '').Trim()
if($night -notmatch '^Night mode: (auto|yes|no)$'){throw ('Unexpected night mode: '+$night)}
$oldNight=$Matches[1]
$oldAnimations=[ordered]@{};foreach($key in @('window_animation_scale','transition_animation_scale','animator_duration_scale')){$oldAnimations[$key]=((Adb @('shell','settings','get','global',$key))-join '').Trim()}
$report=$null
try{
    foreach($key in $oldAnimations.Keys){Adb @('shell','settings','put','global',$key,'0')|Out-Null}
    Adb @('shell','settings','put','system','font_scale',$(if($Mode -eq 'font1.3'){'1.3'}else{'1.0'}))|Out-Null
    Adb @('shell','settings','put','system','accelerometer_rotation','0')|Out-Null
    Adb @('shell','settings','put','system','user_rotation',$(if($Mode -eq 'landscape'){'1'}else{'0'}))|Out-Null
    Adb @('shell','cmd','uimode','night',$(if($Mode -eq 'dark'){'yes'}else{'no'}))|Out-Null
    Adb @('shell','am','force-stop','cc.huevia')|Out-Null
    $instrument=Adb @('shell','am','instrument','-w','-r','-e','apkSha256',$sha,'-e','runId',$runId,'-e','mode',$Mode,'-e','evidenceGroup',$EvidenceGroup,'-e','vendorId',$VendorId,'-e','scope',$Scope,'cc.huevia.remotecaptureqa/.RemoteCaptureProbe')
    [IO.File]::WriteAllLines((Join-Path $evidence 'instrumentation.txt'),@($instrument),[Text.UTF8Encoding]::new($false))
    $remote='/sdcard/Android/data/cc.huevia/files/'+$EvidenceGroup+'/'+$runId
    Adb @('pull',$remote,($evidence+'/run'))|Out-Null
    $report=Get-Content -LiteralPath (Join-Path $evidence 'run/report.json') -Raw|ConvertFrom-Json
    if($report.apkSha256 -ne $sha -or $report.status -ne 'PASS'){throw ('Native remote capture failed: '+$report.failure)}
    Write-Output ($Mode+' vendor '+$VendorId+' PASS: '+$report.assertions.Count+' checks; '+$sha)
}finally{
    foreach($key in $oldAnimations.Keys){if($oldAnimations[$key] -eq 'null'){Adb @('shell','settings','delete','global',$key)|Out-Null}else{Adb @('shell','settings','put','global',$key,$oldAnimations[$key])|Out-Null}}
    foreach($name in $old.Keys){Restore $name $old[$name]}
    Adb @('shell','cmd','uimode','night',$oldNight)|Out-Null
    $restored=[ordered]@{};foreach($name in $old.Keys){$restored[$name]=(Setting $name);if($restored[$name] -ne $old[$name]){throw ('Setting not restored: '+$name)}}
    $restoredAnimations=[ordered]@{};foreach($key in $oldAnimations.Keys){$restoredAnimations[$key]=((Adb @('shell','settings','get','global',$key))-join '').Trim();if($restoredAnimations[$key] -ne $oldAnimations[$key]){throw ('Animation setting not restored: '+$key)}}
    $receipt=[ordered]@{serial=$Serial;apkSha256=$sha;runId=$runId;mode=$Mode;vendorId=$VendorId;original=$old;restored=$restored;originalNight=$oldNight;restoredNight=(((Adb @('shell','cmd','uimode','night'))-join '').Trim());originalAnimations=$oldAnimations;restoredAnimations=$restoredAnimations;status=if($report){$report.status}else{'NO_REPORT'}}
    [IO.File]::WriteAllText((Join-Path $evidence 'run-identity.json'),($receipt|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
}
