param(
    [Parameter(Mandatory=$true)][string]$CandidateApk,
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedApkSha256,
    [Parameter(Mandatory=$true)][string]$CanonicalUrl,
    [ValidateSet('emulator-5586','emulator-5588')][string]$Serial='emulator-5586',
    [string]$ExpectedAvdName='Huevia_Format_102',
    [string]$AdbPath='D:/dev/Android/Sdk/platform-tools/adb.exe',
    [string]$SdkRoot='D:/dev/android-sdk'
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$probePackage='cc.huevia.largedownloadqa'
function Adb([string[]]$Arguments){
    $previousPreference=$ErrorActionPreference
    try{$ErrorActionPreference='Continue';$value=(& $AdbPath -s $Serial @Arguments 2>&1|Out-String);$code=$LASTEXITCODE}
    finally{$ErrorActionPreference=$previousPreference}
    if($code -ne 0){throw ('Large download ADB failed: '+($Arguments[0..([Math]::Min(2,$Arguments.Length-1))] -join ' '))}
    return $value.Trim()
}
if($CanonicalUrl -cnotmatch '^https://(huevia\.cc|nikon-d8girdjsr252fd90e-1252602548\.ap-shanghai\.app\.tcloudbase\.com)/preset-library/releases/[a-f0-9-]{36}/file$'){throw 'Only the canonical public release URL without a query is accepted'}
if(-not(Test-Path -LiteralPath $CandidateApk -PathType Leaf)){throw 'Candidate APK missing'}
$candidateSha=(Get-FileHash -Algorithm SHA256 -LiteralPath $CandidateApk).Hash.ToLowerInvariant()
if($candidateSha -ne $ExpectedApkSha256.ToLowerInvariant()){throw 'Frozen candidate SHA mismatch'}
$candidateBytes=(Get-Item -LiteralPath $CandidateApk).Length
if($candidateBytes -le 4194304 -or $candidateBytes -gt 33554432){throw 'This probe requires a real APK above 4MiB and at most 32MiB'}
$badging=& (Join-Path $SdkRoot 'build-tools/35.0.0/aapt2.exe') dump badging $CandidateApk
if($LASTEXITCODE -ne 0){throw 'Cannot read candidate APK metadata'}
$candidateMetadata=[regex]::Match(($badging -join "`n"),"package: name='([^']+)' versionCode='(\d+)' versionName='([^']*)'")
if(-not $candidateMetadata.Success -or $candidateMetadata.Groups[1].Value -ne 'cc.huevia'){throw 'Candidate package or version metadata invalid'}
$candidateVersionCode=[long]$candidateMetadata.Groups[2].Value
$candidateVersionName=$candidateMetadata.Groups[3].Value
$hardware=Adb @('shell','getprop','ro.hardware')
if($hardware -notin @('ranchu','goldfish')){throw 'Owned emulator hardware required'}
if((Adb @('shell','getprop','sys.boot_completed')) -ne '1'){throw 'Emulator not ready'}
$avdLines=(Adb @('emu','avd','name')) -split "`n"|ForEach-Object{$_.Trim()}
if($ExpectedAvdName -notin $avdLines){throw 'Expected owned AVD does not match'}
$base=((Adb @('shell','pm','path','cc.huevia')) -split "`n"|ForEach-Object{$_.Trim()}|Where-Object{$_ -match '^package:.*base\.apk$'}|Select-Object -First 1)-replace '^package:',''
if(-not $base -or ((Adb @('shell','sha256sum',$base)) -split '\s+')[0] -ne $candidateSha){throw 'Install the exact frozen candidate separately first'}
if((Adb @('shell','pm','list','packages',$probePackage)) -match ('(?m)^package:'+([regex]::Escape($probePackage))+'\s*$')){throw 'Probe package already installed; resolve ownership first'}
$probe=Join-Path $PSScriptRoot '.build/update-large-download-probe.apk'
$buildProvenance=Get-Content -LiteralPath (Join-Path $PSScriptRoot '.build/provenance.json') -Raw|ConvertFrom-Json
if((Get-FileHash -LiteralPath $probe -Algorithm SHA256).Hash.ToLowerInvariant() -ne $buildProvenance.apkSha256){throw 'Probe APK identity mismatch'}
foreach($entry in $buildProvenance.inputs){if((Get-FileHash -LiteralPath (Join-Path $root $entry.path) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.sha256){throw ('Probe source changed after build: '+$entry.path)}}
$runId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)
$destination=Join-Path $root ('docs/validation/update-large-download/'+$candidateSha.Substring(0,8)+'/'+$runId)
if(Test-Path -LiteralPath $destination){throw 'Evidence folder already exists'}
New-Item -ItemType Directory -Path $destination -Force|Out-Null
$remote='/sdcard/Android/data/cc.huevia/files/update-large-download-evidence/'+$runId
$installed=$false
$mainFailure=$null
$successMessage=$null
$cleanupErrors=[System.Collections.Generic.List[string]]::new()
$cleanup=[ordered]@{serial=$Serial;testPackageRemoved=$false;mainAppUninstalled=$false;mainDataCleared=$false;settingsModified=$false;installerStarted=$false;primaryFailure=$null;errors=@()}
try{
    Adb @('install','-r','-t',$probe)|Out-Null
    $installed=$true
    $result=Adb @('shell','am','instrument','-w','-e','runId',$runId,'-e','canonicalUrl',$CanonicalUrl,'-e','candidateSha256',$candidateSha,'-e','candidateVersionCode',[string]$candidateVersionCode,'-e','candidateVersionName',$candidateVersionName,'-e','expectedSha256',$candidateSha,'-e','expectedBytes',[string]$candidateBytes,'-e','expectedVersionCode',[string]$candidateVersionCode,'-e','expectedVersionName',$candidateVersionName,($probePackage+'/.LargeDownloadProbe'))
    [IO.File]::WriteAllText((Join-Path $destination 'instrumentation.txt'),$result,[Text.UTF8Encoding]::new($false))
    Adb @('pull',$remote,$destination)|Out-Null
    $reportDirectory=Join-Path $destination $runId
    $report=Get-Content -LiteralPath (Join-Path $reportDirectory 'report.json') -Raw|ConvertFrom-Json
    if($report.candidateSha256 -ne $candidateSha -or $report.downloadSha256 -ne $candidateSha -or [long]$report.downloadBytes -ne $candidateBytes -or [long]$report.downloadVersionCode -ne $candidateVersionCode -or [string]$report.downloadVersionName -ne $candidateVersionName){throw 'Report candidate identity mismatch'}
    $provenance=[ordered]@{candidateSha256=$candidateSha;versionCode=$candidateVersionCode;versionName=$candidateVersionName;byteLength=$candidateBytes;canonicalUrl=$CanonicalUrl;serial=$Serial;avd=$ExpectedAvdName;probeSha256=$buildProvenance.apkSha256;pass=[bool]$report.pass;scope=$report.scope;reportSha256=(Get-FileHash -LiteralPath (Join-Path $reportDirectory 'report.json') -Algorithm SHA256).Hash.ToLowerInvariant()}
    [IO.File]::WriteAllText((Join-Path $destination 'provenance.json'),($provenance|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
    if(-not $report.pass){throw ('Large download probe failed: '+$report.failure+'; '+(Join-Path $reportDirectory 'report.json'))}
    $successMessage='PASS '+$report.checks.Count+' checks; real DownloadManager; '+$destination
}catch{$mainFailure=$_}
finally{
    if($null -ne $mainFailure){$cleanup.primaryFailure=$mainFailure.ToString()}
    if($installed){try{$cleanup.testPackageRemoved=(Adb @('uninstall',$probePackage)) -match 'Success';if(-not $cleanup.testPackageRemoved){throw 'Instrumentation uninstall did not report Success'}}catch{$cleanupErrors.Add('uninstall owned probe: '+$_.Exception.Message)}}
    $cleanup.errors=$cleanupErrors.ToArray()
    [IO.File]::WriteAllText((Join-Path $destination 'cleanup.json'),($cleanup|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
}
if($null -ne $mainFailure){throw $mainFailure}
if($cleanupErrors.Count -gt 0){throw ('Large download cleanup failed; see '+(Join-Path $destination 'cleanup.json'))}
Write-Output $successMessage
