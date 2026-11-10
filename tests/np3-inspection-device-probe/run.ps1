param(
 [Parameter(Mandatory=$true)][string]$CandidateApk,
 [Parameter(Mandatory=$true)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedApkSha256,
 [ValidateSet('phone','dark','narrow','font')][string[]]$Modes=@('phone','dark','narrow','font'),
 [string]$Adb='D:/dev/Android/Sdk/platform-tools/adb.exe'
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'));$serial='emulator-5588'
function A([string[]]$Arguments){$oldPreference=$ErrorActionPreference;try{$ErrorActionPreference='Continue';$text=(& $Adb -s $serial @Arguments 2>&1|Out-String);$code=$LASTEXITCODE}finally{$ErrorActionPreference=$oldPreference};if($code -ne 0){throw ('NP3 ADB failed: '+($Arguments -join ' ')+' '+$text)};return $text.Trim()}
$candidate=[IO.Path]::GetFullPath($CandidateApk);$sha=(Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant();if($sha -ne $ExpectedApkSha256.ToLowerInvariant()){throw 'Frozen candidate hash mismatch'}
if((A @('shell','getprop','ro.hardware')) -notin @('ranchu','goldfish')){throw 'Only owned emulator-5588 permitted'}
$base=((A @('shell','pm','path','cc.huevia')) -split "`r?`n"|Where-Object{$_ -match '^package:.*base\.apk$'}|Select-Object -First 1)-replace '^package:',''
if(-not $base -or ((A @('shell','sha256sum',$base)) -split '\s+')[0] -ne $sha){throw 'Installed APK does not match frozen candidate'}
$runId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)
$destination=Join-Path $root ('docs/validation/np3-inspection160/'+$sha.Substring(0,8)+'/'+$runId);New-Item -ItemType Directory -Force -Path $destination|Out-Null
$font=A @('shell','settings','get','system','font_scale');$airplane=A @('shell','settings','get','global','airplane_mode_on');$size=A @('shell','wm','size')
$before=[ordered]@{fontScale=$font;airplane=$airplane;size=$size};$before|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $destination 'device-before.json') -Encoding utf8
$probe=Join-Path $PSScriptRoot '.build/np3-inspection-probe.apk';$reports=@()
try{
 A @('shell','cmd','connectivity','airplane-mode','enable')|Out-Null
 A @('install','--no-streaming','-r','-t',$probe)|Out-Null
 foreach($mode in $Modes){
  A @('shell','am','force-stop','cc.huevia')|Out-Null
  if($mode -eq 'narrow'){A @('shell','wm','size','840x1872')|Out-Null}else{A @('shell','wm','size','1080x2424')|Out-Null}
  A @('shell','settings','put','system','font_scale',$(if($mode -eq 'font'){'1.3'}else{'1.0'}))|Out-Null
  $text=A @('shell','am','instrument','-w','-e','mode',$mode,'-e','runId',$runId,'-e','apkSha256',$sha,'cc.huevia.np3inspectionqa/.Np3InspectionProbe')
  [IO.File]::WriteAllText((Join-Path $destination ($mode+'-instrumentation.txt')),$text,[Text.UTF8Encoding]::new($false))
  A @('pull',('/sdcard/Android/data/cc.huevia/files/np3-inspection160/'+$runId+'/'+$mode),$destination)|Out-Null
  $report=Get-Content -LiteralPath (Join-Path $destination ($mode+'/report.json')) -Raw|ConvertFrom-Json
  if(-not $report.pass -or $text -notmatch 'PASS \d+ NP3 device checks'){throw ('NP3 '+$mode+' failed: '+$report.failure+' '+$text)}
  $reports+=([ordered]@{mode=$mode;pass=$true;checks=$report.checks.Count;apkSha256=$report.apkSha256})
  Write-Output ('PASS '+$mode+': '+$report.checks.Count+' checks')
 }
 $np3Total=0;foreach($item in $reports){$np3Total+=[int]$item.checks}
 $proof=[ordered]@{pass=$true;runId=$runId;candidateSha256=$sha;versionCode=160;serial=$serial;probeSha256=(Get-FileHash -LiteralPath $probe -Algorithm SHA256).Hash.ToLowerInvariant();modes=$reports;totalChecks=$np3Total;scope='Installed APK, generated NP3, real parameter-entry touch and dialog; offline owned emulator only.'}
 $proof|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $destination 'summary.json') -Encoding utf8
 Write-Output $destination
}finally{
 A @('shell','am','force-stop','cc.huevia')|Out-Null
 A @('shell','settings','put','system','font_scale',$font)|Out-Null
 if($size -match 'Override size:\s*(\d+x\d+)'){A @('shell','wm','size',$Matches[1])|Out-Null}else{A @('shell','wm','size','reset')|Out-Null}
 A @('shell','cmd','connectivity','airplane-mode',$(if($airplane -eq '1'){'enable'}else{'disable'}))|Out-Null
 A @('uninstall','cc.huevia.np3inspectionqa')|Out-Null
}
