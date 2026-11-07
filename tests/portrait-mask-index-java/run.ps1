param([string]$JdkHome = 'D:\dev\Java\jdk-17.0.19')
$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$testBuild = Join-Path ([IO.Path]::GetTempPath()) ('huevia-portrait-mask-index-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testBuild | Out-Null
$sources = @('PhotoPortrait.java', 'PortraitPreviewFilter.java', 'SpatialPreviewFilter.java') | ForEach-Object { Join-Path $repository ('app\src\main\java\cc\huevia\ncp\' + $_) }
& (Join-Path $JdkHome 'bin\javac.exe') --release 17 -encoding UTF-8 -d $testBuild $sources (Join-Path $PSScriptRoot 'cc\huevia\ncp\PortraitMaskIndexTest.java')
if ($LASTEXITCODE -ne 0) { throw 'Portrait mask index compilation failed.' }
& (Join-Path $JdkHome 'bin\java.exe') -cp $testBuild cc.huevia.ncp.PortraitMaskIndexTest
if ($LASTEXITCODE -ne 0) { throw 'Portrait mask index checks failed.' }
