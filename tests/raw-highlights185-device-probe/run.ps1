param(
 [Parameter(Mandatory=$true)][string]$CandidateApk,
 [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedApkSha256,
 [ValidateSet('emulator-5584','emulator-5588')][string]$Serial='emulator-5584',
 [string]$Adb='D:/dev/Android/Sdk/platform-tools/adb.exe'
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
function A([string[]]$Arguments){$saved=$ErrorActionPreference;try{$ErrorActionPreference='Continue';$output=(& $Adb -s $Serial @Arguments 2>&1|Out-String);$code=$LASTEXITCODE}finally{$ErrorActionPreference=$saved};if($code -ne 0){throw $output};return $output.Trim()}
$candidate=[IO.Path]::GetFullPath($CandidateApk)
$sha=(Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant()
if($sha -ne $ExpectedApkSha256){throw 'Candidate SHA differs'}
if((A @('shell','getprop','ro.hardware')) -notin @('ranchu','goldfish')){throw 'Owned emulator required'}
if((A @('shell','getprop','sys.boot_completed')) -ne '1'){throw 'Device not ready'}
$base=((A @('shell','pm','path','cc.huevia')) -split "`r?`n"|Where-Object{$_ -match '^package:.*base\.apk$'}|Select-Object -First 1)-replace '^package:',''
if(-not $base -or ((A @('shell','sha256sum',$base))-split '\s+')[0] -ne $sha){throw 'Actual installed APK differs'}
$run=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)
$dest=Join-Path $root ('docs/validation/raw-highlights185/device/'+$sha.Substring(0,8)+'/'+$run)
New-Item -ItemType Directory -Force $dest|Out-Null
$probe=Join-Path $PSScriptRoot '.build/raw-highlights185-probe.apk'
$provenance=Get-Content -Encoding UTF8 (Join-Path $PSScriptRoot '.build/provenance.json') -Raw|ConvertFrom-Json
if((Get-FileHash -LiteralPath $probe -Algorithm SHA256).Hash.ToLowerInvariant() -ne $provenance.probeSha256){throw 'Probe mismatch'}
foreach($file in $provenance.inputs){if((Get-FileHash -LiteralPath (Join-Path $root $file.path) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.sha256){throw 'Probe source changed'}}
$sample=Join-Path $root '.tooling/raw-native/samples/nikon-z6-lossless-14bit.NEF'
if((Get-FileHash -LiteralPath $sample -Algorithm SHA256).Hash.ToLowerInvariant() -ne 'c079345fc93f53a4f0d322f8ddaae505f920c36015f25b58befccaa61db1af31'){throw 'Licensed NEF differs'}
$airplane=A @('shell','settings','get','global','airplane_mode_on');$installed=$false;$mainFailure=$null
try{
 A @('shell','am','force-stop','cc.huevia')|Out-Null
 A @('shell','cmd','connectivity','airplane-mode','enable')|Out-Null
 A @('install','-r','-t',$probe)|Out-Null;$installed=$true
 $result=A @('shell','am','instrument','-w','-e','runId',$run,'-e','candidateSha256',$sha,'cc.huevia.rawhighlights185qa/.RawHighlights185Probe')
 [IO.File]::WriteAllText((Join-Path $dest 'instrumentation.txt'),$result,[Text.UTF8Encoding]::new($false))
 A @('pull',('/sdcard/Android/data/cc.huevia/files/raw-highlights185/'+$run),$dest)|Out-Null
 Copy-Item (Join-Path $PSScriptRoot '.build/provenance.json') (Join-Path $dest 'probe-build.json')
 $report=Get-Content -Encoding UTF8 (Join-Path $dest ($run+'/report.json')) -Raw|ConvertFrom-Json
 if(-not $report.pass){throw ('Probe failed: '+$report.failure)}
 Write-Output ('PASS RAW diagnostic matrix; '+$dest)
}catch{$mainFailure=$_.ToString();throw}finally{
 $errors=[Collections.Generic.List[string]]::new()
 foreach($command in @(@('shell','am','force-stop','cc.huevia'),@('shell','cmd','connectivity','airplane-mode',$(if($airplane -eq '1'){'enable'}else{'disable'})))){try{A $command|Out-Null}catch{$errors.Add($_.ToString())}}
 if($installed){try{A @('uninstall','cc.huevia.rawhighlights185qa')|Out-Null}catch{$errors.Add($_.ToString())}}
 [ordered]@{mainFailure=$mainFailure;errors=@($errors);appOwnedFixtureCleanup=$report.fixtureCleanup;testPackageRemoved=$installed;airplaneRestored=$true}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $dest 'cleanup.json')
 if($errors.Count -gt 0 -and -not $mainFailure){throw 'Probe cleanup failed'}
}
