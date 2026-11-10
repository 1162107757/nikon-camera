param(
 [string]$NdkRoot='D:/dev/android-sdk/ndk/28.2.13676358',
 [ValidateSet('arm64-v8a','armeabi-v7a','x86_64','x86')][string[]]$Abi=@('arm64-v8a','armeabi-v7a','x86_64','x86'),
 [switch]$AllowModifiedLibRaw
)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$vendorRoot=Join-Path $projectRoot 'third-party/libraw'
$sourceRoot=Join-Path $vendorRoot 'LibRaw-0.22.3'
$archivePath=Join-Path $vendorRoot 'LibRaw-0.22.3.zip'
$sourceSha='114ca5cf9f774114cb99ce7acbb521af5f6895e76372098ea4bef5741bd089ac'
if((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $sourceSha){throw 'Official LibRaw archive SHA mismatch'}
$toolRoot=Join-Path $NdkRoot 'toolchains/llvm/prebuilt/windows-x86_64'
$clang=Join-Path $toolRoot 'bin/clang++.exe'
if(-not(Test-Path -LiteralPath $clang)){throw 'Install Android NDK 28.2.13676358 first'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::OpenRead($archivePath)
$sourceInputs=@()
try{
 foreach($entry in $archive.Entries){
  if($entry.FullName.EndsWith('/')){continue}
  $target=[IO.Path]::GetFullPath((Join-Path $vendorRoot $entry.FullName))
  if(-not $target.StartsWith([IO.Path]::GetFullPath($sourceRoot)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'LibRaw ZIP path escaped source root'}
  if(-not(Test-Path -LiteralPath $target -PathType Leaf)){throw ('Missing LibRaw source: '+$entry.FullName)}
  $actual=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
  $stream=$entry.Open();$hasher=[Security.Cryptography.SHA256]::Create()
  try{$expected=([BitConverter]::ToString($hasher.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}finally{$stream.Dispose();$hasher.Dispose()}
  if($actual -ne $expected -and -not $AllowModifiedLibRaw){throw ('Modified LibRaw source; pass -AllowModifiedLibRaw for a documented replacement build: '+$entry.FullName)}
  $sourceInputs+=[ordered]@{path=$entry.FullName;sha256=$actual;officialSha256=$expected}
 }
}finally{$archive.Dispose()}
if($AllowModifiedLibRaw){
 $known=@{};foreach($input in $sourceInputs){$known[$input.path]=$true}
 foreach($file in Get-ChildItem -LiteralPath $sourceRoot -File -Recurse){$relative=$file.FullName.Substring($vendorRoot.Length+1).Replace('\','/');if(-not $known.ContainsKey($relative)){$sourceInputs+=[ordered]@{path=$relative;sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant();officialSha256=$null}}}
}
$makefile=Get-Content -LiteralPath (Join-Path $sourceRoot 'Makefile.am') -Raw
$sourceBlock=[regex]::Match($makefile,'(?ms)^lib_libraw_a_SOURCES\s*=\s*(.*?)\r?\n\s*\r?\n').Groups[1].Value
$sources=@(($sourceBlock -replace '\\\r?\n',' ') -split '\s+' | Where-Object{$_ -match '^src/.+\.cpp$'})
if($sources.Count -lt 70){throw 'Cannot read official LibRaw source list'}
$flags=@('-std=c++17','-O2','-fPIC','-pthread','-DNDEBUG','-DUSE_ZLIB','-DLIBRAW_NODLL','-ffunction-sections','-fdata-sections',('-I'+$sourceRoot))
$signature=($sourceInputs|ConvertTo-Json -Compress -Depth 4)+($flags -join ' ')+(Get-Content -LiteralPath (Join-Path $NdkRoot 'source.properties') -Raw)
$digest=[Security.Cryptography.SHA256]::Create();try{$fingerprint=([BitConverter]::ToString($digest.ComputeHash([Text.Encoding]::UTF8.GetBytes($signature)))).Replace('-','').ToLowerInvariant()}finally{$digest.Dispose()}
$buildRoot=Join-Path $projectRoot ('.tooling/raw-native/'+$fingerprint.Substring(0,16));New-Item -ItemType Directory -Force -Path $buildRoot|Out-Null
function Invoke-Native([string]$Executable,[string[]]$Arguments){
 $savedPreference=$ErrorActionPreference
 try{$ErrorActionPreference='Continue';$result=(& $Executable @Arguments 2>&1|Out-String);$code=$LASTEXITCODE}finally{$ErrorActionPreference=$savedPreference}
 if($result){Write-Output $result.TrimEnd()};if($code -ne 0){throw ('Native tool failed '+$code+': '+$Executable)}
}
$outputs=@()
foreach($currentAbi in $Abi){
 $triple=switch($currentAbi){'arm64-v8a'{'aarch64-linux-android'}'armeabi-v7a'{'armv7a-linux-androideabi'}'x86_64'{'x86_64-linux-android'}'x86'{'i686-linux-android'}}
 $libraryTriple=if($currentAbi -eq 'armeabi-v7a'){'arm-linux-androideabi'}else{$triple}
 $is64=$currentAbi -eq 'arm64-v8a' -or $currentAbi -eq 'x86_64'
 $objects=Join-Path $buildRoot $currentAbi;New-Item -ItemType Directory -Force -Path $objects|Out-Null
 $destination=Join-Path $projectRoot ('app/src/main/jniLibs/'+$currentAbi);New-Item -ItemType Directory -Force -Path $destination|Out-Null
 $targetFlags=@(('--target='+$triple+'26'),('--sysroot='+(Join-Path $toolRoot 'sysroot')))
 $objectPaths=@()
 foreach($relative in $sources){
  $object=Join-Path $objects (($relative -replace '[/\\]','_')+'.o');$objectPaths+=$object
  if(-not(Test-Path -LiteralPath $object)){Invoke-Native $clang ($targetFlags+$flags+@('-c',(Join-Path $sourceRoot $relative),'-o',$object))}
 }
 $objectResponse=Join-Path $objects 'objects.rsp';[IO.File]::WriteAllLines($objectResponse,@($objectPaths|ForEach-Object{ '"'+$_.Replace('\','/')+'"' }),[Text.UTF8Encoding]::new($false))
 $raw=Join-Path $destination 'libraw.so'
 $link=@('-shared','-Wl,--build-id=sha1','-Wl,--no-undefined','-Wl,-z,max-page-size=16384','-Wl,-z,common-page-size=16384','-nostdlib++','-lc++_shared','-lz','-lm','-latomic')
 Invoke-Native $clang ($targetFlags+@('@'+$objectResponse)+$link+@('-Wl,-soname,libraw.so','-o',$raw))
 $bridge=Join-Path $destination 'libhuevia_raw.so'
 Invoke-Native $clang ($targetFlags+$flags+@((Join-Path $projectRoot 'app/src/main/cpp/huevia_raw.cpp'),('-L'+$destination),'-lraw','-ljnigraphics','-llog')+$link+@('-Wl,-soname,libhuevia_raw.so','-o',$bridge))
 Copy-Item -LiteralPath (Join-Path $toolRoot ('sysroot/usr/lib/'+$libraryTriple+'/libc++_shared.so')) -Destination (Join-Path $destination 'libc++_shared.so') -Force
 foreach($library in @($raw,$bridge,(Join-Path $destination 'libc++_shared.so'))){
  Invoke-Native (Join-Path $toolRoot 'bin/llvm-strip.exe') @('--strip-unneeded',$library)
  $headers=(& (Join-Path $toolRoot 'bin/llvm-readelf.exe') '-lW' $library|Out-String);if($LASTEXITCODE -ne 0){throw 'ELF verification failed'}
  $loads=@($headers -split "`r?`n"|Where-Object{$_ -match '^\s*LOAD\s'})
  $alignments=@($loads|ForEach-Object{if($_ -notmatch '\s0x([0-9a-fA-F]+)\s*$'){throw 'Cannot read ELF LOAD alignment'};[Convert]::ToInt64($Matches[1],16)})
  if($alignments.Count -lt 1){throw 'ELF has no LOAD segments'};$minimumAlignment=($alignments|Measure-Object -Minimum).Minimum
  if($minimumAlignment -lt 4096 -or $is64 -and $minimumAlignment -lt 16384){throw ('Native LOAD alignment does not satisfy its ABI requirement: '+$library)}
  $outputs+=[ordered]@{abi=$currentAbi;abiBits=if($is64){64}else{32};path=$library.Substring($projectRoot.Length+1).Replace('\','/');bytes=(Get-Item -LiteralPath $library).Length;sha256=(Get-FileHash -LiteralPath $library -Algorithm SHA256).Hash.ToLowerInvariant();minimumLoadAlignmentBytes=$minimumAlignment;page16KiBCompatible=($minimumAlignment -ge 16384);requires16KiBAlignment=$is64}
 }
 Write-Output ('Built '+$currentAbi)
}
$sourceBundle=$archivePath
if($AllowModifiedLibRaw){
 if(@(Get-ChildItem -LiteralPath $sourceRoot -Force -Recurse|Where-Object{($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0}).Count -ne 0){throw 'Replacement source packaging refuses filesystem links'}
 $sourceBundle=Join-Path $buildRoot ('replacement-source-'+[Guid]::NewGuid().ToString('N')+'.zip')
 [IO.Compression.ZipFile]::CreateFromDirectory($sourceRoot,$sourceBundle,[IO.Compression.CompressionLevel]::Optimal,$true)
}
$identity=[ordered]@{version='LibRaw 0.22.3';sourceUrl='https://www.libraw.org/data/LibRaw-0.22.3.zip';officialArchiveSha256=$sourceSha;bundledSourceSha256=(Get-FileHash -LiteralPath $sourceBundle -Algorithm SHA256).Hash.ToLowerInvariant();sourceFingerprint=$fingerprint;modifiedSource=[bool]$AllowModifiedLibRaw;ndk=(Get-Content -LiteralPath (Join-Path $NdkRoot 'source.properties') -Raw);minimumAndroidApi=26;openmp=$false;optionalLibraries=@('Android system zlib');sourceInputs=$sourceInputs;outputs=$outputs;bridgeSha256=(Get-FileHash -LiteralPath (Join-Path $projectRoot 'app/src/main/cpp/huevia_raw.cpp') -Algorithm SHA256).Hash.ToLowerInvariant()}
[IO.File]::WriteAllText((Join-Path $vendorRoot 'BUILD-IDENTITY.json'),($identity|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
$assetRoot=Join-Path $projectRoot 'app/src/main/assets/third-party/libraw';New-Item -ItemType Directory -Force -Path $assetRoot|Out-Null
Copy-Item -LiteralPath $sourceBundle -Destination (Join-Path $assetRoot 'LibRaw-0.22.3-source.zip') -Force
Copy-Item -LiteralPath (Join-Path $vendorRoot 'BUILD-IDENTITY.json') -Destination (Join-Path $assetRoot 'BUILD-IDENTITY.json') -Force
foreach($notice in @('LICENSE.LGPL','LICENSE.CDDL','COPYRIGHT')){Copy-Item -LiteralPath (Join-Path $sourceRoot $notice) -Destination (Join-Path $assetRoot $notice) -Force}
Copy-Item -LiteralPath (Join-Path $toolRoot 'NOTICE') -Destination (Join-Path $assetRoot 'LLVM-NOTICE.txt') -Force
Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $assetRoot 'build-raw-native.ps1') -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'app/src/main/cpp/huevia_raw.cpp') -Destination (Join-Path $assetRoot 'huevia_raw.cpp') -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'app/src/main/java/cc/huevia/album/RawDeveloper.java') -Destination (Join-Path $assetRoot 'RawDeveloper.java') -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'app/src/main/java/cc/huevia/album/RawPngWriter.java') -Destination (Join-Path $assetRoot 'RawPngWriter.java') -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'app/src/main/java/cc/huevia/ncp/RawDevelopmentSettings.java') -Destination (Join-Path $assetRoot 'RawDevelopmentSettings.java') -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'app/src/main/java/cc/huevia/ncp/RawJpegColorMatch.java') -Destination (Join-Path $assetRoot 'RawJpegColorMatch.java') -Force
Write-Output ('Native build complete: '+$outputs.Count+' libraries, source '+$fingerprint.Substring(0,16))
