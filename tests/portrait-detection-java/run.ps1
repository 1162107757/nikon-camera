param(
    [string]$SdkRoot='D:/dev/android-sdk',
    [string]$JdkRoot='D:/dev/Java/jdk-17.0.19'
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$androidJar=Join-Path $SdkRoot 'platforms/android-35/android.jar'
$output=Join-Path $PSScriptRoot '.build/classes'
if(-not(Test-Path -LiteralPath $androidJar)){throw 'Android API35 android.jar is required.'}
New-Item -ItemType Directory -Force -Path $output | Out-Null
$sources=@(
    (Join-Path $root 'app/src/main/java/cc/huevia/ncp/PhotoPortrait.java'),
    (Join-Path $root 'app/src/main/java/cc/huevia/album/PhotoPortraitDetection.java'),
    (Join-Path $PSScriptRoot 'cc/huevia/album/PortraitDetectionGeometryTest.java')
)
& (Join-Path $JdkRoot 'bin/javac.exe') '-J-Xmx256m' --release 17 -encoding UTF-8 -classpath $androidJar -d $output @sources
if($LASTEXITCODE -ne 0){throw 'Portrait detection geometry compilation failed.'}
& (Join-Path $JdkRoot 'bin/java.exe') '-Xmx128m' '-XX:+UseSerialGC' -classpath ($output+[IO.Path]::PathSeparator+$androidJar) cc.huevia.album.PortraitDetectionGeometryTest
if($LASTEXITCODE -ne 0){throw 'Portrait detection geometry checks failed.'}
