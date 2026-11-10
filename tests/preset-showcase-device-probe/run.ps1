param([string]$Adb='D:/dev/Android/Sdk/platform-tools/adb.exe',[string]$Serial='emulator-5588',
  [string[]]$Modes=@('phone','font','narrow','landscape','tablet','tablet-landscape','dark'))
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$owner=Join-Path $root '.tooling/four-home154/emulator-handoff.json'
if($Serial -ne 'emulator-5588' -or -not(Test-Path -LiteralPath $owner)){throw 'The explicitly handed-off emulator is required.'}
function Invoke-ShowcaseAdb([string[]]$Arguments){$value=(& $Adb -s $Serial @Arguments | Out-String);if($LASTEXITCODE -ne 0){throw ('ADB failed: '+($Arguments -join ' '))};return $value.Trim()}
if((Invoke-ShowcaseAdb @('shell','getprop','ro.hardware')) -notin @('ranchu','goldfish')){throw 'Owned emulator only.'}
$candidate=Join-Path $root 'dist/huevia-0.30.1-beta-debug.apk'
$sha=(Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant()
$installed=(Invoke-ShowcaseAdb @('shell','pm','path','cc.huevia')) -replace '^package:',''
if(((Invoke-ShowcaseAdb @('shell','sha256sum',$installed)) -split '\s+')[0] -ne $sha){throw 'Installed APK does not match the candidate.'}
Invoke-ShowcaseAdb @('install','-r',(Join-Path $PSScriptRoot '.build/preset-showcase-probe.apk'))|Out-Null
$output=Join-Path $root 'docs/validation/preset-showcase/native'
New-Item -ItemType Directory -Force -Path $output|Out-Null
try{
  foreach($mode in $Modes){
    $size='1080x2424';$density='420';$font='1'
    if($mode -eq 'font'){$font='1.3'}
    if($mode -eq 'narrow'){$size='640x1440';$density='320';$font='1.3'}
    if($mode -eq 'landscape'){$size='1920x1080'}
    if($mode -eq 'tablet'){$size='1600x2560';$density='240'}
    if($mode -eq 'tablet-landscape'){$size='2560x1600';$density='240'}
    Invoke-ShowcaseAdb @('shell','am','force-stop','cc.huevia')|Out-Null
    Invoke-ShowcaseAdb @('shell','pm','clear','cc.huevia')|Out-Null
    Invoke-ShowcaseAdb @('shell','wm','size',$size)|Out-Null
    Invoke-ShowcaseAdb @('shell','wm','density',$density)|Out-Null
    Invoke-ShowcaseAdb @('shell','settings','put','system','font_scale',$font)|Out-Null
    $log=Join-Path $output ('native-'+$mode+'.log')
    & $Adb -s $Serial shell am instrument -w -e mode $mode cc.huevia.showcaseqa/.ShowcaseProbe > $log
    if($LASTEXITCODE -ne 0){throw ('Instrumentation failed: '+$mode)}
    Invoke-ShowcaseAdb @('pull',('/sdcard/Android/data/cc.huevia/files/preset-showcase155/'+$mode),$output)|Out-Null
    $report=Get-Content -LiteralPath (Join-Path $output ($mode+'/report.json')) -Raw -Encoding UTF8|ConvertFrom-Json
    if(-not $report.pass -or -not(Select-String -LiteralPath $log -Pattern '^PASS [0-9]+' -Quiet)){throw ($mode+': '+$report.failure)}
    Write-Output ($mode+': PASS '+$report.checks.Count+' assertion executions')
  }
  [IO.File]::WriteAllText((Join-Path $output 'candidate.json'),([ordered]@{apkSha256=$sha;versionCode=155;modes=$Modes;scope='Preset gallery photography only'}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
}finally{
  Invoke-ShowcaseAdb @('shell','am','force-stop','cc.huevia')|Out-Null
  Invoke-ShowcaseAdb @('shell','wm','size','reset')|Out-Null
  Invoke-ShowcaseAdb @('shell','wm','density','reset')|Out-Null
  Invoke-ShowcaseAdb @('shell','settings','put','system','font_scale','1')|Out-Null
}
