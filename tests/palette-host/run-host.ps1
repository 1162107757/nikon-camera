param([string]$JdkRoot='D:/dev/Java/jdk-17.0.19')
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$outputRoot=Join-Path $projectRoot '.tooling/palette126/engine'
[IO.Directory]::CreateDirectory($outputRoot)|Out-Null
$classes=Join-Path $outputRoot 'classes'
$javac=Join-Path $JdkRoot 'bin/javac.exe'
$java=Join-Path $JdkRoot 'bin/java.exe'
$sourceFiles=@(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'app/src/main/java/cc/huevia/ncp') -Filter '*.java' -File|ForEach-Object {$_.FullName})
foreach($name in @('PhotoEditStore','PhotoRecipeStore','PhotoAdjustmentCopy')){$sourceFiles+=Join-Path $projectRoot "app/src/main/java/cc/huevia/album/$name.java"}
foreach($name in @('PaletteLegacyVectors','PhotoColorPaletteTest')){$sourceFiles+=Join-Path $PSScriptRoot "cc/huevia/ncp/$name.java"}
foreach($name in @('PhotoAdjustmentsTest','PhotoToolsPersistenceTest','PhotoColorAdjustmentsTest')){$sourceFiles+=Join-Path $projectRoot "tests/editor-java/cc/huevia/album/$name.java"}
$sourceFiles+=Join-Path $projectRoot 'tests/adjustment-region-host/cc/huevia/ncp/AdjustmentRegionTest.java'
$sourceFiles+=Join-Path $projectRoot 'tests/java/cc/huevia/ncp/NcpCompatibilityFixtures.java'
$compileOutput=& $javac '-encoding' 'UTF-8' '-d' $classes @sourceFiles 2>&1
$compileExit=$LASTEXITCODE
$compileOutput|Out-File -LiteralPath (Join-Path $outputRoot 'javac.log') -Encoding utf8
if($compileExit -ne 0){throw "javac failed: $compileOutput"}
$testResults=@()
foreach($name in @('cc.huevia.ncp.PaletteLegacyVectors','cc.huevia.ncp.PhotoColorPaletteTest','cc.huevia.album.PhotoAdjustmentsTest','cc.huevia.album.PhotoToolsPersistenceTest','cc.huevia.album.PhotoColorAdjustmentsTest','cc.huevia.ncp.AdjustmentRegionTest')){
    $testOutput=& $java '-Xmx256m' '-cp' $classes $name 2>&1
    $testExit=$LASTEXITCODE
    $testText=($testOutput -join "`n")+"`n"
    $logPath=Join-Path $outputRoot ($name.Split('.')[-1]+'.log')
    [IO.File]::WriteAllText($logPath,$testText,(New-Object Text.UTF8Encoding($false)))
    if($testExit -ne 0){throw "$name failed: $testText"}
    if($name.EndsWith('PaletteLegacyVectors')){
        $expected=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'legacy-vectors.txt')).Replace("`r`n","`n").Trim()
        if($testText.Trim() -ne $expected){throw 'Legacy pixel/wire/identity vectors changed.'}
        Write-Output 'Legacy pixel/wire/identity exact match: 294912 pixels.'
    }else{Write-Output $testText.Trim()}
    $testResults+=@{name=$name;exitCode=$testExit;log=$logPath;sha256=(Get-FileHash -LiteralPath $logPath -Algorithm SHA256).Hash.ToLowerInvariant()}
}
$freezeFiles=@('app/src/main/java/cc/huevia/ncp/PhotoColorPalette.java','app/src/main/java/cc/huevia/ncp/PhotoAdjustments.java','app/src/main/java/cc/huevia/ncp/AdjustedPreviewProfile.java','app/src/main/java/cc/huevia/ncp/AdjustmentRegion.java','app/src/main/java/cc/huevia/ncp/PhotoLocalEdits.java','app/src/main/java/cc/huevia/album/PhotoEditStore.java','app/src/main/java/cc/huevia/album/PhotoRecipeStore.java','tests/palette-host/cc/huevia/ncp/PaletteLegacyVectors.java','tests/palette-host/cc/huevia/ncp/PhotoColorPaletteTest.java','tests/palette-host/legacy-vectors.txt','tests/palette-host/run-host.ps1')
$freeze=@()
foreach($file in $freezeFiles){$freeze+=@{path=$file;sha256=(Get-FileHash -LiteralPath (Join-Path $projectRoot $file) -Algorithm SHA256).Hash.ToLowerInvariant()}}
$summary=@{status='pass';tests=$testResults;inputs=$freeze;legacyPixelCount=294912;legacyExact=$true;syntheticImagesOnly=$true;nativeDeviceTest=$false;limitations=@('Warm hue protection is a smooth colour heuristic, not semantic skin segmentation.','No claim of matching proprietary vivo or Apple image algorithms.')}
$summary|ConvertTo-Json -Depth 8|Out-File -LiteralPath (Join-Path $outputRoot 'host-summary.json') -Encoding utf8
