param([string]$SdkRoot='D:/dev/android-sdk',[string]$JdkRoot='D:/dev/Java/jdk-17.0.19')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$output=Join-Path $PSScriptRoot '.build'
$work=Join-Path $output ([Guid]::NewGuid().ToString('N'))
$classes=Join-Path $work 'classes';$dex=Join-Path $work 'dex';$assets=Join-Path $work 'assets'
foreach($directory in @($classes,$dex,$assets)){New-Item -ItemType Directory -Force -Path $directory|Out-Null}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$corpus=Join-Path $root 'dist/nikon-cloud-recipes-20261018/nikon-cloud-recipes-142.zip'
if((Get-FileHash -LiteralPath $corpus -Algorithm SHA256).Hash.ToLowerInvariant() -ne '7a1cf3cd719ed9ec69dae4936625afb1fc3cc1871bc6d61f46c27903a32a087c'){throw 'Fixed public recipe fixture archive changed'}
$zip=[IO.Compression.ZipFile]::OpenRead($corpus)
try{$entry=$zip.GetEntry('Color Grading/BleachBypass_01a.NP3');if($null -eq $entry){throw 'NP3 fixture missing'};[IO.Compression.ZipFileExtensions]::ExtractToFile($entry,(Join-Path $assets 'supported.np3'))}finally{$zip.Dispose()}
$android=Join-Path $SdkRoot 'platforms/android-35/android.jar'
$buildTools=Join-Path $SdkRoot 'build-tools/35.0.0'
function Checked([string]$Executable,[string[]]$Arguments){& $Executable @Arguments;if($LASTEXITCODE -ne 0){throw ('Online format probe build failed: '+$Executable)}}
$unsigned=Join-Path $work 'unsigned.apk'
Checked (Join-Path $buildTools 'aapt2.exe') @('link','-I',$android,'--manifest',(Join-Path $PSScriptRoot 'AndroidManifest.xml'),'--min-sdk-version','26','--target-sdk-version','35','-A',$assets,'-o',$unsigned)
$source=Join-Path $PSScriptRoot 'src/cc/huevia/onlineformatqa/OnlineFormatProbe.java'
Checked (Join-Path $JdkRoot 'bin/javac.exe') @('-J-Xmx256m','-J-XX:+UseSerialGC','-J-XX:ActiveProcessorCount=2','-encoding','UTF-8','-source','17','-target','17','-classpath',$android,'-d',$classes,$source)
$jar=Join-Path $work 'probe.jar'
Checked (Join-Path $JdkRoot 'bin/jar.exe') @('--create','--file',$jar,'-C',$classes,'.')
Checked (Join-Path $JdkRoot 'bin/java.exe') @('-Xmx256m','-XX:+UseSerialGC','-XX:ActiveProcessorCount=2','-cp',(Join-Path $buildTools 'lib/d8.jar'),'com.android.tools.r8.D8','--debug','--min-api','26','--lib',$android,'--output',$dex,$jar)
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::Open($unsigned,[IO.Compression.ZipArchiveMode]::Update)
try{foreach($file in Get-ChildItem -LiteralPath $dex -Filter '*.dex'){[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$file.FullName,$file.Name,[IO.Compression.CompressionLevel]::Optimal)|Out-Null}}finally{$archive.Dispose()}
$aligned=Join-Path $work 'aligned.apk';$final=Join-Path $output 'online-format-probe.apk'
Checked (Join-Path $buildTools 'zipalign.exe') @('-f','4',$unsigned,$aligned)
Checked (Join-Path $JdkRoot 'bin/java.exe') @('-Xmx128m','-XX:+UseSerialGC','-XX:ActiveProcessorCount=2','-jar',(Join-Path $buildTools 'lib/apksigner.jar'),'sign','--ks',(Join-Path $root '.tooling/debug.keystore'),'--ks-pass','pass:android','--key-pass','pass:android','--ks-key-alias','androiddebugkey','--out',$final,$aligned)
$inputs=@(Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -File | Where-Object{ $_.FullName -notlike ($output+'*') } | Sort-Object FullName | ForEach-Object{[ordered]@{path=$_.FullName.Substring($root.Length+1).Replace('\','/');sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant()}})
[IO.File]::WriteAllText((Join-Path $output 'provenance.json'),([ordered]@{inputs=$inputs;fixtureArchiveSha256='7a1cf3cd719ed9ec69dae4936625afb1fc3cc1871bc6d61f46c27903a32a087c';np3FixtureSha256=(Get-FileHash -LiteralPath (Join-Path $assets 'supported.np3') -Algorithm SHA256).Hash.ToLowerInvariant();apkSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $final).Hash.ToLowerInvariant()}|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
Write-Output $final
