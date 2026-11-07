param([string]$JdkHome = 'D:\dev\Java\jdk-17.0.19')
$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$testBuild = Join-Path ([IO.Path]::GetTempPath()) ('huevia-detail-raster-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testBuild | Out-Null
& (Join-Path $JdkHome 'bin\javac.exe') --release 17 -encoding UTF-8 -d $testBuild (Join-Path $repository 'app\src\main\java\cc\huevia\album\PhotoDetailRaster.java') (Join-Path $PSScriptRoot 'stubs\android\graphics\Bitmap.java') (Join-Path $PSScriptRoot 'stubs\android\graphics\Rect.java') (Join-Path $PSScriptRoot 'cc\huevia\album\PhotoDetailRasterTest.java')
if ($LASTEXITCODE -ne 0) { throw 'Detail raster compilation failed.' }
& (Join-Path $JdkHome 'bin\java.exe') -cp $testBuild cc.huevia.album.PhotoDetailRasterTest
if ($LASTEXITCODE -ne 0) { throw 'Detail raster checks failed.' }
