param([string]$Adb='D:/dev/Android/Sdk/platform-tools/adb.exe',[string]$Serial='emulator-5588',[string[]]$Modes=@('phone','font','narrow','dark','tablet','compact','tablet-landscape'),[string]$OutputDirectory,[switch]$CaptureOnly)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if(-not $OutputDirectory){$OutputDirectory=Join-Path $root '.tooling/source-motion150/native'}
New-Item -ItemType Directory -Force -Path $OutputDirectory|Out-Null
$hardware=(& $Adb -s $Serial shell getprop ro.hardware).Trim()
if($Serial -notlike 'emulator-*' -or $hardware -notin @('ranchu','goldfish')){throw 'This fixture runner is restricted to the owned emulator.'}
function Invoke-Adb150([string[]]$Arguments){& $Adb -s $Serial @Arguments;if($LASTEXITCODE -ne 0){throw ('ADB failed: '+($Arguments -join ' '))}}
foreach($mode in $Modes){
    $size='1080x2424';$density='420';$font='1'
    $scale=if($mode -eq 'reduced'){'0'}else{'1'}
    if($mode -eq 'font'){$font='1.3'}
    if($mode -eq 'narrow'){$size='640x1440';$density='320';$font='1.3'}
    if($mode -eq 'tablet'){$size='1600x2560';$density='240'}
    if($mode -eq 'compact'){$size='1920x1080'}
    if($mode -eq 'tablet-landscape'){$size='2560x1600';$density='240'}
    Invoke-Adb150 -Arguments @('shell','am','force-stop','cc.huevia')|Out-Null
    Invoke-Adb150 -Arguments @('shell','pm','clear','cc.huevia')|Out-Null
    Invoke-Adb150 -Arguments @('shell','wm','size',$size)|Out-Null
    Invoke-Adb150 -Arguments @('shell','wm','density',$density)|Out-Null
    Invoke-Adb150 -Arguments @('shell','settings','put','system','font_scale',$font)|Out-Null
    Invoke-Adb150 -Arguments @('shell','settings','put','global','animator_duration_scale',$scale)|Out-Null
    Invoke-Adb150 -Arguments @('shell','pm','grant','cc.huevia','android.permission.READ_MEDIA_IMAGES')|Out-Null
    $log=Join-Path $OutputDirectory ('native-'+$mode+'.log')
    & $Adb -s $Serial shell am instrument -w -e captureOnly ($CaptureOnly.IsPresent.ToString().ToLowerInvariant()) -e mode $mode cc.huevia.syncpolishqa/.SourceMotionProbe > $log
    if($LASTEXITCODE -ne 0){throw ('Instrumentation failed: '+$mode)}
    Invoke-Adb150 -Arguments @('pull',('/sdcard/Android/data/cc.huevia/files/source-motion150/'+$mode),$OutputDirectory)|Out-Null
    $report=Get-Content -LiteralPath (Join-Path $OutputDirectory ($mode+'/report.json')) -Raw -Encoding UTF8|ConvertFrom-Json
    if(-not $report.pass -or -not (Select-String -LiteralPath $log -Pattern 'INSTRUMENTATION_CODE: -1' -Quiet)){throw ($mode+': '+$report.failure)}
    Write-Output ($mode+': PASS '+$report.checks.Count+' assertion executions')
}
