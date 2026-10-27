param(
    [Parameter(Mandatory=$true)][string]$CandidateApk,
    [ValidateSet('emulator-5586')][string]$Serial='emulator-5586',
    [string]$SdkRoot='D:\dev\android-sdk',
    [string]$AdbPath='D:\dev\Android\Sdk\platform-tools\adb.exe'
)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$probeApk=Join-Path $PSScriptRoot '.build\detail-load-probe.apk'
$provenancePath=Join-Path $PSScriptRoot '.build\provenance.json'
function Adb([string[]]$Arguments){$value=& $AdbPath -s $Serial @Arguments; if($LASTEXITCODE -ne 0){throw ('Dedicated detail-load probe adb failed: '+($Arguments -join ' '))}; return $value}
if(-not(Test-Path -LiteralPath $CandidateApk -PathType Leaf)){throw 'Candidate APK is missing.'}
if(-not(Test-Path -LiteralPath $probeApk -PathType Leaf)){throw 'Build this standalone probe first.'}
$hardware=((Adb @('shell','getprop','ro.hardware'))-join '').Trim()
if($Serial -ne 'emulator-5586' -or $hardware -notin @('ranchu','goldfish')){throw 'This probe is reserved for emulator-5586 only.'}
$candidateSha=(Get-FileHash -Algorithm SHA256 -LiteralPath $CandidateApk).Hash.ToLowerInvariant()
$runId=[Guid]::NewGuid().ToString('N')
$evidence=Join-Path $projectRoot ('docs\validation\photo-detail-load-94\'+$candidateSha.Substring(0,8)+'\'+$runId)
New-Item -ItemType Directory -Force -Path $evidence|Out-Null
$provenance=Get-Content -LiteralPath $provenancePath -Raw -Encoding UTF8|ConvertFrom-Json
if($provenance.probeApkSha256 -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $probeApk).Hash.ToLowerInvariant()){throw 'Probe APK provenance mismatch.'}
foreach($entry in @(@('probeJavaSha256','src\cc\huevia\detailloadqa\PhotoDetailLoadProbe.java'),@('manifestSha256','AndroidManifest.xml'),@('buildScriptSha256','build.ps1'),@('runScriptSha256','run.ps1'))){
    if($provenance.inputs.($entry[0]) -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $PSScriptRoot $entry[1])).Hash.ToLowerInvariant()){throw ('Probe input changed since build: '+$entry[1])}
}
Copy-Item -LiteralPath $provenancePath -Destination (Join-Path $evidence 'provenance.json')
$environment=[ordered]@{serial=$Serial;hardware=$hardware;candidateApk=[IO.Path]::GetFullPath($CandidateApk);candidateApkSha256=$candidateSha;runId=$runId;startedAtUtc=[DateTime]::UtcNow.ToString('O');scope='Private generated 12 MP JPEG and production codecs/source; no phone, camera, network, account state, gallery publication, or system setting changes.'}
[IO.File]::WriteAllText((Join-Path $evidence 'environment.json'),($environment|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
try{
    Adb @('install','-r',$probeApk)|Out-Null
    $instrumentOutput=& $AdbPath -s $Serial shell am instrument -w -r -e apkSha256 $candidateSha -e runId $runId 'cc.huevia.detailloadqa/.PhotoDetailLoadProbe'
    $instrumentExit=$LASTEXITCODE
    [IO.File]::WriteAllLines((Join-Path $evidence 'instrumentation.txt'),$instrumentOutput,[Text.UTF8Encoding]::new($false))
    $instrumentOutput|Write-Output
    Adb @('pull',('/sdcard/Android/data/cc.huevia/files/photo-detail-load-94/'+$candidateSha.Substring(0,8)+'/'+$runId+'/.'),$evidence)|Out-Null
    if($instrumentExit -ne 0 -or ($instrumentOutput-join "`n") -notmatch 'Photo detail load PASS'){throw 'Detail-load benchmark failed; inspect this run evidence.'}
    $report=Get-Content -LiteralPath (Join-Path $evidence 'report.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if($report.status -ne 'PASS' -or $report.apkSha256 -ne $candidateSha -or -not $report.fixtureCleanup){throw 'Detail-load report/candidate/fixture cleanup mismatch.'}
    Write-Output ('Evidence: '+$evidence)
}finally{
    try{Adb @('uninstall','cc.huevia.detailloadqa')|Out-Null}catch{Write-Warning $_.Exception.Message}
}
