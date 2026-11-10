param([Parameter(Mandatory=$true)][string]$CandidateApk,[Parameter(Mandatory=$true)][string]$ExpectedApkSha256,[string]$Serial='emulator-5588',[string]$Adb='D:/dev/Android/Sdk/platform-tools/adb.exe')
$ErrorActionPreference='Stop';$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
function A([string[]]$Arguments){$prior=$ErrorActionPreference;try{$ErrorActionPreference='Continue';$out=(& $Adb -s $Serial @Arguments 2>&1|Out-String);$code=$LASTEXITCODE}finally{$ErrorActionPreference=$prior};if($code -ne 0){throw $out};return $out.Trim()}
$candidate=[IO.Path]::GetFullPath($CandidateApk);$sha=(Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant();if($sha -ne $ExpectedApkSha256){throw 'APK SHA mismatch'}
if((A @('shell','getprop','ro.hardware')) -notin @('ranchu','goldfish')){throw 'Owned emulator required'}
$base=((A @('shell','pm','path','cc.huevia')) -split "`r?`n"|Where-Object{$_ -match '^package:.*base\.apk$'}|Select-Object -First 1)-replace '^package:','';if(-not $base -or ((A @('shell','sha256sum',$base)) -split '\s+')[0] -ne $sha){throw 'Installed APK differs'}
$run=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8);$dest=Join-Path $root ('docs/validation/camera-capability164/device/'+$sha.Substring(0,8)+'/'+$run);New-Item -ItemType Directory -Force -Path $dest|Out-Null
$font=A @('shell','settings','get','system','font_scale');$airplane=A @('shell','settings','get','global','airplane_mode_on');$installed=$false;$mainFailure=$null
try{
 A @('shell','am','force-stop','cc.huevia')|Out-Null;A @('shell','settings','put','system','font_scale','1.0')|Out-Null;A @('shell','cmd','connectivity','airplane-mode','enable')|Out-Null
 $probe=Join-Path $PSScriptRoot '.build/connection164-probe.apk';A @('install','-r','-t',$probe)|Out-Null;$installed=$true
 $result=A @('shell','am','instrument','-w','-e','runId',$run,'-e','candidateSha256',$sha,'cc.huevia.connection164qa/.Connection164Probe');[IO.File]::WriteAllText((Join-Path $dest 'instrumentation.txt'),$result,[Text.UTF8Encoding]::new($false))
 A @('pull',('/sdcard/Android/data/cc.huevia/files/connection164/'+$run),$dest)|Out-Null
 $report=Get-Content -LiteralPath (Join-Path $dest ($run+'/report.json')) -Raw|ConvertFrom-Json
 Copy-Item -LiteralPath (Join-Path $PSScriptRoot '.build/provenance.json') -Destination (Join-Path $dest 'probe-build.json')
 $proof=[ordered]@{versionCode=164;candidateSha256=$sha;probeSha256=(Get-FileHash -LiteralPath $probe -Algorithm SHA256).Hash.ToLowerInvariant();serial=$Serial;pass=$report.pass;scope=$report.scope;files=@(Get-ChildItem -LiteralPath (Join-Path $dest $run) -File|ForEach-Object{[ordered]@{file=$_.Name;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}})}
 [IO.File]::WriteAllText((Join-Path $dest 'provenance.json'),($proof|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
 if(-not $report.pass){throw ('Connection164 failed: '+$report.failure+'; '+$dest)}
 Write-Output ('PASS '+$report.checks.Count+' connection164 checks; '+$dest)
}catch{$mainFailure=$_;throw}finally{
 $errors=[Collections.Generic.List[string]]::new();$cleanup=[ordered]@{fontRestored=$false;airplaneRestored=$false;testPackageRemoved=$false;mainAppStopped=$false;mainFailure=if($mainFailure){$mainFailure.ToString()}else{$null};errors=@()}
 function Cleanup([scriptblock]$Action){try{& $Action}catch{$errors.Add($_.ToString())}}
 Cleanup {if($font -eq 'null'){A @('shell','settings','delete','system','font_scale')|Out-Null}else{A @('shell','settings','put','system','font_scale',$font)|Out-Null};$cleanup.fontRestored=$true}
 Cleanup {A @('shell','cmd','connectivity','airplane-mode',$(if($airplane -eq '1'){'enable'}else{'disable'}))|Out-Null;$cleanup.airplaneRestored=$true}
 if($installed){Cleanup {A @('uninstall','cc.huevia.connection164qa')|Out-Null;$cleanup.testPackageRemoved=$true}}
 Cleanup {A @('shell','am','force-stop','cc.huevia')|Out-Null;$cleanup.mainAppStopped=$true}
 $cleanup.errors=$errors.ToArray();[IO.File]::WriteAllText((Join-Path $dest 'cleanup.json'),($cleanup|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false));if($errors.Count -gt 0 -and -not $mainFailure){throw 'Connection164 cleanup incomplete'}
}
