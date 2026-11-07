param([string]$JdkHome='D:/dev/Java/jdk-17.0.19',[string]$AndroidJar='D:/dev/android-sdk/platforms/android-35/android.jar')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$output=Join-Path $PSScriptRoot '.build'
New-Item -ItemType Directory -Force -Path $output|Out-Null
$core=Join-Path $root 'app/src/main/java/cc/huevia'
$sources=@('ptp','picturecontrol','ncp')|ForEach-Object{Get-ChildItem -LiteralPath (Join-Path $core $_) -Filter '*.java'|ForEach-Object FullName}
$sources+=@(Get-ChildItem -LiteralPath (Join-Path $core 'usb') -Filter 'CameraParameter*.java'|ForEach-Object FullName)
$sources+=Join-Path $core 'usb/PresetImportOptions.java'
$sources+=Join-Path $PSScriptRoot '../java/cc/huevia/ncp/NcpCompatibilityFixtures.java'
$sources+=Join-Path $PSScriptRoot '../java/cc/huevia/ncp/Np3PreviewProfileTest.java'
$sources+=Join-Path $PSScriptRoot 'CameraPresetImportTest.java'
# Session integration is compiled and exercised by run-probe; use its already compiled production classes.
$probe=Join-Path $PSScriptRoot '../.build/probe/classes'
& (Join-Path $JdkHome 'bin/javac.exe') --release 17 -encoding UTF-8 -cp ($probe+';'+$AndroidJar) -d $output @sources
if($LASTEXITCODE -ne 0){throw 'Unified preset host compilation failed'}
& (Join-Path $JdkHome 'bin/java.exe') -cp ($output+';'+$probe+';'+$AndroidJar) cc.huevia.usb.CameraPresetImportTest
if($LASTEXITCODE -ne 0){throw 'Unified preset host regression failed'}
