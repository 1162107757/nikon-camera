param([string]$JdkHome='D:/dev/Java/jdk-17.0.19',[string]$AndroidJar='D:/dev/android-sdk/platforms/android-35/android.jar')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$classes=Join-Path $PSScriptRoot '.build/online-search171/classes'
New-Item -ItemType Directory -Force -Path $classes | Out-Null
$sources=@(Get-ChildItem -LiteralPath (Join-Path $root 'app/src/main/java/cc/huevia/library') -Filter '*.java' | ForEach-Object FullName)
$sources+=Join-Path $root 'app/src/main/java/cc/huevia/ncp/NcpFile.java'
$sources+=Join-Path $PSScriptRoot 'library-java/cc/huevia/library/OnlinePresetSearchTest.java'
& (Join-Path $JdkHome 'bin/javac.exe') --release 17 -encoding UTF-8 -cp $AndroidJar -sourcepath (Join-Path $root 'app/src/main/java') -d $classes @sources
if($LASTEXITCODE -ne 0){throw 'Online search compilation failed'}
& (Join-Path $JdkHome 'bin/java.exe') -cp ($classes+[IO.Path]::PathSeparator+$AndroidJar) cc.huevia.library.OnlinePresetSearchTest
if($LASTEXITCODE -ne 0){throw 'Online search regression failed'}
