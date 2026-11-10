param([string]$JdkRoot='D:/dev/Java/jdk-17.0.19',[string]$AndroidJar='D:/dev/android-sdk/platforms/android-35/android.jar')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$classes=Join-Path $PSScriptRoot '.build/stability184/classes'
New-Item -ItemType Directory -Force -Path $classes|Out-Null
& (Join-Path $JdkRoot 'bin/javac.exe') --release 17 -encoding UTF-8 -cp $AndroidJar -d $classes (Join-Path $root 'app/src/main/java/cc/huevia/AppCrashDiagnostics.java') (Join-Path $PSScriptRoot 'stability-java/cc/huevia/AppCrashDiagnosticsTest.java')
if($LASTEXITCODE -ne 0){throw 'Stability diagnostics host compile failed'}
& (Join-Path $JdkRoot 'bin/java.exe') '-Dfile.encoding=UTF-8' -cp ($classes+[IO.Path]::PathSeparator+$AndroidJar) cc.huevia.AppCrashDiagnosticsTest
if($LASTEXITCODE -ne 0){throw 'Stability diagnostics host regression failed'}
