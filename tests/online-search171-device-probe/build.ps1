param([string]$SdkRoot='D:/dev/android-sdk',[string]$JdkRoot='D:/dev/Java/jdk-17.0.19')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$output=Join-Path $PSScriptRoot '.build';$work=Join-Path $output ([Guid]::NewGuid().ToString('N'));$classes=Join-Path $work 'classes';$dex=Join-Path $work 'dex'
foreach($directory in @($classes,$dex)){New-Item -ItemType Directory -Force -Path $directory|Out-Null}
$androidJar=Join-Path $SdkRoot 'platforms/android-35/android.jar';$tools=Join-Path $SdkRoot 'build-tools/35.0.0'
function Run([string]$Exe,[string[]]$Arguments){$oldPreference=$ErrorActionPreference;try{$ErrorActionPreference='Continue';& $Exe @Arguments;$code=$LASTEXITCODE}finally{$ErrorActionPreference=$oldPreference};if($code -ne 0){throw ('OnlineSearch171 probe build failed: '+$Exe)}}
$sources=@(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'src') -Filter '*.java' -Recurse|ForEach-Object FullName)
$inputs=@($sources|ForEach-Object{[ordered]@{path=$_.Substring($root.Length+1).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()}})
$unsigned=Join-Path $work 'unsigned.apk'
Run (Join-Path $tools 'aapt2.exe') @('link','-I',$androidJar,'--manifest',(Join-Path $PSScriptRoot 'AndroidManifest.xml'),'--min-sdk-version','26','--target-sdk-version','35','--version-code','1','--version-name','1.0','-o',$unsigned)
$argsFile=Join-Path $work 'javac.args';$lines=@('-J-Xmx256m','-encoding','UTF-8','-source','17','-target','17','-classpath',('"'+($androidJar+';'+(Join-Path $root 'app/build/manual/classes')).Replace('\','/')+'"'),'-d',('"'+$classes.Replace('\','/')+'"'))+@($sources|ForEach-Object{'"'+$_.Replace('\','/')+'"'})
[IO.File]::WriteAllLines($argsFile,$lines,[Text.UTF8Encoding]::new($false))
Run (Join-Path $JdkRoot 'bin/javac.exe') @('@'+$argsFile)
$jar=Join-Path $work 'classes.jar';Run (Join-Path $JdkRoot 'bin/jar.exe') @('--create','--file',$jar,'-C',$classes,'.')
$oldJava=$env:JAVA_HOME;$oldOpts=$env:JAVA_OPTS
try{$env:JAVA_HOME=$JdkRoot;$env:JAVA_OPTS='-Xmx256m';Run (Join-Path $tools 'd8.bat') @('--debug','--min-api','26','--lib',$androidJar,'--output',$dex,$jar)}finally{$env:JAVA_HOME=$oldJava;$env:JAVA_OPTS=$oldOpts}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::Open($unsigned,[IO.Compression.ZipArchiveMode]::Update)
try{foreach($file in Get-ChildItem -LiteralPath $dex -Filter '*.dex'){[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$file.FullName,$file.Name,[IO.Compression.CompressionLevel]::Optimal)|Out-Null}}finally{$archive.Dispose()}
$aligned=Join-Path $work 'aligned.apk';$final=Join-Path $output 'online-search171-probe.apk'
Run (Join-Path $tools 'zipalign.exe') @('-f','4',$unsigned,$aligned)
Run (Join-Path $JdkRoot 'bin/java.exe') @('-Xmx128m','-jar',(Join-Path $tools 'lib/apksigner.jar'),'sign','--ks',(Join-Path $root '.tooling/debug.keystore'),'--ks-pass','pass:android','--key-pass','pass:android','--ks-key-alias','androiddebugkey','--out',$final,$aligned)
Run (Join-Path $JdkRoot 'bin/java.exe') @('-Xmx128m','-jar',(Join-Path $tools 'lib/apksigner.jar'),'verify',$final)
$provenance=[ordered]@{builtAt=[DateTime]::UtcNow.ToString('O');inputs=$inputs;probeSha256=(Get-FileHash -LiteralPath $final -Algorithm SHA256).Hash.ToLowerInvariant();manifestSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'AndroidManifest.xml') -Algorithm SHA256).Hash.ToLowerInvariant();buildSha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant();runSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'run.ps1') -Algorithm SHA256).Hash.ToLowerInvariant()}
[IO.File]::WriteAllText((Join-Path $output 'provenance.json'),($provenance|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
Write-Output ('OnlineSearch171 probe: '+$final)
