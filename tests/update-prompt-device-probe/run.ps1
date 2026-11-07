param(
  [Parameter(Mandatory=$true)][string]$CandidateApk,
  [Parameter(Mandatory=$true)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedApkSha256,
  [Parameter(Mandatory=$true)][ValidateRange(1,2147483647)][int]$ExpectedVersionCode,
  [ValidateSet('emulator-5586','emulator-5588')][string]$Serial='emulator-5586',
  [ValidateSet('1.0','1.3')][string]$FontScale='1.0',
  [string]$Adb='D:/dev/Android/Sdk/platform-tools/adb.exe'
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$candidate=[IO.Path]::GetFullPath($CandidateApk)
if(-not (Test-Path -LiteralPath $candidate -PathType Leaf)){throw 'Candidate APK not found'}
$candidateSha=(Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant()
if($candidateSha -ne $ExpectedApkSha256.ToLowerInvariant()){throw 'Candidate SHA-256 differs from the explicitly expected build'}
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
$versionMatch=[regex]::Match($versionDump,'versionCode=(\d+)')
if(-not $versionMatch.Success -or [int]$versionMatch.Groups[1].Value -ne $ExpectedVersionCode){throw ('Expected candidate versionCode '+$ExpectedVersionCode)}
$probe=Join-Path $PSScriptRoot '.build/update-prompt-probe.apk'
if(-not (Test-Path -LiteralPath $probe -PathType Leaf)){throw 'Build the test package first'}
$compiled=Get-Content -LiteralPath (Join-Path $PSScriptRoot '.build/provenance.json') -Raw | ConvertFrom-Json
$probeSha=(Get-FileHash -LiteralPath $probe -Algorithm SHA256).Hash.ToLowerInvariant()
if($probeSha -ne $compiled.apkSha256){throw 'Compiled probe hash differs from its build record'}
foreach($input in $compiled.inputs){
  $inputPath=Join-Path $root $input.path
  if((Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $input.sha256){throw ('Rebuild stale probe after changing '+$input.path)}
}
$runId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-font-'+$FontScale.Replace('.','-')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,6)
$destination=Join-Path $root ('docs/validation/update-prompt-'+$ExpectedVersionCode+'/'+$candidateSha.Substring(0,8)+'/'+$runId)
New-Item -ItemType Directory -Force -Path $destination | Out-Null
$remote='/sdcard/Android/data/cc.huevia/files/update-prompt-qa/'+$runId
$installed=$false
try {
  $install=AdbText @('install','--no-incremental','-r','-t',$probe);$installed=$true
  $result=AdbText @('shell','am','instrument','-w','-e','fontScale',$FontScale,'-e','runId',$runId,'-e','candidateSha256',$candidateSha,'cc.huevia.updateqa/.UpdatePromptProbe')
  [IO.File]::WriteAllText((Join-Path $destination 'instrumentation.txt'),$result,[Text.UTF8Encoding]::new($false))
  $pull=AdbText @('pull',$remote,$destination)
  $reportPath=Join-Path $destination ($runId+'/report.json')
  if(-not (Test-Path -LiteralPath $reportPath -PathType Leaf)){throw 'Probe report missing'}
  $report=Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
  $files=Get-ChildItem -LiteralPath (Split-Path $reportPath) -File | Sort-Object Name | ForEach-Object{[ordered]@{file=$_.Name;bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}}
  $provenance=[ordered]@{candidateApk=[IO.Path]::GetRelativePath($root,$candidate).Replace('\','/');candidateSha256=$candidateSha;versionCode=$ExpectedVersionCode;serial=$serial;hardware=$hardware;fontScale=[double]$FontScale;runId=$runId;probeSha256=$probeSha;compiledInputs=@($compiled.inputs);scope='Production UpdatePanel component UI with validated synthetic Release and state callbacks; no metadata HTTP, DownloadManager or installer';files=@($files);pass=[bool]$report.pass}
  [IO.File]::WriteAllText((Join-Path $destination 'provenance.json'),($provenance|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
  if(-not $report.pass){throw ('Probe failed: '+$report.failure+'; report '+$reportPath)}
  Write-Output ('PASS '+$report.checks.Count+' checks; '+$report.screenshots.Count+' screenshots; '+$destination)
}
finally {
  $cleanup=[ordered]@{runId=$runId;serial=$serial;testPackageUninstalled=$false;remoteFixtureRemoved=$false}
  if($installed){$uninstall=AdbText @('uninstall','cc.huevia.updateqa');$cleanup.testPackageUninstalled=$uninstall -match 'Success'}
  if($remote -notmatch '^/sdcard/Android/data/cc\.huevia/files/update-prompt-qa/[a-zA-Z0-9.-]+$'){throw 'Unsafe remote fixture path'}
  $removed=AdbText @('shell','rm','-r','-f',$remote);$cleanup.remoteFixtureRemoved=$true
  [IO.File]::WriteAllText((Join-Path $destination 'cleanup.json'),($cleanup|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
}
