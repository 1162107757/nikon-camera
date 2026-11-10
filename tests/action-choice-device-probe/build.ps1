param([string]$SdkRoot='D:/dev/android-sdk',[string]$JdkRoot='D:/dev/Java/jdk-17.0.19')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'));$output=Join-Path $PSScriptRoot '.build'
$classes=Join-Path $output 'classes';$dex=Join-Path $output 'dex';$assets=Join-Path $output 'assets'
foreach($dir in @($classes,$dex,$assets)){New-Item -ItemType Directory -Force -Path $dir|Out-Null}
$android=Join-Path $SdkRoot 'platforms/android-35/android.jar';$tools=Join-Path $SdkRoot 'build-tools/35.0.0';$java=Join-Path $JdkRoot 'bin/java.exe'
function Checked([string]$Exe,[string[]]$Arguments){& $Exe @Arguments;if($LASTEXITCODE -ne 0){throw ('Action choice probe build failed: '+$Exe)}}
$unsigned=Join-Path $output 'unsigned.apk'
Checked (Join-Path $tools 'aapt2.exe') @('link','-I',$android,'-A',$assets,'--manifest',(Join-Path $PSScriptRoot 'AndroidManifest.xml'),'--min-sdk-version','26','--target-sdk-version','35','-o',$unsigned)
$sources=@(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'src') -Filter '*.java' -Recurse|ForEach-Object FullName)
Checked (Join-Path $JdkRoot 'bin/javac.exe') (@('-encoding','UTF-8','-source','17','-target','17','-classpath',$android,'-d',$classes)+$sources)
$jar=Join-Path $output 'probe.jar';Checked (Join-Path $JdkRoot 'bin/jar.exe') @('--create','--file',$jar,'-C',$classes,'.')
Checked $java @('-Xmx256m','-cp',(Join-Path $tools 'lib/d8.jar'),'com.android.tools.r8.D8','--debug','--min-api','26','--lib',$android,'--output',$dex,$jar)
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::Open($unsigned,[IO.Compression.ZipArchiveMode]::Update)
try{foreach($file in Get-ChildItem -LiteralPath $dex -Filter '*.dex'){[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$file.FullName,$file.Name,[IO.Compression.CompressionLevel]::Optimal)|Out-Null}}finally{$archive.Dispose()}
$aligned=Join-Path $output 'aligned.apk';$final=Join-Path $output 'action-choice-probe.apk'
Checked (Join-Path $tools 'zipalign.exe') @('-f','4',$unsigned,$aligned)
Checked $java @('-Xmx128m','-jar',(Join-Path $tools 'lib/apksigner.jar'),'sign','--ks',(Join-Path $root '.tooling/debug.keystore'),'--ks-pass','pass:android','--key-pass','pass:android','--ks-key-alias','androiddebugkey','--out',$final,$aligned)
Write-Output $final
