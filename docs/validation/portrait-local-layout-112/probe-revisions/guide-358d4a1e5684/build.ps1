param([string]$SdkRoot='D:/dev/android-sdk',[string]$JdkRoot='D:/dev/Java/jdk-17.0.19')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$output=Join-Path $PSScriptRoot '.build'
$work=Join-Path $output ([Guid]::NewGuid().ToString('N'))
$classes=Join-Path $work 'classes'
$dex=Join-Path $work 'dex'
foreach($directory in @($classes,$dex)){New-Item -ItemType Directory -Force -Path $directory|Out-Null}
$android=Join-Path $SdkRoot 'platforms/android-35/android.jar'
$buildTools=Join-Path $SdkRoot 'build-tools/35.0.0'
$java=Join-Path $JdkRoot 'bin/java.exe'
function Checked([string]$Executable,[string[]]$Arguments){& $Executable @Arguments;if($LASTEXITCODE -ne 0){throw ('Photo tools probe build failed: '+$Executable)}}
$unsigned=Join-Path $work 'unsigned.apk'
Checked (Join-Path $buildTools 'aapt2.exe') @('link','-I',$android,'--manifest',(Join-Path $PSScriptRoot 'AndroidManifest.xml'),'--min-sdk-version','26','--target-sdk-version','35','-o',$unsigned)
$source=@(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'src/cc/huevia/phototoolsqa') -Filter '*.java'|ForEach-Object FullName)
# Compile only against Android. Production symbols are resolved by reflection from the installed APK.
Checked (Join-Path $JdkRoot 'bin/javac.exe') (@('-J-Xmx256m','-encoding','UTF-8','-source','17','-target','17','-classpath',$android,'-d',$classes)+$source)
$jar=Join-Path $work 'probe.jar'
Checked (Join-Path $JdkRoot 'bin/jar.exe') @('--create','--file',$jar,'-C',$classes,'.')
Checked $java @('-Xmx256m','-XX:+UseSerialGC','-cp',(Join-Path $buildTools 'lib/d8.jar'),'com.android.tools.r8.D8','--debug','--min-api','26','--lib',$android,'--output',$dex,$jar)
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::Open($unsigned,[IO.Compression.ZipArchiveMode]::Update)
try{foreach($file in Get-ChildItem -LiteralPath $dex -Filter '*.dex'){[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$file.FullName,$file.Name,[IO.Compression.CompressionLevel]::Optimal)|Out-Null}}finally{$archive.Dispose()}
$aligned=Join-Path $work 'aligned.apk'
$final=Join-Path $output 'photo-tools-probe.apk'
Checked (Join-Path $buildTools 'zipalign.exe') @('-f','4',$unsigned,$aligned)
Checked $java @('-Xmx128m','-jar',(Join-Path $buildTools 'lib/apksigner.jar'),'sign','--ks',(Join-Path $root '.tooling/debug.keystore'),'--ks-pass','pass:android','--key-pass','pass:android','--ks-key-alias','androiddebugkey','--out',$final,$aligned)
Checked $java @('-Xmx128m','-jar',(Join-Path $buildTools 'lib/apksigner.jar'),'verify','--verbose',$final)
$allInputs=@($source)+@((Join-Path $PSScriptRoot 'AndroidManifest.xml'),$PSCommandPath,(Join-Path $PSScriptRoot 'run.ps1'))
$inputs=@($allInputs|ForEach-Object{[ordered]@{path=$_.Substring($root.Length).TrimStart([char[]]'\/').Replace('\','/');sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_).Hash.ToLowerInvariant()}})
$classNames=@(Get-ChildItem -LiteralPath $classes -Filter '*.class' -Recurse|ForEach-Object{$_.FullName.Substring($classes.Length).TrimStart([char[]]'\/').Replace('\','/')})
if(@($classNames|Where-Object{-not $_.StartsWith('cc/huevia/phototoolsqa/')}).Count -gt 0){throw 'Unexpected production classes in probe'}
[IO.File]::WriteAllText((Join-Path $output 'provenance.json'),([ordered]@{inputs=$inputs;classpath='Android API35 only';classes=$classNames;apkSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $final).Hash.ToLowerInvariant()}|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
Write-Output $final
