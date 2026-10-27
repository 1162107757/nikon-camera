param(
    [Parameter(Mandatory=$true)][string]$CandidateApk,
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedApkSha256,
    [ValidateSet('emulator-5586','emulator-5588')][string]$Serial='emulator-5586',
    [string]$AdbPath='D:/dev/Android/Sdk/platform-tools/adb.exe'
)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$probeApk=Join-Path $PSScriptRoot '.build/export-preview-probe.apk'
$provenancePath=Join-Path $PSScriptRoot '.build/provenance.json'
function Adb([string[]]$Arguments){
    $savedPreference=$ErrorActionPreference
    try{$ErrorActionPreference='Continue';$value=(& $AdbPath -s $Serial @Arguments 2>&1|Out-String);$code=$LASTEXITCODE}
    finally{$ErrorActionPreference=$savedPreference}
    if($code -ne 0){throw ('Export preview ADB failed: '+($Arguments -join ' ')+' '+$value)}
    return $value.Trim()
}
if(-not(Test-Path -LiteralPath $CandidateApk -PathType Leaf)){throw 'Candidate APK missing'}
if(-not(Test-Path -LiteralPath $probeApk -PathType Leaf)){throw 'Build standalone probe first'}
$candidateSha=(Get-FileHash -Algorithm SHA256 -LiteralPath $CandidateApk).Hash.ToLowerInvariant()
if($candidateSha -ne $ExpectedApkSha256.ToLowerInvariant()){throw 'Frozen candidate SHA mismatch'}
$hardware=Adb @('shell','getprop','ro.hardware')
if($hardware -notin @('ranchu','goldfish')){throw 'Only owned emulator hardware is allowed'}
if((Adb @('shell','getprop','sys.boot_completed')) -ne '1'){throw 'Emulator is not ready'}
$base=((Adb @('shell','pm','path','cc.huevia')) -split "`r?`n"|Where-Object{$_ -match '^package:.*base\.apk$'}|Select-Object -First 1)-replace '^package:',''
if(-not $base){throw 'Install the frozen candidate app separately first'}
if(((Adb @('shell','sha256sum',$base))-split '\s+')[0] -ne $candidateSha){throw 'Installed APK differs from candidate'}
$provenance=Get-Content -LiteralPath $provenancePath -Raw -Encoding UTF8|ConvertFrom-Json
if($provenance.probeApkSha256 -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $probeApk).Hash.ToLowerInvariant()){throw 'Probe provenance mismatch'}
foreach($entry in @(@('probeJavaSha256','src/cc/huevia/exportpreviewqa/ExportPreviewProbe.java'),@('manifestSha256','AndroidManifest.xml'),@('buildScriptSha256','build.ps1'),@('runScriptSha256','run.ps1'))){
    if($provenance.inputs.($entry[0]) -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $PSScriptRoot $entry[1])).Hash.ToLowerInvariant()){throw ('Probe source changed: '+$entry[1])}
}
$runId=[Guid]::NewGuid().ToString('N')
$evidence=Join-Path $projectRoot ('docs/validation/photo-export-preview/'+$candidateSha.Substring(0,8)+'/'+$runId)
New-Item -ItemType Directory -Force -Path $evidence|Out-Null
Copy-Item -LiteralPath $provenancePath -Destination (Join-Path $evidence 'provenance.json')
$priorAirplane=Adb @('shell','settings','get','global','airplane_mode_on')
$priorFont=Adb @('shell','settings','get','system','font_scale')
$installed=$false
try{
    Adb @('shell','am','force-stop','cc.huevia')|Out-Null
    Adb @('shell','cmd','connectivity','airplane-mode','enable')|Out-Null
    Adb @('shell','settings','put','system','font_scale','1.0')|Out-Null
    Adb @('install','-r',$probeApk)|Out-Null;$installed=$true
    $instrument=Adb @('shell','am','instrument','-w','-r','-e','apkSha256',$candidateSha,'-e','runId',$runId,'cc.huevia.exportpreviewqa/.ExportPreviewProbe')
    [IO.File]::WriteAllText((Join-Path $evidence 'instrumentation.txt'),$instrument,[Text.UTF8Encoding]::new($false))
    Adb @('pull',('/sdcard/Android/data/cc.huevia/files/photo-export-preview/'+$runId+'/.'),$evidence)|Out-Null
    $report=Get-Content -LiteralPath (Join-Path $evidence 'report.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $environment=[ordered]@{serial=$Serial;hardware=$hardware;candidateApk=[IO.Path]::GetFullPath($CandidateApk);candidateSha256=$candidateSha;runId=$runId;probe=$provenance;pass=$report.pass;scope=$report.scope}
    [IO.File]::WriteAllText((Join-Path $evidence 'environment.json'),($environment|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
    if(-not $report.pass -or $report.apkSha256 -ne $candidateSha -or -not $report.fixtureCleanup){throw ('Export preview probe failed; evidence '+$evidence)}
    Write-Output ('PASS '+$report.checks.Count+' checks; '+$report.screenshots.Count+' screenshots; '+$evidence)
}finally{
    $cleanup=[ordered]@{serial=$Serial;runId=$runId;testPackageRemoved=$false;settingsRestored=$false;remoteEvidenceRetained=$true}
    Adb @('shell','am','force-stop','cc.huevia')|Out-Null
    if($installed){$cleanup.testPackageRemoved=(Adb @('uninstall','cc.huevia.exportpreviewqa')) -match 'Success'}
    if($priorFont -eq 'null'){Adb @('shell','settings','delete','system','font_scale')|Out-Null}else{Adb @('shell','settings','put','system','font_scale',$priorFont)|Out-Null}
    Adb @('shell','cmd','connectivity','airplane-mode',$(if($priorAirplane -eq '1'){'enable'}else{'disable'}))|Out-Null
    $cleanup.settingsRestored=$true
    [IO.File]::WriteAllText((Join-Path $evidence 'cleanup.json'),($cleanup|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
}
