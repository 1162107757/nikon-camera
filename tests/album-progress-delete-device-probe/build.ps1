param([string]$SdkRoot='D:/dev/android-sdk',[string]$JdkRoot='D:/dev/Java/jdk-17.0.19')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$output=Join-Path $PSScriptRoot '.build'
$work=Join-Path $output ([Guid]::NewGuid().ToString('N'))
$classes=Join-Path $work 'classes';$dex=Join-Path $work 'dex'
foreach($directory in @($classes,$dex)){New-Item -ItemType Directory -Force -Path $directory|Out-Null}
$android=Join-Path $SdkRoot 'platforms/android-35/android.jar'
$buildTools=Join-Path $SdkRoot 'build-tools/35.0.0'
function Checked([string]$Executable,[string[]]$Arguments){& $Executable @Arguments;if($LASTEXITCODE -ne 0){throw ('Album progress/delete probe build failed: '+$Executable)}}
$unsigned=Join-Path $work 'unsigned.apk'
Checked (Join-Path $buildTools 'aapt2.exe') @('link','-I',$android,'--manifest',(Join-Path $PSScriptRoot 'AndroidManifest.xml'),'--min-sdk-version','26','--target-sdk-version','35','-o',$unsigned)
$source=Join-Path $PSScriptRoot 'src/cc/huevia/albumlayoutqa/AlbumLayoutProbe.java'
Checked (Join-Path $JdkRoot 'bin/javac.exe') @('-encoding','UTF-8','-source','17','-target','17','-classpath',($android+';'+(Join-Path $root 'app/build/manual/classes')),'-d',$classes,$source)
$jar=Join-Path $work 'probe.jar'
Checked (Join-Path $JdkRoot 'bin/jar.exe') @('--create','--file',$jar,'-C',$classes,'.')
$priorJavaHome=$env:JAVA_HOME
try{$env:JAVA_HOME=$JdkRoot;Checked (Join-Path $buildTools 'd8.bat') @('--debug','--min-api','26','--lib',$android,'--output',$dex,$jar)}finally{$env:JAVA_HOME=$priorJavaHome}
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::Open($unsigned,[IO.Compression.ZipArchiveMode]::Update)
try{foreach($file in Get-ChildItem -LiteralPath $dex -Filter '*.dex'){[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$file.FullName,$file.Name,[IO.Compression.CompressionLevel]::Optimal)|Out-Null}}finally{$archive.Dispose()}
$aligned=Join-Path $work 'aligned.apk';$final=Join-Path $output 'album-layout-probe.apk'
Checked (Join-Path $buildTools 'zipalign.exe') @('-f','4',$unsigned,$aligned)
Checked (Join-Path $JdkRoot 'bin/java.exe') @('-jar',(Join-Path $buildTools 'lib/apksigner.jar'),'sign','--ks',(Join-Path $root '.tooling/debug.keystore'),'--ks-pass','pass:android','--key-pass','pass:android','--ks-key-alias','androiddebugkey','--out',$final,$aligned)
$inputs=@($source,(Join-Path $PSScriptRoot 'AndroidManifest.xml'),$PSCommandPath)|ForEach-Object{[ordered]@{path=[IO.Path]::GetFullPath($_).Substring($root.Length+1).Replace('\','/');sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_).Hash.ToLowerInvariant()}}
[IO.File]::WriteAllText((Join-Path $output 'provenance.json'),([ordered]@{inputs=@($inputs);apkSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $final).Hash.ToLowerInvariant()}|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
Write-Output $final

