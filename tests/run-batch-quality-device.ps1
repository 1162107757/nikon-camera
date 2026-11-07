param([string]$Adb='D:/dev/Android/Sdk/platform-tools/adb.exe',[string]$Serial='emulator-5588',[string[]]$Modes=@('phone','font','narrow','dark','tablet','compact'),[string]$OutputDirectory,[switch]$AdvancedCopies)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if(-not $OutputDirectory){$OutputDirectory=Join-Path $root '.tooling/batch-quality143'}
New-Item -ItemType Directory -Force -Path $OutputDirectory|Out-Null
$hardware=(& $Adb -s $Serial shell getprop ro.hardware).Trim()
if($Serial -notlike 'emulator-*' -or $hardware -notin @('ranchu','goldfish')){throw 'This destructive fixture runner is restricted to the owned emulator.'}
foreach($mode in $Modes){
    $size='1080x2424';$density='420';$font='1'
    if($mode -eq 'font'){$font='1.3'}
    if($mode -eq 'narrow'){$size='640x1440';$density='320';$font='1.3'}
    if($mode -eq 'tablet'){$size='1600x2560';$density='240'}
    if($mode -eq 'compact'){$size='1920x1080'}
    & $Adb -s $Serial shell am force-stop cc.huevia|Out-Null
    & $Adb -s $Serial shell pm clear cc.huevia|Out-Null
    & $Adb -s $Serial shell wm size $size
    & $Adb -s $Serial shell wm density $density
    & $Adb -s $Serial shell settings put system font_scale $font
    & $Adb -s $Serial shell pm grant cc.huevia android.permission.READ_MEDIA_IMAGES
    & $Adb -s $Serial shell pm grant cc.huevia android.permission.POST_NOTIFICATIONS
    $full=if($mode -eq 'phone'){if($AdvancedCopies){'copies'}else{'true'}}else{'false'}
    $log=Join-Path $OutputDirectory ('native-'+$mode+'.log')
    & $Adb -s $Serial shell am instrument -w -e mode $mode -e full $full cc.huevia.syncpolishqa/.BatchQualityProbe > $log
    if($LASTEXITCODE -ne 0){throw ('Instrumentation failed: '+$mode)}
    & $Adb -s $Serial pull ('/sdcard/Android/data/cc.huevia/files/batch-quality143/'+$mode) $OutputDirectory|Out-Null
    $report=Get-Content -LiteralPath (Join-Path $OutputDirectory ($mode+'/report.json')) -Raw -Encoding UTF8|ConvertFrom-Json
    if(-not $report.pass -or -not (Select-String -LiteralPath $log -Pattern 'INSTRUMENTATION_CODE: -1' -Quiet)){throw ($mode+': '+$report.failure)}
    Write-Output ($mode+': PASS '+$report.checks.Count+' assertion executions')
}
