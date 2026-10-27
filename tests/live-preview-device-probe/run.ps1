param(
  [Parameter(Mandatory=$true)][string]$CandidateApk,
  [ValidateSet('phone','font1.3','landscape')][string]$Mode='phone',
  [switch]$Baseline,
  [string]$Adb='D:/dev/Android/Sdk/platform-tools/adb.exe'
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$serial='emulator-5588'
function AdbText([string[]]$Arguments){$result=(& $Adb -s $serial @Arguments 2>&1 | Out-String);if($LASTEXITCODE -ne 0){throw ('ADB failed: '+($Arguments -join ' ')+' '+$result)};return $result.Trim()}
$hardware=AdbText @('shell','getprop','ro.hardware')
if($hardware -notmatch '^(ranchu|goldfish)$'){throw 'Owned emulator required'}
$candidate=[IO.Path]::GetFullPath($CandidateApk)
$sha=(Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant()
$base=((AdbText @('shell','pm','path','cc.huevia')) -split "`r?`n" | Where-Object{$_ -match '^package:.*base\.apk$'} | Select-Object -First 1) -replace '^package:',''
if(-not $base -or ((AdbText @('shell','sha256sum',$base)) -split '\s+')[0] -ne $sha){throw 'Installed candidate mismatch'}
$fontBefore=AdbText @('shell','settings','get','system','font_scale')
$runId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$Mode+'-'+[Guid]::NewGuid().ToString('N').Substring(0,6)
$remote='/sdcard/Android/data/cc.huevia/files/live-preview-107/'+$runId
$destination=Join-Path $root ('docs/validation/live-preview-107/'+$sha.Substring(0,8)+'/'+$runId)
New-Item -ItemType Directory -Force -Path $destination|Out-Null
$probe=Join-Path $PSScriptRoot '.build/live-preview-probe.apk'
$installed=$false
try{
  AdbText @('shell','settings','put','system','font_scale',$(if($Mode -eq 'font1.3'){'1.3'}else{'1.0'}))|Out-Null
  AdbText @('shell','am','force-stop','cc.huevia')|Out-Null
  AdbText @('install','-r','-t',$probe)|Out-Null;$installed=$true
  $result=AdbText @('shell','am','instrument','-w','-e','runId',$runId,'-e','candidateSha256',$sha,'-e','mode',$Mode,'-e','baseline',$Baseline.IsPresent.ToString().ToLowerInvariant(),'cc.huevia.livepreviewqa/.LivePreviewProbe')
  [IO.File]::WriteAllText((Join-Path $destination 'instrumentation.txt'),$result,[Text.UTF8Encoding]::new($false))
  AdbText @('pull',$remote,$destination)|Out-Null
  $reportPath=Join-Path $destination ($runId+'/report.json');$report=Get-Content -LiteralPath $reportPath -Raw|ConvertFrom-Json
  $provenance=[ordered]@{candidateSha256=$sha;versionCode=$(if($Baseline){106}else{107});serial=$serial;hardware=$hardware;mode=$Mode;probeSha256=(Get-FileHash -LiteralPath $probe -Algorithm SHA256).Hash.ToLowerInvariant();scope=$report.scope;pass=[bool]$report.pass;files=@(Get-ChildItem -LiteralPath (Split-Path $reportPath) -File|ForEach-Object{[ordered]@{file=$_.Name;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}})}
  [IO.File]::WriteAllText((Join-Path $destination 'provenance.json'),($provenance|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
  if(-not $report.pass){throw ('Probe failed: '+$report.failure+'; '+$reportPath)}
  Write-Output ('PASS '+$report.checks.Count+' checks; '+$destination)
}finally{
  if($fontBefore -eq 'null'){AdbText @('shell','settings','delete','system','font_scale')|Out-Null}else{AdbText @('shell','settings','put','system','font_scale',$fontBefore)|Out-Null}
  AdbText @('shell','am','force-stop','cc.huevia')|Out-Null
  $cleanup=[ordered]@{serial=$serial;fontScaleRestoredTo=$fontBefore;testPackageUninstalled=$false;remoteFixtureRemoved=$false}
  if($installed){$cleanup.testPackageUninstalled=(AdbText @('uninstall','cc.huevia.livepreviewqa')) -match 'Success'}
  if($remote -notmatch '^/sdcard/Android/data/cc\.huevia/files/live-preview-107/[a-zA-Z0-9.-]+$'){throw 'Unsafe fixture path'}
  AdbText @('shell','rm','-r','-f',$remote)|Out-Null;$cleanup.remoteFixtureRemoved=$true
  [IO.File]::WriteAllText((Join-Path $destination 'cleanup.json'),($cleanup|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
}
