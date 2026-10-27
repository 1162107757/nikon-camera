param(
    [Parameter(Mandatory=$true)][string]$CandidateApk,
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedApkSha256,
    [ValidateSet('phone','font1.3','landscape')][string]$Mode='phone',
    [ValidateSet('emulator-5586','emulator-5588')][string]$Serial='emulator-5586',
    [string]$AdbPath='D:/dev/Android/Sdk/platform-tools/adb.exe',
    [string]$SdkRoot='D:/dev/android-sdk'
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$probePackage='cc.huevia.compositiondockqa'
function Adb([string[]]$Arguments){
    $previousPreference=$ErrorActionPreference
    try{$ErrorActionPreference='Continue';$value=(& $AdbPath -s $Serial @Arguments 2>&1|Out-String);$code=$LASTEXITCODE}
    finally{$ErrorActionPreference=$previousPreference}
    if($code -ne 0){throw ('Composition dock ADB failed: '+($Arguments -join ' ')+' '+$value)}
    return $value.Trim()
}
function SettingValue([string]$Value){
    if([string]::IsNullOrWhiteSpace($Value) -or $Value.Trim() -eq 'null'){return '<default>'}
    return $Value.Trim()
}
function RestoreSetting([string]$Namespace,[string]$Name,[string]$Before){
    if((SettingValue $Before) -eq '<default>'){Adb @('shell','settings','delete',$Namespace,$Name)|Out-Null}
    else{Adb @('shell','settings','put',$Namespace,$Name,$Before)|Out-Null}
    $after=Adb @('shell','settings','get',$Namespace,$Name)
    if((SettingValue $after) -ne (SettingValue $Before)){throw ('Setting restoration readback mismatch: '+$Namespace+'/'+$Name)}
    return $after
}
if(-not(Test-Path -LiteralPath $CandidateApk -PathType Leaf)){throw 'Candidate APK missing'}
$candidateSha=(Get-FileHash -Algorithm SHA256 -LiteralPath $CandidateApk).Hash.ToLowerInvariant()
if($candidateSha -ne $ExpectedApkSha256.ToLowerInvariant()){throw 'Frozen candidate SHA mismatch'}
$badging=& (Join-Path $SdkRoot 'build-tools/35.0.0/aapt2.exe') dump badging $CandidateApk
if($LASTEXITCODE -ne 0){throw 'Cannot read candidate APK metadata'}
$candidateMetadata=[regex]::Match(($badging -join "`n"),"package: name='([^']+)' versionCode='(\d+)' versionName='([^']*)'")
if(-not $candidateMetadata.Success -or $candidateMetadata.Groups[1].Value -ne 'cc.huevia'){throw 'Candidate package or version metadata invalid'}
$candidateVersionCode=[long]$candidateMetadata.Groups[2].Value
$candidateVersionName=$candidateMetadata.Groups[3].Value
$hardware=Adb @('shell','getprop','ro.hardware')
if($hardware -notin @('ranchu','goldfish')){throw 'Owned emulator hardware required'}
if((Adb @('shell','getprop','sys.boot_completed')) -ne '1'){throw 'Emulator not ready'}
$base=((Adb @('shell','pm','path','cc.huevia')) -split "`r?`n"|Where-Object{$_ -match '^package:.*base\.apk$'}|Select-Object -First 1)-replace '^package:',''
if(-not $base -or ((Adb @('shell','sha256sum',$base)) -split '\s+')[0] -ne $candidateSha){throw 'Install the exact frozen candidate separately first'}
$package=Adb @('shell','dumpsys','package','cc.huevia')
$installedCode=[regex]::Match($package,'versionCode=(\d+)')
$installedName=[regex]::Match($package,'(?m)^\s*versionName=(.*?)\s*$')
if(-not $installedCode.Success -or -not $installedName.Success -or [long]$installedCode.Groups[1].Value -ne $candidateVersionCode -or $installedName.Groups[1].Value.Trim() -ne $candidateVersionName){throw 'Installed version differs from candidate APK metadata'}
if((Adb @('shell','pm','list','packages',$probePackage)) -match ('(?m)^package:'+([regex]::Escape($probePackage))+'$')){throw 'Composition dock instrumentation package already installed; resolve its ownership before running'}
$probe=Join-Path $PSScriptRoot '.build/composition-dock-probe.apk'
$buildProvenance=Get-Content -LiteralPath (Join-Path $PSScriptRoot '.build/provenance.json') -Raw|ConvertFrom-Json
if((Get-FileHash -LiteralPath $probe -Algorithm SHA256).Hash.ToLowerInvariant() -ne $buildProvenance.apkSha256){throw 'Probe APK identity mismatch'}
foreach($entry in $buildProvenance.inputs){if((Get-FileHash -LiteralPath (Join-Path $root $entry.path) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.sha256){throw ('Probe source changed after build: '+$entry.path)}}
$fontBefore=Adb @('shell','settings','get','system','font_scale')
$accelerometerBefore=Adb @('shell','settings','get','system','accelerometer_rotation')
$rotationBefore=Adb @('shell','settings','get','system','user_rotation')
$airplaneBefore=Adb @('shell','settings','get','global','airplane_mode_on')
$immersiveBefore=Adb @('shell','settings','get','secure','immersive_mode_confirmations')
$runId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$Mode+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)
$destination=Join-Path $root ('docs/validation/composition-dock/'+$candidateSha.Substring(0,8)+'/'+$runId)
if(Test-Path -LiteralPath $destination){throw 'Evidence folder already exists'}
New-Item -ItemType Directory -Path $destination -Force|Out-Null
$remote='/sdcard/Android/data/cc.huevia/files/composition-dock/'+$runId
$installed=$false
$mainFailure=$null
$successMessage=$null
$cleanupErrors=[System.Collections.Generic.List[string]]::new()
function CleanupStep([string]$Name,[scriptblock]$Action){try{& $Action}catch{$cleanupErrors.Add($Name+': '+$_.Exception.Message)}}
try{
    Adb @('shell','cmd','connectivity','airplane-mode','enable')|Out-Null
    Adb @('shell','settings','put','system','font_scale',$(if($Mode -eq 'font1.3'){'1.3'}else{'1.0'}))|Out-Null
    Adb @('shell','settings','put','system','accelerometer_rotation','0')|Out-Null
    Adb @('shell','settings','put','system','user_rotation',$(if($Mode -eq 'landscape'){'1'}else{'0'}))|Out-Null
    Adb @('shell','settings','put','secure','immersive_mode_confirmations','confirmed')|Out-Null
    Adb @('shell','am','force-stop','cc.huevia')|Out-Null
    Adb @('install','-r','-t',$probe)|Out-Null
    $installed=$true
    $result=Adb @('shell','am','instrument','-w','-e','runId',$runId,'-e','candidateSha256',$candidateSha,'-e','expectedVersionCode',[string]$candidateVersionCode,'-e','expectedVersionName',$candidateVersionName,'-e','mode',$Mode,($probePackage+'/.CompositionDockProbe'))
    [IO.File]::WriteAllText((Join-Path $destination 'instrumentation.txt'),$result,[Text.UTF8Encoding]::new($false))
    Adb @('pull',$remote,$destination)|Out-Null
    $reportDirectory=Join-Path $destination $runId
    $report=Get-Content -LiteralPath (Join-Path $reportDirectory 'report.json') -Raw|ConvertFrom-Json
    if($report.apkSha256 -ne $candidateSha -or [long]$report.versionCode -ne $candidateVersionCode -or [string]$report.versionName -ne $candidateVersionName){throw 'Report candidate identity mismatch'}
    $provenance=[ordered]@{candidateSha256=$candidateSha;versionCode=$candidateVersionCode;versionName=$candidateVersionName;serial=$Serial;hardware=$hardware;mode=$Mode;probeSha256=$buildProvenance.apkSha256;pass=[bool]$report.pass;scope=$report.scope;files=@(Get-ChildItem -LiteralPath $reportDirectory -File|ForEach-Object{[ordered]@{file=$_.Name;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}})}
    [IO.File]::WriteAllText((Join-Path $destination 'provenance.json'),($provenance|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    if(-not $report.pass){throw ('Composition dock probe failed: '+$report.failure+'; '+(Join-Path $reportDirectory 'report.json'))}
    $successMessage='PASS '+$report.checks.Count+' checks; '+$report.screenshots+' screenshots; '+$destination
}catch{$mainFailure=$_}
finally{
    $primaryFailureText=$null
    if($null -ne $mainFailure){$primaryFailureText=$mainFailure.ToString()}
    $cleanup=[ordered]@{serial=$Serial;fontScaleBefore=$fontBefore;fontScaleRestored=$false;accelerometerBefore=$accelerometerBefore;accelerometerRestored=$false;rotationBefore=$rotationBefore;rotationRestored=$false;airplaneBefore=$airplaneBefore;airplaneCommandRestored=$false;airplaneSettingRestored=$false;immersiveBefore=$immersiveBefore;immersiveRestored=$false;mainAppStopped=$false;testPackageRemoved=$false;remoteEvidenceRetained=$true;mainAppUninstalled=$false;mainDataCleared=$false;primaryFailure=$primaryFailureText;errors=@()}
    CleanupStep 'force-stop main app' {Adb @('shell','am','force-stop','cc.huevia')|Out-Null;$cleanup.mainAppStopped=$true}
    CleanupStep 'restore font scale' {$cleanup.fontScaleAfter=RestoreSetting 'system' 'font_scale' $fontBefore;$cleanup.fontScaleRestored=$true}
    CleanupStep 'restore accelerometer rotation' {$cleanup.accelerometerAfter=RestoreSetting 'system' 'accelerometer_rotation' $accelerometerBefore;$cleanup.accelerometerRestored=$true}
    CleanupStep 'restore user rotation' {$cleanup.rotationAfter=RestoreSetting 'system' 'user_rotation' $rotationBefore;$cleanup.rotationRestored=$true}
    CleanupStep 'restore airplane command' {Adb @('shell','cmd','connectivity','airplane-mode',$(if($airplaneBefore -eq '1'){'enable'}else{'disable'}))|Out-Null;$cleanup.airplaneCommandRestored=$true}
    CleanupStep 'restore airplane setting' {$cleanup.airplaneAfter=RestoreSetting 'global' 'airplane_mode_on' $airplaneBefore;$cleanup.airplaneSettingRestored=$true}
    CleanupStep 'restore immersive confirmation' {$cleanup.immersiveAfter=RestoreSetting 'secure' 'immersive_mode_confirmations' $immersiveBefore;$cleanup.immersiveRestored=$true}
    if($installed){CleanupStep 'uninstall test package' {$cleanup.testPackageRemoved=(Adb @('uninstall',$probePackage)) -match 'Success';if(-not $cleanup.testPackageRemoved){throw 'Instrumentation uninstall did not report Success'}}}
    $cleanup.errors=$cleanupErrors.ToArray()
    try{[IO.File]::WriteAllText((Join-Path $destination 'cleanup.json'),($cleanup|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))}catch{$cleanupErrors.Add('write cleanup evidence: '+$_.Exception.Message);[Console]::Error.WriteLine('Composition dock cleanup evidence could not be saved: '+$_.Exception.Message)}
}
if($null -ne $mainFailure){if($cleanupErrors.Count -gt 0){[Console]::Error.WriteLine('Cleanup also reported: '+($cleanupErrors -join ' | '))};throw $mainFailure}
if($cleanupErrors.Count -gt 0){throw ('Composition dock cleanup failed: '+($cleanupErrors -join ' | ')+'; '+(Join-Path $destination 'cleanup.json'))}
Write-Output $successMessage
