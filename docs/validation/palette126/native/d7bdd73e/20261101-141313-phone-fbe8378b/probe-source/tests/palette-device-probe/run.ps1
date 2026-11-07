param(
    [Parameter(Mandatory=$true)][string]$CandidateApk,
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedApkSha256,
    [ValidateSet('phone','font1.3','landscape','animations-off')][string]$Mode='phone',
    [ValidateSet('full','core','ui')][string]$Scope='full',
    [ValidateSet('emulator-5586','emulator-5588')][string]$Serial='emulator-5588',
    [string]$AdbPath='D:/dev/Android/Sdk/platform-tools/adb.exe'
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
function Adb([string[]]$Arguments){
    $previousPreference=$ErrorActionPreference
    try{$ErrorActionPreference='Continue';$value=(& $AdbPath -s $Serial @Arguments 2>&1|Out-String);$code=$LASTEXITCODE}
    finally{$ErrorActionPreference=$previousPreference}
    if($code -ne 0){throw ('Palette ADB failed: '+($Arguments -join ' ')+' '+$value)}
    return $value.Trim()
}
if(-not(Test-Path -LiteralPath $CandidateApk -PathType Leaf)){throw 'Candidate APK missing'}
$candidateSha=(Get-FileHash -Algorithm SHA256 -LiteralPath $CandidateApk).Hash.ToLowerInvariant()
if($candidateSha -ne $ExpectedApkSha256.ToLowerInvariant()){throw 'Frozen candidate SHA mismatch'}
$hardware=Adb @('shell','getprop','ro.hardware')
if($hardware -notin @('ranchu','goldfish')){throw 'Owned emulator hardware required'}
if((Adb @('shell','getprop','sys.boot_completed')) -ne '1'){throw 'Emulator not ready'}
$base=((Adb @('shell','pm','path','cc.huevia')) -split "`r?`n"|Where-Object{$_ -match '^package:.*base\.apk$'}|Select-Object -First 1)-replace '^package:',''
if(-not $base -or ((Adb @('shell','sha256sum',$base)) -split '\s+')[0] -ne $candidateSha){throw 'Install exact candidate separately first'}
$package=Adb @('shell','dumpsys','package','cc.huevia')
$versionMatch=[regex]::Match($package,'versionCode=(\d+)')
if(-not $versionMatch.Success){throw 'Cannot read installed version'}
$fontBefore=Adb @('shell','settings','get','system','font_scale')
$airplaneBefore=Adb @('shell','settings','get','global','airplane_mode_on')
$animatorBefore=Adb @('shell','settings','get','global','animator_duration_scale')
$immersiveBefore=Adb @('shell','settings','get','secure','immersive_mode_confirmations')
$runId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$Mode+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)
$destination=Join-Path $root ('docs/validation/palette126/native/'+$candidateSha.Substring(0,8)+'/'+$runId)
if(Test-Path -LiteralPath $destination){throw 'Evidence folder already exists'}
New-Item -ItemType Directory -Path $destination -Force|Out-Null
$remote='/sdcard/Android/data/cc.huevia/files/palette126/'+$runId
$probe=Join-Path $PSScriptRoot '.build/palette-probe.apk'
$buildProvenance=Get-Content -LiteralPath (Join-Path $PSScriptRoot '.build/provenance.json') -Raw|ConvertFrom-Json
if((Get-FileHash -LiteralPath $probe -Algorithm SHA256).Hash.ToLowerInvariant() -ne $buildProvenance.apkSha256){throw 'Probe APK identity mismatch'}
foreach($entry in $buildProvenance.inputs){if((Get-FileHash -LiteralPath (Join-Path $root $entry.path) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.sha256){throw ('Probe source changed after build: '+$entry.path)}}
$installed=$false
$mainFailure=$null
$successMessage=$null
$probeArchive=Join-Path $destination 'probe-source'
New-Item -ItemType Directory -Force -Path $probeArchive|Out-Null
Copy-Item -LiteralPath $probe -Destination (Join-Path $probeArchive 'probe.apk')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '.build/provenance.json') -Destination (Join-Path $probeArchive 'build-provenance.json')
foreach($probeInput in $buildProvenance.inputs){
    $path=Join-Path $root $probeInput.path
    if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $probeInput.sha256){throw ('Probe input changed since build: '+$probeInput.path)}
    $target=Join-Path $probeArchive $probeInput.path
    New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent)|Out-Null
    Copy-Item -LiteralPath $path -Destination $target
}
$cleanupErrors=[System.Collections.Generic.List[string]]::new()
function CleanupStep([string]$Name,[scriptblock]$Action){
    try{& $Action}catch{$cleanupErrors.Add($Name+': '+$_.Exception.Message)}
}
try{
    Adb @('shell','mkdir','-p','/sdcard/Android/data/cc.huevia/files')|Out-Null
    # Keep Android's first-fullscreen coaching overlay out of native popup accessibility.
    # The exact prior secure-setting value is restored independently in finally.
    Adb @('shell','settings','put','secure','immersive_mode_confirmations','confirmed')|Out-Null
    Adb @('shell','cmd','connectivity','airplane-mode','enable')|Out-Null
    Adb @('shell','settings','put','system','font_scale',$(if($Mode -eq 'font1.3'){'1.3'}else{'1.0'}))|Out-Null
    Adb @('shell','settings','put','global','animator_duration_scale',$(if($Mode -eq 'animations-off'){'0'}else{'1'}))|Out-Null
    Adb @('shell','am','force-stop','cc.huevia')|Out-Null
    Adb @('install','-r','-t',$probe)|Out-Null
    $installed=$true
    $result=Adb @('shell','am','instrument','-w','-e','runId',$runId,'-e','candidateSha256',$candidateSha,'-e','mode',$Mode,'-e','scope',$Scope,'cc.huevia.paletteqa/.PaletteProbe')
    [IO.File]::WriteAllText((Join-Path $destination 'instrumentation.txt'),$result,[Text.UTF8Encoding]::new($false))
    Adb @('pull',$remote,$destination)|Out-Null
    $reportDirectory=Join-Path $destination $runId
    $report=Get-Content -LiteralPath (Join-Path $reportDirectory 'report.json') -Raw|ConvertFrom-Json
    $provenance=[ordered]@{candidateSha256=$candidateSha;versionCode=[long]$versionMatch.Groups[1].Value;serial=$Serial;hardware=$hardware;mode=$Mode;probeSha256=$buildProvenance.apkSha256;pass=[bool]$report.pass;scope=$report.scope;files=@(Get-ChildItem -LiteralPath $reportDirectory -File|ForEach-Object{[ordered]@{file=$_.Name;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}})}
    [IO.File]::WriteAllText((Join-Path $destination 'provenance.json'),($provenance|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    if(-not $report.pass){throw ('Palette probe failed: '+$report.failure+'; '+(Join-Path $reportDirectory 'report.json'))}
    $successMessage='PASS '+$report.checks.Count+' checks; '+$report.screenshots+' screenshots; '+$destination
}catch{
    $mainFailure=$_
}finally{
    $primaryFailureText=$null
    if($null -ne $mainFailure){$primaryFailureText=$mainFailure.ToString()}
    $airplaneDefault=[string]::IsNullOrWhiteSpace($airplaneBefore) -or $airplaneBefore -eq 'null'
    $cleanup=[ordered]@{serial=$Serial;animatorDurationRestoredTo=$animatorBefore;animatorDurationRestored=$false;fontScaleRestoredTo=$fontBefore;fontScaleRestored=$false;airplaneModeRestoredTo=$airplaneBefore;airplaneCommandRestored=$false;airplaneSettingRestored=(-not $airplaneDefault);airplaneModeRestored=$false;immersiveConfirmationRestoredTo=$immersiveBefore;immersiveConfirmationRestored=$false;mainAppStopped=$false;testPackageRemoved=$false;remoteEvidenceRetained=$true;mainAppUninstalled=$false;mainDataCleared=$false;primaryFailure=$primaryFailureText;errors=@()}
    CleanupStep 'force-stop main app' {
        Adb @('shell','am','force-stop','cc.huevia')|Out-Null
        $cleanup.mainAppStopped=$true
    }
    CleanupStep 'restore font scale' {
        if([string]::IsNullOrWhiteSpace($fontBefore) -or $fontBefore -eq 'null'){Adb @('shell','settings','delete','system','font_scale')|Out-Null}else{Adb @('shell','settings','put','system','font_scale',$fontBefore)|Out-Null}
        $cleanup.fontScaleRestored=$true
    }
    CleanupStep 'restore animator duration' {
        if([string]::IsNullOrWhiteSpace($animatorBefore) -or $animatorBefore -eq 'null'){Adb @('shell','settings','delete','global','animator_duration_scale')|Out-Null}else{Adb @('shell','settings','put','global','animator_duration_scale',$animatorBefore)|Out-Null}
    }
    $cleanup.animatorDurationRestored=(Adb @('shell','settings','get','global','animator_duration_scale')) -eq $animatorBefore
    CleanupStep 'restore airplane command' {
        Adb @('shell','cmd','connectivity','airplane-mode',$(if($airplaneBefore -eq '1'){'enable'}else{'disable'}))|Out-Null
        $cleanup.airplaneCommandRestored=$true
    }
    if($airplaneDefault){CleanupStep 'restore default airplane setting' {
        Adb @('shell','settings','delete','global','airplane_mode_on')|Out-Null
        $cleanup.airplaneSettingRestored=$true
    }}
    $cleanup.airplaneModeRestored=$cleanup.airplaneCommandRestored -and $cleanup.airplaneSettingRestored
    CleanupStep 'restore immersive confirmation' {
        if([string]::IsNullOrWhiteSpace($immersiveBefore) -or $immersiveBefore -eq 'null'){Adb @('shell','settings','delete','secure','immersive_mode_confirmations')|Out-Null}else{Adb @('shell','settings','put','secure','immersive_mode_confirmations',$immersiveBefore)|Out-Null}
        $cleanup.immersiveConfirmationRestored=$true
    }
    if($installed){CleanupStep 'uninstall test package' {
        $cleanup.testPackageRemoved=(Adb @('uninstall','cc.huevia.paletteqa')) -match 'Success'
        if(-not $cleanup.testPackageRemoved){throw 'Instrumentation uninstall did not report Success'}
    }}
    $cleanup.errors=$cleanupErrors.ToArray()
    try{[IO.File]::WriteAllText((Join-Path $destination 'cleanup.json'),($cleanup|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))}catch{
        $cleanupErrors.Add('write cleanup evidence: '+$_.Exception.Message)
        [Console]::Error.WriteLine('Palette cleanup evidence could not be saved: '+$_.Exception.Message)
    }
}
if($null -ne $mainFailure){
    if($cleanupErrors.Count -gt 0){[Console]::Error.WriteLine('Cleanup also reported: '+($cleanupErrors -join ' | '))}
    throw $mainFailure
}
if($cleanupErrors.Count -gt 0){throw ('Palette cleanup failed: '+($cleanupErrors -join ' | ')+'; '+(Join-Path $destination 'cleanup.json'))}
Write-Output $successMessage
