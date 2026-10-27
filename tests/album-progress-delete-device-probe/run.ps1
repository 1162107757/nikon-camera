param(
    [Parameter(Mandatory=$true)][string]$CandidateApk,
    [ValidateSet('phone','large-font','rail')][string]$Mode='phone',
    [string]$Adb='D:/dev/Android/Sdk/platform-tools/adb.exe'
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$serial='emulator-5586'; $package='cc.huevia'; $probePackage='cc.huevia.albumlayoutqa'
$candidate=[IO.Path]::GetFullPath($CandidateApk)
if(-not (Test-Path -LiteralPath $candidate -PathType Leaf)){throw 'Candidate APK missing'}
$candidateSha=(Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant()
function AdbText([string[]]$Arguments){$savedPreference=$ErrorActionPreference;try{$ErrorActionPreference='Continue';$value=(& $Adb -s $serial @Arguments 2>&1 | Out-String);$code=$LASTEXITCODE}finally{$ErrorActionPreference=$savedPreference};if($code -ne 0){throw ('ADB failed '+($Arguments -join ' ')+' '+$value)};return $value.Trim()}
function RestoreSetting([string]$Name,[string]$Value){if($Value -eq 'null'){AdbText @('shell','settings','delete','system',$Name)|Out-Null}else{AdbText @('shell','settings','put','system',$Name,$Value)|Out-Null}}
$hardware=AdbText @('shell','getprop','ro.hardware')
if($hardware -notmatch '^(ranchu|goldfish)$'){throw 'Only the owned 5586 emulator may run this probe'}
if((AdbText @('shell','getprop','sys.boot_completed')) -ne '1'){throw 'Emulator not booted'}
$pathLine=AdbText @('shell','pm','path',$package)
$base=($pathLine -split "`r?`n" | Where-Object{$_ -match '^package:.*base\.apk$'} | Select-Object -First 1) -replace '^package:',''
if(-not $base){throw 'No installed candidate'}
$installedSha=((AdbText @('shell','sha256sum',$base)) -split '\s+')[0].ToLowerInvariant()
if($installedSha -ne $candidateSha){throw 'Installed APK does not match the immutable candidate'}
if((AdbText @('shell','dumpsys','package',$package)) -notmatch 'versionCode=100(?:\s|$)'){throw 'Expected versionCode 100'}
$probe=Join-Path $PSScriptRoot '.build/album-layout-probe.apk'
if(-not (Test-Path -LiteralPath $probe)){throw 'Build the independent probe first'}
$priorFont=AdbText @('shell','settings','get','system','font_scale')
$priorSize=AdbText @('shell','wm','size')
$priorAuto=AdbText @('shell','settings','get','system','accelerometer_rotation')
$priorRotation=AdbText @('shell','settings','get','system','user_rotation')
$runId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$Mode+'-'+[Guid]::NewGuid().ToString('N').Substring(0,6)
$destination=Join-Path $root ('docs/validation/album-progress-delete-100/'+$candidateSha.Substring(0,8)+'/'+$runId)
$remote='/sdcard/Android/data/cc.huevia/files/album-layout-qa/'+$runId
New-Item -ItemType Directory -Force -Path $destination | Out-Null
$installed=$false
try {
    AdbText @('shell','am','force-stop',$package)|Out-Null
    AdbText @('shell','wm','size',$(if($Mode -eq 'rail'){'1800x2400'}else{'1080x2424'}))|Out-Null
    AdbText @('shell','settings','put','system','font_scale',$(if($Mode -eq 'large-font'){'1.3'}else{'1.0'}))|Out-Null
    AdbText @('shell','settings','put','system','accelerometer_rotation','0')|Out-Null
    AdbText @('shell','settings','put','system','user_rotation','0')|Out-Null
    AdbText @('install','-r','-t',$probe)|Out-Null; $installed=$true
    $result=AdbText @('shell','am','instrument','-w','-e','mode',$Mode,'-e','runId',$runId,'-e','candidateSha256',$candidateSha,($probePackage+'/.AlbumLayoutProbe'))
    [IO.File]::WriteAllText((Join-Path $destination 'instrumentation.txt'),$result,[Text.UTF8Encoding]::new($false))
    AdbText @('pull',$remote,$destination)|Out-Null
    $reportPath=Join-Path $destination ($runId+'/report.json')
    if(-not (Test-Path -LiteralPath $reportPath)){throw 'Probe report missing'}
    $report=Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    $files=Get-ChildItem -LiteralPath (Split-Path $reportPath) -File | Sort-Object Name | ForEach-Object{[ordered]@{file=$_.Name;bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}}
    $provenance=[ordered]@{candidateApk=$candidate.Replace('\','/');candidateSha256=$candidateSha;versionCode=100;serial=$serial;hardware=$hardware;mode=$Mode;runId=$runId;probeSha256=(Get-FileHash -LiteralPath $probe -Algorithm SHA256).Hash.ToLowerInvariant();scope=$report.scope;files=@($files);pass=[bool]$report.pass}
    [IO.File]::WriteAllText((Join-Path $destination 'provenance.json'),($provenance|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    if(-not $report.pass){throw ('Probe failed '+$report.failure+'; '+$reportPath)}
    Write-Output ('PASS '+$report.checks.Count+' checks; '+$report.screenshots.Count+' screenshots; '+$destination)
} finally {
    $cleanup=[ordered]@{serial=$serial;runId=$runId;testPackageUninstalled=$false;settingsRestored=$false;remoteEvidenceRemoved=$false}
    AdbText @('shell','am','force-stop',$package)|Out-Null
    if($installed){$cleanup.testPackageUninstalled=(AdbText @('uninstall',$probePackage)) -match 'Success'}
    if($priorSize -match 'Override size:\s*(\d+x\d+)'){AdbText @('shell','wm','size',$Matches[1])|Out-Null}else{AdbText @('shell','wm','size','reset')|Out-Null}
    RestoreSetting 'font_scale' $priorFont; RestoreSetting 'accelerometer_rotation' $priorAuto; RestoreSetting 'user_rotation' $priorRotation
    $cleanup.settingsRestored=$true
    if($remote -notmatch '^/sdcard/Android/data/cc\.huevia/files/album-layout-qa/[a-zA-Z0-9.-]+$'){throw 'Unsafe remote evidence path'}
    AdbText @('shell','rm','-r','-f',$remote)|Out-Null; $cleanup.remoteEvidenceRemoved=$true
    [IO.File]::WriteAllText((Join-Path $destination 'cleanup.json'),($cleanup|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
}
