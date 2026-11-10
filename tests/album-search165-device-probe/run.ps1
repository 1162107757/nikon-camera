param(
 [Parameter(Mandatory=$true)][string]$CandidateApk,
 [string]$Serial='emulator-5592',
 [string]$RunId=('album-search165-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')),
 [switch]$VisualOnly,[ValidateSet('system','light','dark')][string]$Appearance='system',
 [string]$Adb='D:/dev/Android/Sdk/platform-tools/adb.exe'
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
function Device([string[]]$Values){$result=& $Adb -s $Serial @Values;if($LASTEXITCODE -ne 0){throw ('adb failed: '+($Values -join ' '))};return $result}
if($Serial -notmatch '^emulator-\d+$' -or $RunId -notmatch '^[A-Za-z0-9.-]{8,100}$'){throw 'Owned emulator and safe unique run id required.'}
$hardware=(Device @('shell','getprop','ro.hardware')).Trim()
if($hardware -notin @('ranchu','goldfish')){throw 'This probe must not run on a physical phone.'}
$sha=(Get-FileHash -LiteralPath $CandidateApk -Algorithm SHA256).Hash.ToLowerInvariant()
$before=Device @('shell','dumpsys','package','cc.huevia')
$previousGrant=($before -join "`n") -match 'android.permission.READ_MEDIA_IMAGES: granted=true'
$probe=Join-Path $PSScriptRoot '.build/album-search165-probe.apk'
$dest=Join-Path $root ('docs/validation/album-search165/'+$RunId)
if(Test-Path -LiteralPath $dest){throw 'Evidence directory already exists; use a fresh RunId.'}
try{
 Device @('install','-r',([IO.Path]::GetFullPath($CandidateApk)))|Out-Null
 Device @('install','-r',$probe)|Out-Null
 $installed=(Device @('shell','pm','path','cc.huevia')|Select-Object -First 1).Trim().Substring(8)
 $actual=((Device @('shell','sha256sum',$installed)) -split '\s+')[0]
 if($actual -ne $sha){throw 'Installed APK hash differs from candidate.'}
 Device @('shell','pm','grant','cc.huevia','android.permission.READ_MEDIA_IMAGES')|Out-Null
 $arguments=@('shell','am','instrument','-w','-e','runId',$RunId,'-e','appearance',$Appearance)
 if($VisualOnly){$arguments+=@('-e','visualOnly','true')}
 $arguments+='cc.huevia.albumsearch165qa/.AlbumSearch165Probe'
 $raw=Device $arguments
 Device @('pull',('/sdcard/Android/data/cc.huevia/files/album-search165/'+$RunId),$dest)|Out-Null
 $raw|Set-Content -LiteralPath (Join-Path $dest 'instrument.txt')
 $report=Get-Content -LiteralPath (Join-Path $dest 'report.json') -Raw|ConvertFrom-Json
 $proof=[ordered]@{candidateSha256=$sha;installedSha256=$actual;probeSha256=(Get-FileHash -LiteralPath $probe -Algorithm SHA256).Hash.ToLowerInvariant();serial=$Serial;versionCode=$report.versionCode;sdk=$report.sdk;pass=$report.pass;visualOnly=[bool]$VisualOnly;appearance=$Appearance}
 [IO.File]::WriteAllText((Join-Path $dest 'provenance.json'),($proof|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
 if(-not $report.pass){throw ('Probe failed: '+$report.failure)}
 Write-Output ($proof|ConvertTo-Json -Compress)
}finally{
 if(-not $previousGrant){Device @('shell','pm','revoke','cc.huevia','android.permission.READ_MEDIA_IMAGES')|Out-Null}
}
