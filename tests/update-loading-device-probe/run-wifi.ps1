param(
  [Parameter(Mandatory=$true)][string]$CandidateApk,
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
$wifiStatus=AdbText @('shell','cmd','wifi','status')
if($wifiStatus -notmatch 'Wi-?Fi is (enabled|disabled)'){throw 'Unknown Wi-Fi state'}
$wifiBefore=$Matches[1]
$runId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,6)
$remote='/sdcard/Android/data/cc.huevia/files/wifi-system-105/'+$runId
$destination=Join-Path $root ('docs/validation/loading-update-105/'+$sha.Substring(0,8)+'/wifi-'+$runId)
New-Item -ItemType Directory -Force -Path $destination | Out-Null
$probe=Join-Path $PSScriptRoot '.build/update-loading-probe.apk'
$installed=$false
try {
  AdbText @('shell','svc','wifi','disable')|Out-Null
  Start-Sleep -Milliseconds 750
  AdbText @('shell','am','force-stop','cc.huevia')|Out-Null
  AdbText @('install','-r','-t',$probe)|Out-Null;$installed=$true
  $result=AdbText @('shell','am','instrument','-w','-e','runId',$runId,'-e','candidateSha256',$sha,'cc.huevia.updatevisualqa/.WifiSelectionProbe')
  [IO.File]::WriteAllText((Join-Path $destination 'instrumentation.txt'),$result,[Text.UTF8Encoding]::new($false))
  AdbText @('pull',$remote,$destination)|Out-Null
  $reportPath=Join-Path $destination ($runId+'/report.json')
  $report=Get-Content -LiteralPath $reportPath -Raw|ConvertFrom-Json
  $provenance=[ordered]@{candidateSha256=$sha;versionCode=105;serial=$serial;hardware=$hardware;probeSha256=(Get-FileHash -LiteralPath $probe -Algorithm SHA256).Hash.ToLowerInvariant();scope=$report.scope;pass=[bool]$report.pass;files=@(Get-ChildItem -LiteralPath (Split-Path $reportPath) -File|ForEach-Object{[ordered]@{file=$_.Name;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}})}
  [IO.File]::WriteAllText((Join-Path $destination 'provenance.json'),($provenance|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
  if(-not $report.pass){throw ('Probe failed: '+$report.failure+'; '+$reportPath)}
  Write-Output ('PASS '+$report.checks.Count+' checks; '+$destination)
}
finally {
  AdbText @('shell','am','force-stop','cc.huevia')|Out-Null
  AdbText @('shell','svc','wifi',$(if($wifiBefore -eq 'enabled'){'enable'}else{'disable'}))|Out-Null
  $cleanup=[ordered]@{serial=$serial;wifiRestoredTo=$wifiBefore;testPackageUninstalled=$false;remoteFixtureRemoved=$false}
  if($installed){$cleanup.testPackageUninstalled=(AdbText @('uninstall','cc.huevia.updatevisualqa')) -match 'Success'}
  if($remote -notmatch '^/sdcard/Android/data/cc\.huevia/files/wifi-system-105/[a-zA-Z0-9.-]+$'){throw 'Unsafe fixture path'}
  AdbText @('shell','rm','-r','-f',$remote)|Out-Null;$cleanup.remoteFixtureRemoved=$true
  [IO.File]::WriteAllText((Join-Path $destination 'cleanup.json'),($cleanup|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
}
