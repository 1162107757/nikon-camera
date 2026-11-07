param([string]$SdkRoot='D:/dev/android-sdk',[string]$JdkRoot='D:/dev/Java/jdk-17.0.19',[string]$GoldenFile='', [switch]$CompileOnly)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$output=Join-Path $PSScriptRoot '.build'
$work=Join-Path $output ([Guid]::NewGuid().ToString('N'))
$classes=Join-Path $work 'classes'
$dex=Join-Path $work 'dex'
foreach($directory in @($classes,$dex)){New-Item -ItemType Directory -Force -Path $directory|Out-Null}
$android=Join-Path $SdkRoot 'platforms/android-35/android.jar'
$buildTools=Join-Path $SdkRoot 'build-tools/35.0.0'
$java=Join-Path $JdkRoot 'bin/java.exe'
$fixtureRoot=Join-Path $root '.tooling/nikonpc-import-20261027'
$priorApk=Join-Path $root 'dist/huevia-0.24.0-beta-debug.apk'
$priorSha='a8c765ec68debe11611011bb77a890ef695b2bef38f109bdc2657a56ecb60e47'
$oldModel='encoded-rgb-tone-hsv-v1:np3-0310-encoded-hsl-zones-spatial-v3:np3-0310-deep-tone-monochrome-spatial-v1:np3-0310-monochrome-spatial-v1'
if((Get-FileHash -LiteralPath $priorApk -Algorithm SHA256).Hash.ToLowerInvariant() -ne $priorSha){throw 'Sealed122 cache baseline APK changed'}
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$priorZip=[IO.Compression.ZipFile]::OpenRead($priorApk)
try{$dexBytes=[IO.MemoryStream]::new();$stream=$priorZip.GetEntry('classes.dex').Open();try{$stream.CopyTo($dexBytes)}finally{$stream.Dispose()};$foundOld=[Text.Encoding]::ASCII.GetString($dexBytes.ToArray()).Contains($oldModel+[char]0);$dexBytes.Dispose();if(-not $foundOld){throw 'Sealed122 exact NUL-terminated model key not found'}}finally{$priorZip.Dispose()}
$cacheBaseline=Join-Path $work 'cache-baseline.json'
[IO.File]::WriteAllText($cacheBaseline,([ordered]@{apkSha256=$priorSha;modelVersion=$oldModel;dexStringConfirmed=$true}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
$manifestPath=Join-Path $fixtureRoot 'ready-manifest.json'
$originalManifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
if(@($originalManifest.items).Count -ne 149){throw 'Expected original149 manifest'}
$golden=$null
if(-not $CompileOnly){
    if([string]::IsNullOrWhiteSpace($GoldenFile)){throw 'Frozen native vectors required for an installable probe; use -CompileOnly for source self-check'}
    $GoldenFile=[IO.Path]::GetFullPath($GoldenFile)
    if(-not $GoldenFile.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or -not(Test-Path -LiteralPath $GoldenFile -PathType Leaf)){throw 'Frozen native vectors must exist under the project root'}
    $golden=Get-Content -LiteralPath $GoldenFile -Raw|ConvertFrom-Json
    if(-not $golden.modelVersion -or @($golden.argb).Count -le 8){throw 'Frozen native vector schema invalid'}
}
$fixtureInputs=[System.Collections.Generic.List[string]]::new()
$fixtureEntries=[System.Collections.Generic.List[object]]::new()
foreach($item in $originalManifest.items){
    $fixture=[IO.Path]::GetFullPath((Join-Path $fixtureRoot $item.filePath))
    if(-not $fixture.StartsWith($fixtureRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture escapes original corpus'}
    $bytes=[IO.File]::ReadAllBytes($fixture)
    if($bytes.Length -ne $item.byteLength -or (Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash.ToLowerInvariant() -ne $item.sha256){throw ('Original corpus changed: '+$item.filePath)}
    $isMono=$bytes[36] -eq 6 -and $bytes[37] -eq 77
    if(-not $CompileOnly -and $isMono -and -not $golden.outputs.PSObject.Properties[$item.sha256]){throw ('Missing frozen mono vector: '+$item.sha256)}
    $fixtureInputs.Add($fixture)
    $fixtureEntries.Add([ordered]@{asset=('originals/'+[IO.Path]::GetFileName($fixture));name=$item.name;sha256=$item.sha256;byteLength=$bytes.Length;monochrome=$isMono;filterEffect=[int]$bytes[45];toning=[int]$bytes[46];density=[int]$bytes[47]})
}
$assetManifest=Join-Path $work 'fixtures.json'
[IO.File]::WriteAllText($assetManifest,([ordered]@{sourceManifestSha256=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant();archiveSha256=$originalManifest.archiveSha256;items=$fixtureEntries.ToArray()}|ConvertTo-Json -Depth 7),[Text.UTF8Encoding]::new($false))
function Checked([string]$Executable,[string[]]$Arguments){& $Executable @Arguments;if($LASTEXITCODE -ne 0){throw ('NCP preview probe build failed: '+$Executable)}}
$unsigned=Join-Path $work 'unsigned.apk'
Checked (Join-Path $buildTools 'aapt2.exe') @('link','-I',$android,'--manifest',(Join-Path $PSScriptRoot 'AndroidManifest.xml'),'--min-sdk-version','26','--target-sdk-version','35','-o',$unsigned)
$source=@(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'src/cc/huevia/ncpqa') -Filter '*.java'|ForEach-Object FullName)
# Compile only against Android. Production symbols are resolved by reflection from the installed APK.
Checked (Join-Path $JdkRoot 'bin/javac.exe') (@('-J-Xmx256m','-encoding','UTF-8','-source','17','-target','17','-classpath',$android,'-d',$classes)+$source)
$jar=Join-Path $work 'probe.jar'
Checked (Join-Path $JdkRoot 'bin/jar.exe') @('--create','--file',$jar,'-C',$classes,'.')
Checked $java @('-Xmx256m','-XX:+UseSerialGC','-cp',(Join-Path $buildTools 'lib/d8.jar'),'com.android.tools.r8.D8','--debug','--min-api','26','--lib',$android,'--output',$dex,$jar)
if($CompileOnly){
    $auditInputs=@($source)+@((Join-Path $PSScriptRoot 'AndroidManifest.xml'),$PSCommandPath,(Join-Path $PSScriptRoot 'run.ps1'),$manifestPath,$priorApk)
    $audit=[ordered]@{scope='Compile only; no installable APK, golden or device operation';corpusCount=$fixtureEntries.Count;monochromeCount=@($fixtureEntries|Where-Object monochrome).Count;classpath='Android API35 only';sourceInputs=@($auditInputs|ForEach-Object{[ordered]@{path=$_.Substring($root.Length).TrimStart([char[]]'\/').Replace('\','/');sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_).Hash.ToLowerInvariant()}});dex=@(Get-ChildItem -LiteralPath $dex -Filter '*.dex'|ForEach-Object{[ordered]@{name=$_.Name;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}})}
    [IO.File]::WriteAllText((Join-Path $output 'compile-only.json'),($audit|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    Write-Output ('COMPILE_ONLY PASS; originals='+$fixtureEntries.Count+'; mono='+$audit.monochromeCount+'; '+(Join-Path $output 'compile-only.json'))
    return
}
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::Open($unsigned,[IO.Compression.ZipArchiveMode]::Update)
try{
    foreach($file in Get-ChildItem -LiteralPath $dex -Filter '*.dex'){[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$file.FullName,$file.Name,[IO.Compression.CompressionLevel]::Optimal)|Out-Null}
    foreach($fixture in $fixtureInputs){[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$fixture,('assets/originals/'+[IO.Path]::GetFileName($fixture)),[IO.Compression.CompressionLevel]::Optimal)|Out-Null}
    [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$assetManifest,'assets/fixtures.json',[IO.Compression.CompressionLevel]::Optimal)|Out-Null
    [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$cacheBaseline,'assets/cache-baseline.json',[IO.Compression.CompressionLevel]::Optimal)|Out-Null
    [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$GoldenFile,'assets/native-vectors.json',[IO.Compression.CompressionLevel]::Optimal)|Out-Null
}finally{$archive.Dispose()}
$aligned=Join-Path $work 'aligned.apk'
$final=Join-Path $output 'ncp-preview-probe.apk'
Checked (Join-Path $buildTools 'zipalign.exe') @('-f','4',$unsigned,$aligned)
Checked $java @('-Xmx128m','-jar',(Join-Path $buildTools 'lib/apksigner.jar'),'sign','--ks',(Join-Path $root '.tooling/debug.keystore'),'--ks-pass','pass:android','--key-pass','pass:android','--ks-key-alias','androiddebugkey','--out',$final,$aligned)
Checked $java @('-Xmx128m','-jar',(Join-Path $buildTools 'lib/apksigner.jar'),'verify','--verbose',$final)
$allInputs=@($source)+@((Join-Path $PSScriptRoot 'AndroidManifest.xml'),$PSCommandPath,(Join-Path $PSScriptRoot 'run.ps1'),$manifestPath,$GoldenFile,$priorApk)+$fixtureInputs.ToArray()
$inputs=@($allInputs|ForEach-Object{[ordered]@{path=$_.Substring($root.Length).TrimStart([char[]]'\/').Replace('\','/');sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_).Hash.ToLowerInvariant()}})
$classNames=@(Get-ChildItem -LiteralPath $classes -Filter '*.class' -Recurse|ForEach-Object{$_.FullName.Substring($classes.Length).TrimStart([char[]]'\/').Replace('\','/')})
if(@($classNames|Where-Object{-not $_.StartsWith('cc/huevia/ncpqa/')}).Count -gt 0){throw 'Unexpected production classes in probe'}
[IO.File]::WriteAllText((Join-Path $output 'provenance.json'),([ordered]@{inputs=$inputs;classpath='Android API35 only';classes=$classNames;apkSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $final).Hash.ToLowerInvariant()}|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
Write-Output $final
