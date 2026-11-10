param([Parameter(Mandatory=$true)][string]$CandidateApk,[Parameter(Mandatory=$true)][string]$ExpectedApkSha256,[ValidateSet('phone','font-dark','landscape-dark','tablet')][string]$Mode='phone',[string]$Serial='emulator-5588',[string]$Adb='D:/dev/Android/Sdk/platform-tools/adb.exe')
$ErrorActionPreference='Stop';$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
function A([string[]]$Arguments){$prior=$ErrorActionPreference;try{$ErrorActionPreference='Continue';$out=(& $Adb -s $Serial @Arguments 2>&1|Out-String);$code=$LASTEXITCODE}finally{$ErrorActionPreference=$prior};if($code -ne 0){throw $out};return $out.Trim()}
$candidate=[IO.Path]::GetFullPath($CandidateApk);$sha=(Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant();if($sha -ne $ExpectedApkSha256){throw 'APK SHA mismatch'}
if((A @('shell','getprop','ro.hardware')) -notin @('ranchu','goldfish')){throw 'Owned emulator required'}
$base=((A @('shell','pm','path','cc.huevia')) -split "`r?`n"|Where-Object{$_ -match '^package:.*base\.apk$'}|Select-Object -First 1)-replace '^package:','';if(-not $base -or ((A @('shell','sha256sum',$base)) -split '\s+')[0] -ne $sha){throw 'Installed APK differs'}
$run=$Mode+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8);$dest=Join-Path $root ('docs/validation/online-search171/device/'+$sha.Substring(0,8)+'/'+$run);New-Item -ItemType Directory -Force -Path $dest|Out-Null
$size=A @('shell','wm','size');$density=A @('shell','wm','density');$night=A @('shell','cmd','uimode','night');$font=A @('shell','settings','get','system','font_scale');$airplane=A @('shell','settings','get','global','airplane_mode_on');$installed=$false;$mainFailure=$null
try{
 if($Mode -eq 'tablet'){A @('shell','wm','size','1600x2560')|Out-Null;A @('shell','wm','density','240')|Out-Null}else{A @('shell','wm','size',$(if($Mode -eq 'landscape-dark'){'2424x1080'}else{'1080x2424'}))|Out-Null;A @('shell','wm','density','420')|Out-Null}
 A @('shell','cmd','uimode','night',$(if($Mode -match 'dark'){'yes'}else{'no'}))|Out-Null
 A @('shell','am','force-stop','cc.huevia')|Out-Null;A @('shell','settings','put','system','font_scale',$(if($Mode -match 'dark'){'1.3'}else{'1.0'}))|Out-Null;A @('shell','cmd','connectivity','airplane-mode','enable')|Out-Null
 $probe=Join-Path $PSScriptRoot '.build/online-search171-probe.apk';A @('install','-r','-t',$probe)|Out-Null;$installed=$true
 $result=A @('shell','am','instrument','-w','-e','appearance',$(if($Mode -match 'dark'){'dark'}else{'light'}),'-e','runId',$run,'-e','candidateSha256',$sha,'cc.huevia.onlinesearch171qa/.OnlineSearch171Probe');[IO.File]::WriteAllText((Join-Path $dest 'instrumentation.txt'),$result,[Text.UTF8Encoding]::new($false))
 A @('pull',('/sdcard/Android/data/cc.huevia/files/online-search171/'+$run),$dest)|Out-Null
 $report=Get-Content -LiteralPath (Join-Path $dest ($run+'/report.json')) -Raw|ConvertFrom-Json
 Copy-Item -LiteralPath (Join-Path $PSScriptRoot '.build/provenance.json') -Destination (Join-Path $dest 'probe-build.json')
 $proof=[ordered]@{versionCode=171;candidateSha256=$sha;probeSha256=(Get-FileHash -LiteralPath $probe -Algorithm SHA256).Hash.ToLowerInvariant();serial=$Serial;pass=$report.pass;scope=$report.scope;files=@(Get-ChildItem -LiteralPath (Join-Path $dest $run) -File|ForEach-Object{[ordered]@{file=$_.Name;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}})}
 [IO.File]::WriteAllText((Join-Path $dest 'provenance.json'),($proof|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
 if(-not $report.pass){throw ('OnlineSearch171 failed: '+$report.failure+'; '+$dest)}
 Write-Output ('PASS '+$report.checks.Count+' online-search171 checks; '+$dest)
}catch{$mainFailure=$_;throw}finally{
 $errors=[Collections.Generic.List[string]]::new();$cleanup=[ordered]@{displayRestored=$false;nightRestored=$false;fontRestored=$false;airplaneRestored=$false;testPackageRemoved=$false;mainAppStopped=$false;mainFailure=if($mainFailure){$mainFailure.ToString()}else{$null};errors=@()}
 function Cleanup([scriptblock]$Action){try{& $Action}catch{$errors.Add($_.ToString())}}
 Cleanup {$s=[regex]::Match($size,'Override size:\s*(\d+x\d+)');A @('shell','wm','size',$(if($s.Success){$s.Groups[1].Value}else{'reset'}))|Out-Null;$d=[regex]::Match($density,'Override density:\s*(\d+)');A @('shell','wm','density',$(if($d.Success){$d.Groups[1].Value}else{'reset'}))|Out-Null;$cleanup.displayRestored=$true}
 Cleanup {A @('shell','cmd','uimode','night',$(if($night -match 'yes'){'yes'}elseif($night -match 'auto'){'auto'}else{'no'}))|Out-Null;$cleanup.nightRestored=$true}
 Cleanup {if($font -eq 'null'){A @('shell','settings','delete','system','font_scale')|Out-Null}else{A @('shell','settings','put','system','font_scale',$font)|Out-Null};$cleanup.fontRestored=$true}
 Cleanup {A @('shell','cmd','connectivity','airplane-mode',$(if($airplane -eq '1'){'enable'}else{'disable'}))|Out-Null;$cleanup.airplaneRestored=$true}
 if($installed){Cleanup {A @('uninstall','cc.huevia.onlinesearch171qa')|Out-Null;$cleanup.testPackageRemoved=$true}}
 Cleanup {A @('shell','am','force-stop','cc.huevia')|Out-Null;$cleanup.mainAppStopped=$true}
 $cleanup.errors=$errors.ToArray();[IO.File]::WriteAllText((Join-Path $dest 'cleanup.json'),($cleanup|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false));if($errors.Count -gt 0 -and -not $mainFailure){throw 'OnlineSearch171 cleanup incomplete'}
}
