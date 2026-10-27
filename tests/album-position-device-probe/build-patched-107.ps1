param([string]$SdkRoot='D:/dev/android-sdk',[string]$JdkRoot='D:/dev/Java/jdk-17.0.19')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$work=Join-Path $root '.tooling/album-position-108'
$baseline=Join-Path $root 'dist/huevia-0.21.8-beta-debug.apk'
if((Get-FileHash -LiteralPath $baseline -Algorithm SHA256).Hash.ToLowerInvariant() -ne 'b05fc8e8bbe786b5f41f1bc1998c4bf6649ee329b3413f8ab800c73d6ab3d347'){throw 'Frozen107 APK changed'}
$classes=Join-Path $work ('patched-'+[Guid]::NewGuid().ToString('N'))
Copy-Item -LiteralPath (Join-Path $work 'classes-107') -Destination $classes -Recurse
$dex=Join-Path $classes 'dex-output';New-Item -ItemType Directory -Path $dex|Out-Null
$android=Join-Path $SdkRoot 'platforms/android-35/android.jar';$tools=Join-Path $SdkRoot 'build-tools/35.0.0'
function Checked([string]$File,[string[]]$Arguments){& $File @Arguments;if($LASTEXITCODE -ne 0){throw ('Targeted107 build failed: '+$File)}}
$source=Join-Path $root 'app/src/main/java/cc/huevia/ui/LocalAlbumPanel.java'
Checked (Join-Path $JdkRoot 'bin/javac.exe') @('-J-Xmx256m','-encoding','UTF-8','-source','17','-target','17','-classpath',($android+';'+$classes),'-d',$classes,$source)
$jar=Join-Path $work 'patched-classes.jar'
Checked (Join-Path $JdkRoot 'bin/jar.exe') @('--create','--file',$jar,'-C',$classes,'.')
Checked (Join-Path $JdkRoot 'bin/java.exe') @('-Xmx512m','-cp',(Join-Path $tools 'lib/d8.jar'),'com.android.tools.r8.D8','--debug','--min-api','26','--lib',$android,'--classpath',(Join-Path $root 'app/libs/compile-only/support-fragment-28.0.0.jar'),'--output',$dex,$jar,(Join-Path $root 'app/libs/open_sdk_3.5.19_r9483ffc7_lite.jar'))
$unsigned=Join-Path $work 'patched-unsigned.apk';Copy-Item -LiteralPath $baseline -Destination $unsigned
Add-Type -AssemblyName System.IO.Compression;Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[IO.Compression.ZipFile]::Open($unsigned,[IO.Compression.ZipArchiveMode]::Update)
try{foreach($entry in @($zip.Entries|Where-Object{$_.FullName -match '^classes\d*\.dex$'})){$entry.Delete()};foreach($file in Get-ChildItem -LiteralPath $dex -Filter '*.dex'){[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$file.FullName,$file.Name,[IO.Compression.CompressionLevel]::Optimal)|Out-Null}}finally{$zip.Dispose()}
$aligned=Join-Path $work 'patched-aligned.apk';$final=Join-Path $work 'album-position-patched-107.apk'
Checked (Join-Path $tools 'zipalign.exe') @('-f','4',$unsigned,$aligned)
Checked (Join-Path $JdkRoot 'bin/java.exe') @('-Xmx128m','-jar',(Join-Path $tools 'lib/apksigner.jar'),'sign','--ks',(Join-Path $root '.tooling/debug.keystore'),'--ks-pass','pass:android','--key-pass','pass:android','--ks-key-alias','androiddebugkey','--out',$final,$aligned)
[ordered]@{scope='Isolated107 bytecode baseline plus LocalAlbumPanel only; not unified108 or publishable release';baselineApkSha256=(Get-FileHash -LiteralPath $baseline -Algorithm SHA256).Hash.ToLowerInvariant();sourceSha256=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant();candidateSha256=(Get-FileHash -LiteralPath $final -Algorithm SHA256).Hash.ToLowerInvariant();candidate=$final}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $work 'candidate.json') -Encoding UTF8
Write-Output $final
