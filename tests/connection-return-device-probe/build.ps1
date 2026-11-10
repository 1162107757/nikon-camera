param([string]$SdkRoot='D:/dev/android-sdk',[string]$JdkRoot='D:/dev/Java/jdk-17.0.19')
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$output=Join-Path $PSScriptRoot '.build'
$work=Join-Path $output ([Guid]::NewGuid().ToString('N'))
$classes=Join-Path $work 'classes';$dex=Join-Path $work 'dex';$assets=Join-Path $work 'assets'
foreach($directory in @($classes,$dex,$assets)){New-Item -ItemType Directory -Force -Path $directory|Out-Null}
$sourceAsset=Join-Path $projectRoot 'docs/design-review/remote-capture-20261024/assets/live-view.png'
Copy-Item -LiteralPath $sourceAsset -Destination (Join-Path $assets 'live-view.png')
$androidJar=Join-Path $SdkRoot 'platforms/android-35/android.jar'
$tools=Join-Path $SdkRoot 'build-tools/35.0.0'
$appClasses=Join-Path $projectRoot 'app/build/manual/classes'
function Checked([string]$Executable,[string[]]$Arguments){& $Executable @Arguments;if($LASTEXITCODE -ne 0){throw ('Connection return probe build failed: '+$Executable)}}
$unsigned=Join-Path $work 'unsigned.apk'
Checked (Join-Path $tools 'aapt2.exe') @('link','-I',$androidJar,'--manifest',(Join-Path $PSScriptRoot 'AndroidManifest.xml'),'-A',$assets,'--min-sdk-version','26','--target-sdk-version','35','--version-code','1','--version-name','1.0','-o',$unsigned)
$sources=@(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'src') -Recurse -Filter '*.java'|ForEach-Object FullName)+@(Join-Path $projectRoot 'tests/remote-capture-device-probe/src/cc/huevia/remotecaptureqa/FakeNikonPeer.java')
Checked (Join-Path $JdkRoot 'bin/javac.exe') (@('-encoding','UTF-8','-source','17','-target','17','-classpath',($androidJar+';'+$appClasses),'-d',$classes)+$sources)
$jar=Join-Path $work 'probe.jar';Checked (Join-Path $JdkRoot 'bin/jar.exe') @('--create','--file',$jar,'-C',$classes,'.')
$priorJavaHome=$env:JAVA_HOME
try{$env:JAVA_HOME=$JdkRoot;Checked (Join-Path $tools 'd8.bat') @('--debug','--min-api','26','--lib',$androidJar,'--output',$dex,$jar)}finally{$env:JAVA_HOME=$priorJavaHome}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::Open($unsigned,[IO.Compression.ZipArchiveMode]::Update)
try{foreach($file in Get-ChildItem -LiteralPath $dex -Filter '*.dex'){[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$file.FullName,$file.Name,[IO.Compression.CompressionLevel]::Optimal)|Out-Null}}finally{$archive.Dispose()}
$aligned=Join-Path $work 'aligned.apk';$final=Join-Path $output 'connection-return-probe.apk'
Checked (Join-Path $tools 'zipalign.exe') @('-f','4',$unsigned,$aligned)
Checked (Join-Path $JdkRoot 'bin/java.exe') @('-jar',(Join-Path $tools 'lib/apksigner.jar'),'sign','--ks',(Join-Path $projectRoot '.tooling/debug.keystore'),'--ks-pass','pass:android','--key-pass','pass:android','--ks-key-alias','androiddebugkey','--out',$final,$aligned)
$inputs=@($sources+(Join-Path $PSScriptRoot 'AndroidManifest.xml')+$PSCommandPath+(Join-Path $PSScriptRoot 'run.ps1')|ForEach-Object{[ordered]@{path=[IO.Path]::GetRelativePath($projectRoot,$_).Replace('\','/');sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_).Hash.ToLowerInvariant()}})
$provenance=[ordered]@{inputs=$inputs;sampleSource='docs/design-review/remote-capture-20261024/assets/live-view.png';sampleSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $sourceAsset).Hash.ToLowerInvariant();apkSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $final).Hash.ToLowerInvariant()}
[IO.File]::WriteAllText((Join-Path $output 'provenance.json'),($provenance|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
Write-Output $final
