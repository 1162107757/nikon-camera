param(
  [Parameter(Mandatory=$true)][string]$CandidateApk,
  [ValidateSet('1.0','1.3','2.0')][string]$FontScale='1.0',
  [ValidateSet('light','dark')][string]$Theme='light',
  [ValidateSet('on','off')][string]$Motion='on',
  [string]$Adb='D:/dev/Android/Sdk/platform-tools/adb.exe'
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$serial='emulator-5588'
$candidate=[IO.Path]::GetFullPath($CandidateApk)
if(-not (Test-Path -LiteralPath $candidate -PathType Leaf)){throw 'Candidate APK not found'}
$candidateSha=(Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant()
function AdbText([string[]]$Arguments){$result=(& $Adb -s $serial @Arguments 2>&1 | Out-String);if($LASTEXITCODE -ne 0){throw ('ADB failed: '+($Arguments -join ' ')+' '+$result)};return $result.Trim()}
$hardware=AdbText @('shell','getprop','ro.hardware')
if($hardware -notmatch '^(ranchu|goldfish)$'){throw ('Refusing non-owned emulator hardware '+$hardware)}
$boot=AdbText @('shell','getprop','sys.boot_completed')
if($boot -ne '1'){throw 'Emulator is not booted'}
$pathLine=AdbText @('shell','pm','path','cc.huevia')
$base=($pathLine -split "`r?`n" | Where-Object{$_ -match '^package:.*base\.apk$'} | Select-Object -First 1) -replace '^package:',''
if(-not $base){throw 'No installed candidate base APK'}
$installedSha=((AdbText @('shell','sha256sum',$base)) -split '\s+')[0].ToLowerInvariant()
if($installedSha -ne $candidateSha){throw "Installed candidate mismatch expected $candidateSha got $installedSha"}
$versionDump=AdbText @('shell','dumpsys','package','cc.huevia')
if($versionDump -notmatch 'versionCode=105(?:\s|$)'){throw 'Expected candidate versionCode 105'}
$probe=Join-Path $PSScriptRoot '.build/update-loading-probe.apk'
if(-not (Test-Path -LiteralPath $probe -PathType Leaf)){throw 'Build the test package first'}
$runId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-font-'+$FontScale.Replace('.','-')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,6)
$destination=Join-Path $root ('docs/validation/loading-update-105/'+$candidateSha.Substring(0,8)+'/'+$runId)
New-Item -ItemType Directory -Force -Path $destination | Out-Null
$remote='/sdcard/Android/data/cc.huevia/files/update-loading-qa/'+$runId
$installed=$false
$oldAnimator=AdbText @('shell','settings','get','global','animator_duration_scale')
try {
  AdbText @('shell','settings','put','global','animator_duration_scale',$(if($Motion -eq 'off'){'0'}else{'1'}))|Out-Null
  AdbText @('shell','am','force-stop','cc.huevia')|Out-Null
  $install=AdbText @('install','-r','-t',$probe);$installed=$true
  $result=AdbText @('shell','am','instrument','-w','-e','fontScale',$FontScale,'-e','theme',$Theme,'-e','motion',$Motion,'-e','runId',$runId,'-e','candidateSha256',$candidateSha,'cc.huevia.updatevisualqa/.UpdateLoadingProbe')
  [IO.File]::WriteAllText((Join-Path $destination 'instrumentation.txt'),$result,[Text.UTF8Encoding]::new($false))
  $pull=AdbText @('pull',$remote,$destination)
  $reportPath=Join-Path $destination ($runId+'/report.json')
  if(-not (Test-Path -LiteralPath $reportPath -PathType Leaf)){throw 'Probe report missing'}
  $report=Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
  $files=Get-ChildItem -LiteralPath (Split-Path $reportPath) -File | Sort-Object Name | ForEach-Object{[ordered]@{file=$_.Name;bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}}
  $provenance=[ordered]@{candidateApk=[IO.Path]::GetRelativePath($root,$candidate).Replace('\','/');candidateSha256=$candidateSha;versionCode=105;serial=$serial;hardware=$hardware;fontScale=[double]$FontScale;theme=$Theme;motion=$Motion;runId=$runId;probeSha256=(Get-FileHash -LiteralPath $probe -Algorithm SHA256).Hash.ToLowerInvariant();scope='Production CatalogLoadingView animation/lifecycle and UpdatePanel UI with validated synthetic Release and state callbacks; no metadata HTTP, DownloadManager or installer';files=@($files);pass=[bool]$report.pass}
  [IO.File]::WriteAllText((Join-Path $destination 'provenance.json'),($provenance|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
  if(-not $report.pass){throw ('Probe failed: '+$report.failure+'; report '+$reportPath)}
  Write-Output ('PASS '+$report.checks.Count+' checks; '+$report.screenshots.Count+' screenshots; '+$destination)
}
finally {
  if($oldAnimator -eq 'null'){AdbText @('shell','settings','delete','global','animator_duration_scale')|Out-Null}else{AdbText @('shell','settings','put','global','animator_duration_scale',$oldAnimator)|Out-Null}
  $cleanup=[ordered]@{runId=$runId;serial=$serial;testPackageUninstalled=$false;remoteFixtureRemoved=$false}
  if($installed){$uninstall=AdbText @('uninstall','cc.huevia.updatevisualqa');$cleanup.testPackageUninstalled=$uninstall -match 'Success'}
  if($remote -notmatch '^/sdcard/Android/data/cc\.huevia/files/update-loading-qa/[a-zA-Z0-9.-]+$'){throw 'Unsafe remote fixture path'}
  $removed=AdbText @('shell','rm','-r','-f',$remote);$cleanup.remoteFixtureRemoved=$true
  [IO.File]::WriteAllText((Join-Path $destination 'cleanup.json'),($cleanup|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
}
