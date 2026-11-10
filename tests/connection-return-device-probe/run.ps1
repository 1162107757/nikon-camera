param([ValidateSet('phone','dark','font1.3','landscape')][string]$Mode='phone')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$adb='D:/dev/Android/Sdk/platform-tools/adb.exe'
$candidateSha=(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $root 'dist/huevia-0.30.2-beta-debug.apk')).Hash.ToLowerInvariant()
function Adb([string[]]$Arguments){$result=& $adb -s emulator-5588 @Arguments;if($LASTEXITCODE -ne 0){throw ('ADB failed: '+($Arguments -join ' '))};return $result}
$oldFont=((Adb @('shell','settings','get','system','font_scale'))-join '').Trim()
$oldRotation=((Adb @('shell','settings','get','system','user_rotation'))-join '').Trim()
$oldAuto=((Adb @('shell','settings','get','system','accelerometer_rotation'))-join '').Trim()
$oldNight=((Adb @('shell','cmd','uimode','night'))-join '').Trim().Replace('Night mode: ','')
$oldSize=(Adb @('shell','wm','size'))-join "`n"
try {
    Adb @('shell','am','force-stop','cc.huevia')|Out-Null
    Adb @('shell','settings','put','system','font_scale',$(if($Mode -eq 'font1.3'){'1.3'}else{'1.0'}))|Out-Null
    Adb @('shell','settings','put','system','accelerometer_rotation','0')|Out-Null
    Adb @('shell','settings','put','system','user_rotation','0')|Out-Null
    Adb @('shell','wm','user-rotation','lock','0')|Out-Null
    if($Mode -eq 'landscape'){Adb @('shell','wm','size','1920x1080')|Out-Null}
    Adb @('shell','cmd','uimode','night',$(if($Mode -eq 'dark'){'yes'}else{'no'}))|Out-Null
    $out=Adb @('shell','am','instrument','-w','-e','mode',$Mode,'-e','candidateSha256',$candidateSha,'cc.huevia.connectionreturnqa/cc.huevia.remotecaptureqa.ConnectionReturnProbe')
    $destination=Join-Path $root ('docs/validation/camera-connection156/'+$Mode)
    New-Item -ItemType Directory -Force -Path $destination|Out-Null
    [IO.File]::WriteAllText((Join-Path $destination 'instrumentation.txt'),($out -join [Environment]::NewLine),[Text.UTF8Encoding]::new($false))
    Adb @('pull',('/sdcard/Android/data/cc.huevia/files/connection-return156/'+$Mode+'/.'),$destination)|Out-Null
    $report=Get-Content (Join-Path $destination 'report.json') -Raw|ConvertFrom-Json
    if(-not $report.pass){throw ($out -join [Environment]::NewLine)}
    Write-Output ($Mode+': PASS ('+$report.checks.Count+' checks)')
} finally {
    Adb @('shell','am','force-stop','cc.huevia')|Out-Null
    foreach($entry in @(@('font_scale',$oldFont),@('user_rotation',$oldRotation),@('accelerometer_rotation',$oldAuto))){
        if($entry[1] -eq 'null'){Adb @('shell','settings','delete','system',$entry[0])|Out-Null}else{Adb @('shell','settings','put','system',$entry[0],$entry[1])|Out-Null}
    }
    Adb @('shell','cmd','uimode','night',$oldNight)|Out-Null
    if($oldAuto -eq '1'){Adb @('shell','wm','user-rotation','free')|Out-Null}else{Adb @('shell','wm','user-rotation','lock',$oldRotation)|Out-Null}
    if($oldSize -match 'Override size:\s*(\d+x\d+)'){Adb @('shell','wm','size',$Matches[1])|Out-Null}else{Adb @('shell','wm','size','reset')|Out-Null}
}
