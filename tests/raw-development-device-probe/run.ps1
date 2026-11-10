param(
 [Parameter(Mandatory=$true)][string]$CandidateApk,
 [Parameter(Mandatory=$true)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedApkSha256,
 [ValidateSet('emulator-5586','emulator-5588')][string]$Serial='emulator-5586',
 [string]$Adb='D:/dev/Android/Sdk/platform-tools/adb.exe',
 [string]$SampleNef,
 [switch]$RealEditorOnly,
 [switch]$PerformanceOnly,
 [switch]$AlbumDeleteOnly,
 [ValidateSet('phone','narrow','large-text','landscape')][string]$UiMode='phone'
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if(-not $PSBoundParameters.ContainsKey('SampleNef')){$SampleNef=Join-Path $root '.tooling/raw-native/samples/nikon-z6-lossless-14bit.NEF'}
function A([string[]]$Arguments){$oldPreference=$ErrorActionPreference;try{$ErrorActionPreference='Continue';$text=(& $Adb -s $Serial @Arguments 2>&1|Out-String);$code=$LASTEXITCODE}finally{$ErrorActionPreference=$oldPreference};if($code -ne 0){throw ('RAW probe ADB failed: '+($Arguments -join ' ')+' '+$text)};return $text.Trim()}
function HashText([string]$Text){$hash=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant()}finally{$hash.Dispose()}}
$candidate=[IO.Path]::GetFullPath($CandidateApk);$sha=(Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant();if($sha -ne $ExpectedApkSha256.ToLowerInvariant()){throw 'Frozen APK checksum mismatch'}
$hardware=A @('shell','getprop','ro.hardware');if($hardware -notin @('ranchu','goldfish')){throw 'Owned emulator required'}
if((A @('shell','getprop','sys.boot_completed')) -ne '1'){throw 'Emulator is not booted'}
$base=((A @('shell','pm','path','cc.huevia')) -split "`r?`n"|Where-Object{$_ -match '^package:.*base\.apk$'}|Select-Object -First 1)-replace '^package:',''
if(-not $base -or ((A @('shell','sha256sum',$base)) -split '\s+')[0] -ne $sha){throw 'Installed app is not the frozen candidate'}
$version=[regex]::Match((A @('shell','dumpsys','package','cc.huevia')),'versionCode=(\d+)').Groups[1].Value
$runId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$UiMode+'-'+[Guid]::NewGuid().ToString('N').Substring(0,10)
$remote='/sdcard/Android/data/cc.huevia/files/raw-development-109/'+$runId
$remoteFixture='/sdcard/Android/data/cc.huevia/cache/raw-development-qa/'+$runId
$destination=Join-Path $root ('docs/validation/photo-image-suite/raw-development/'+$sha.Substring(0,8)+'/'+$runId)
New-Item -ItemType Directory -Force -Path $destination|Out-Null
$fontBefore=A @('shell','settings','get','system','font_scale');$airplaneBefore=A @('shell','settings','get','global','airplane_mode_on');$sizeBefore=[regex]::Match((A @('shell','wm','size')),'Override size: (\d+x\d+)').Groups[1].Value;$installed=$false;$sampleSha='';$sampleRemote='';$mainFailure=$null
try{
 A @('shell','settings','put','system','font_scale',$(if($UiMode -eq 'large-text'){'1.3'}else{'1.0'}))|Out-Null
 A @('shell','wm','size',$(if($UiMode -eq 'landscape'){'1890x840'}elseif($UiMode -in @('narrow','large-text')){'840x1890'}else{'reset'}))|Out-Null
 A @('shell','cmd','connectivity','airplane-mode','enable')|Out-Null
 A @('shell','am','force-stop','cc.huevia')|Out-Null
 if($SampleNef -and (Test-Path -LiteralPath $SampleNef -PathType Leaf)){
  $sampleSha=(Get-FileHash -LiteralPath $SampleNef -Algorithm SHA256).Hash.ToLowerInvariant()
  if($sampleSha -ne 'c079345fc93f53a4f0d322f8ddaae505f920c36015f25b58befccaa61db1af31'){throw 'NEF fixture differs from licensed pinned sample'}
  A @('shell','mkdir','-p',$remoteFixture)|Out-Null;$sampleRemote=$remoteFixture+'/sample.NEF';A @('push',$SampleNef,$sampleRemote)|Out-Null
 }
 $probe=Join-Path $PSScriptRoot '.build/raw-development-probe.apk';A @('install','--no-streaming','-r','-t',$probe)|Out-Null;$installed=$true
 $instrumentArgs=@('shell','am','instrument','-w','-e','runId',$runId,'-e','candidateSha256',$sha,'-e','uiMode',$UiMode)
 if($AlbumDeleteOnly){$instrumentArgs+=@('-e','albumDeleteOnly','true')}
 if($PerformanceOnly){$instrumentArgs+=@('-e','performanceOnly','true')}
 if($RealEditorOnly){$instrumentArgs+=@('-e','realEditorOnly','true')}
 if($sampleRemote){$instrumentArgs+=@('-e','sampleNef',$sampleRemote,'-e','sampleNefSha',$sampleSha)}
 $result=A ($instrumentArgs+@('cc.huevia.rawdevelopmentqa/.RawDevelopmentProbe'))
 [IO.File]::WriteAllText((Join-Path $destination 'instrumentation.txt'),$result,[Text.UTF8Encoding]::new($false))
 A @('pull',$remote,$destination)|Out-Null
 $reportPath=Join-Path $destination ($runId+'/report.json');$report=Get-Content -LiteralPath $reportPath -Raw|ConvertFrom-Json
 $proof=[ordered]@{versionCode=$version;candidateSha256=$sha;serial=$Serial;hardware=$hardware;uiMode=$UiMode;probeSha256=(Get-FileHash -LiteralPath $probe -Algorithm SHA256).Hash.ToLowerInvariant();sampleNefSha256=$sampleSha;pass=[bool]$report.pass;scope=$report.scope;files=@(Get-ChildItem -LiteralPath (Split-Path $reportPath) -File|ForEach-Object{[ordered]@{file=$_.Name;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}})}
 [IO.File]::WriteAllText((Join-Path $destination 'provenance.json'),($proof|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
 if(-not $report.pass){throw ('RAW development probe failed: '+$report.failure+'; '+$reportPath)}
 Write-Output ('PASS '+$report.checks.Count+' RAW checks; '+$destination)
}catch{
 $mainFailure=$_
 throw
}finally{
 $cleanupErrors=[Collections.Generic.List[string]]::new()
 $cleanup=[ordered]@{serial=$Serial;testPackageRemoved=$false;fontRestored=$false;sizeRestored=$false;airplaneRestored=$false;remoteFixtureRemoved=$false;privateUniqueFixtureRemoved=$false;remoteEvidenceRetained=$true;mainFailure=if($mainFailure){$mainFailure.ToString()}else{$null};errors=$cleanupErrors}
 function Cleanup([scriptblock]$Operation){try{& $Operation}catch{$cleanupErrors.Add($_.ToString())}}
 Cleanup {A @('shell','am','force-stop','cc.huevia')|Out-Null}
 if($installed){
  Cleanup {
   $appCleanup=A @('shell','am','instrument','-w','-e','cleanupOnly','true','-e','runId',$runId,'cc.huevia.rawdevelopmentqa/.RawDevelopmentProbe')
   [IO.File]::WriteAllText((Join-Path $destination 'cleanup-instrumentation.txt'),$appCleanup,[Text.UTF8Encoding]::new($false))
   if($appCleanup -notmatch 'INSTRUMENTATION_RESULT: pass=true'){throw 'App UID private-fixture cleanup did not confirm success'}
   $cleanup.privateUniqueFixtureRemoved=$true
  }
  Cleanup {A @('uninstall','cc.huevia.rawdevelopmentqa')|Out-Null;$cleanup.testPackageRemoved=$true}
 }
 Cleanup {if($fontBefore -eq 'null'){A @('shell','settings','delete','system','font_scale')|Out-Null}else{A @('shell','settings','put','system','font_scale',$fontBefore)|Out-Null};$cleanup.fontRestored=$true}
 Cleanup {A @('shell','wm','size',$(if($sizeBefore){$sizeBefore}else{'reset'}))|Out-Null;$cleanup.sizeRestored=$true}
 Cleanup {A @('shell','cmd','connectivity','airplane-mode',$(if($airplaneBefore -eq '1'){'enable'}else{'disable'}))|Out-Null;$cleanup.airplaneRestored=$true}
 Cleanup {if($runId -notmatch '^[A-Za-z0-9.-]{8,100}$'){throw 'Unsafe cleanup ID'};A @('shell','rm','-r','-f',$remoteFixture)|Out-Null;$cleanup.remoteFixtureRemoved=$true}
 Cleanup {A @('shell','am','force-stop','cc.huevia')|Out-Null}
 [IO.File]::WriteAllText((Join-Path $destination 'cleanup.json'),($cleanup|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
 if($cleanupErrors.Count -gt 0){if($mainFailure){Write-Output ('Cleanup also reported '+$cleanupErrors.Count+' issue(s); original failure preserved in cleanup.json')}else{throw ('RAW probe cleanup failed: '+($cleanupErrors -join '; '))}}
}
