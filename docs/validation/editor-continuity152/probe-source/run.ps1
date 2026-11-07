param(
    [string]$Adb='D:/dev/Android/Sdk/platform-tools/adb.exe',
    [string]$Serial='emulator-5596',
    [string[]]$Modes=@('phone','font','narrow','landscape','tablet','tablet-landscape','dark'),
    [string]$Candidate='dist/huevia-0.29.1-beta-debug.apk',
    [string]$Scope='editor-continuity152',
    [string]$RestartPhase=''
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$work=Join-Path $root '.tooling/prisma-editor151'
$owner=Get-Content -LiteralPath (Join-Path $work 'emulator-owner.json') -Raw|ConvertFrom-Json
if($Serial -ne $owner.serial -or $Serial -notlike 'emulator-*'){throw 'Only this task-owned emulator is permitted.'}
function Adb151([string[]]$Arguments){
    $oldPreference=$ErrorActionPreference
    try{$ErrorActionPreference='Continue';$result=(& $Adb -s $Serial @Arguments 2>&1|Out-String);$code=$LASTEXITCODE}finally{$ErrorActionPreference=$oldPreference}
    if($code -ne 0){throw ('ADB failed: '+($Arguments -join ' ')+' '+$result)}
    return $result.Trim()
}
if((Adb151 @('shell','getprop','ro.hardware')) -notin @('ranchu','goldfish')){throw 'Emulator hardware required.'}
$candidate=Join-Path $root $Candidate
$candidateSha=(Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant()
$packagePath=(Adb151 @('shell','pm','path','cc.huevia')) -replace '^package:',''
if(((Adb151 @('shell','sha256sum',$packagePath)) -split '\s+')[0] -ne $candidateSha){throw 'Installed APK must match the exact candidate.'}
$fontBefore=Adb151 @('shell','settings','get','system','font_scale')
$nightBefore=Adb151 @('shell','settings','get','secure','ui_night_mode')
$probe=Join-Path $PSScriptRoot '.build/prisma-editor-probe.apk'
$reportRoot=Join-Path $root ('.tooling/'+$Scope+'/native')
New-Item -ItemType Directory -Path $reportRoot -Force|Out-Null
Adb151 @('install','-r','-t',$probe)|Out-Null
try{
    Adb151 @('shell','settings','put','secure','immersive_mode_confirmations','confirmed')|Out-Null
    Adb151 @('shell','cmd','connectivity','airplane-mode','enable')|Out-Null
    foreach($mode in $Modes){
        if($mode -notin @('phone','font','narrow','landscape','tablet','tablet-landscape','dark')){throw ('Unknown mode '+$mode)}
        $size='1170x2532';$density='480';$font='1.0'
        if($mode -eq 'font'){$font='1.3'}
        if($mode -eq 'narrow'){$size='960x1920';$font='1.3'}
        if($mode -eq 'landscape'){$size='2532x1170'}
        if($mode -eq 'tablet'){$size='1600x2560';$density='240'}
        if($mode -eq 'tablet-landscape'){$size='2560x1600';$density='240'}
        Adb151 @('shell','am','force-stop','cc.huevia')|Out-Null
        Adb151 @('shell','wm','size',$size)|Out-Null
        Adb151 @('shell','wm','density',$density)|Out-Null
        Adb151 @('shell','settings','put','system','font_scale',$font)|Out-Null
        Adb151 @('shell','cmd','uimode','night',$(if($mode -eq 'dark'){'yes'}else{'no'}))|Out-Null
        foreach($permission in @('android.permission.READ_MEDIA_IMAGES','android.permission.POST_NOTIFICATIONS')){Adb151 @('shell','pm','grant','cc.huevia',$permission)|Out-Null}
        $runId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$mode+'-'+[Guid]::NewGuid().ToString('N').Substring(0,6)
        $probeArgs=@('shell','am','instrument','-w','-e','runId',$runId,'-e','candidateSha256',$candidateSha,'-e','mode',$mode,'-e','scope',$Scope)
        if($RestartPhase){$probeArgs+=@('-e','restartPhase',$RestartPhase)}
        $probeArgs+='cc.huevia.prismaqa/.PrismaEditorProbe'
        $result=Adb151 $probeArgs
        [IO.File]::WriteAllText((Join-Path $reportRoot ($runId+'.log')),$result,[Text.UTF8Encoding]::new($false))
        Adb151 @('pull',('/sdcard/Android/data/cc.huevia/files/prisma-editor151/'+$runId),$reportRoot)|Out-Null
        $report=Get-Content -LiteralPath (Join-Path $reportRoot ($runId+'/report.json')) -Raw|ConvertFrom-Json
        if(-not $report.pass){throw ($mode+': '+$report.failure+'; evidence '+$runId)}
        Write-Output ($mode+': PASS '+$report.checks.Count+' checks; '+$report.screenshots+' captures; '+$runId)
    }
}finally{
    Adb151 @('shell','am','force-stop','cc.huevia')|Out-Null
    Adb151 @('shell','settings','put','system','font_scale',$(if($fontBefore -eq 'null'){'1.0'}else{$fontBefore}))|Out-Null
    Adb151 @('shell','cmd','uimode','night',$(if($nightBefore -eq '2'){'yes'}else{'no'}))|Out-Null
    Adb151 @('shell','wm','size','reset')|Out-Null
    Adb151 @('shell','wm','density','reset')|Out-Null
    Adb151 @('uninstall','cc.huevia.prismaqa')|Out-Null
}
