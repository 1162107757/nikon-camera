param([string]$JdkHome)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $JdkHome) { $JdkHome = Join-Path $root '.tooling/jdk/jdk-17.0.20.1+1' }
$classes = Join-Path $PSScriptRoot '.build/public-internet-host/classes'
New-Item -ItemType Directory -Force -Path $classes | Out-Null
$sources = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'public-internet-host') -Recurse -Filter '*.java' | ForEach-Object FullName)
foreach ($name in @('AccountHttpTransport','AccountRepository','AccountException','AccountJson')) {
    $sources += Join-Path $root ('app/src/main/java/cc/huevia/account/' + $name + '.java')
}
$sources += Join-Path $root 'app/src/main/java/cc/huevia/community/CommunityHttpTransport.java'
$sources += Join-Path $root 'app/src/main/java/cc/huevia/library/SecureHttpClient.java'
$sources += Join-Path $root 'cross-platform/app/android/app/src/main/java/cc/huevia/sharedapp/PublicInternetConnections.java'
& (Join-Path $JdkHome 'bin/javac.exe') '-J-Dfile.encoding=UTF-8' '-J-Duser.language=en' '-J-Duser.country=US' --release 17 -encoding UTF-8 -d $classes @sources
if ($LASTEXITCODE -ne 0) { throw 'Public Internet host compilation failed.' }
& (Join-Path $JdkHome 'bin/java.exe') '-Dfile.encoding=UTF-8' '-Duser.language=en' '-Duser.country=US' -cp $classes cc.huevia.sharedapp.PublicInternetConnectionsTest
if ($LASTEXITCODE -ne 0) { throw 'Public Internet host regression failed.' }
