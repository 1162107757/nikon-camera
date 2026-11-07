param([string]$CacheRoot)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
if (-not $CacheRoot) { $CacheRoot = Join-Path $projectRoot '.tooling/face-landmarks-cache' }
$CacheRoot = [IO.Path]::GetFullPath($CacheRoot)
New-Item -ItemType Directory -Path $CacheRoot -Force | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem

$sources = @(
    [ordered]@{name='litert-1.4.1.aar';url='https://dl.google.com/dl/android/maven2/com/google/ai/edge/litert/litert/1.4.1/litert-1.4.1.aar';sha256='815ef39f7d40f579adda1c7bcb7ce090685fb286777ffd8283f33202f67da1b4'},
    [ordered]@{name='litert-api-1.4.1.aar';url='https://dl.google.com/dl/android/maven2/com/google/ai/edge/litert/litert-api/1.4.1/litert-api-1.4.1.aar';sha256='ce5f6cc1924f0b9eb0fc339e0d3a3e6c9d041b9deb5e99f800fd6a42150f1875'},
    [ordered]@{name='face_landmarker.task';url='https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task';sha256='64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff'},
    [ordered]@{name='selfie_multiclass_256x256.tflite';url='https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_multiclass_256x256/float32/1/selfie_multiclass_256x256.tflite';bytes=16371837;sha256='c6748b1253a99067ef71f7e26ca71096cd449baefa8f101900ea23016507e0e0'},
    [ordered]@{name='MEDIAPIPE-LICENSE.txt';url='https://raw.githubusercontent.com/google-ai-edge/mediapipe/v0.10.32/LICENSE';sha256='8707eef0533987efc5b155d64761eeb6e20793f50b9bd1a68dad1cf4719d0ed8'}
)
function Hash-File([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Ensure-Source($Source) {
    $sourcePath = Join-Path $CacheRoot $Source.name
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf) -or (Hash-File $sourcePath) -ne $Source.sha256) {
        Invoke-WebRequest -Uri $Source.url -OutFile $sourcePath -UseBasicParsing
    }
    if ((Hash-File $sourcePath) -ne $Source.sha256) { throw ('Pinned face landmark source hash mismatch: ' + $Source.name) }
    if ($Source.bytes -and (Get-Item -LiteralPath $sourcePath).Length -ne $Source.bytes) { throw ('Pinned model source length mismatch: ' + $Source.name) }
    return $sourcePath
}
function Copy-ArchiveEntry([string]$ArchivePath, [string]$EntryName, [string]$Destination, [string]$ExpectedHash='') {
    if ($ExpectedHash -and (Test-Path -LiteralPath $Destination -PathType Leaf) -and (Hash-File $Destination) -eq $ExpectedHash) { return }
    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        $entry = $archive.GetEntry($EntryName)
        if (-not $entry) { throw ('Missing pinned artifact entry: ' + $EntryName) }
        $sourceStream = $entry.Open()
        try {
            $targetStream = [IO.File]::Create($Destination)
            try { $sourceStream.CopyTo($targetStream) } finally { $targetStream.Dispose() }
        } finally { $sourceStream.Dispose() }
    } finally { $archive.Dispose() }
    if ($ExpectedHash -and (Hash-File $Destination) -ne $ExpectedHash) { throw ('Extracted artifact hash mismatch: ' + $Destination) }
}
function Prepare-FaceSkinModel([string]$SourcePath, [string]$Destination) {
    $packedHash = '9920fafc503c9090b3840c6fb433efc7eeb117bb00176b04034bd589c0e19bb0'
    $packedBytes = 13881786
    $packedPath = Join-Path $CacheRoot 'face_skin_multiclass.shuffle4.zlib'
    if (-not ('HueviaFaceSkinPacking' -as [type])) {
        Add-Type -TypeDefinition @'
public static class HueviaFaceSkinPacking {
    public static byte[] Shuffle4(byte[] source) {
        int words = source.Length / 4;
        byte[] result = new byte[source.Length];
        for (int plane = 0; plane < 4; plane++)
            for (int word = 0; word < words; word++)
                result[plane * words + word] = source[word * 4 + plane];
        for (int tail = words * 4; tail < source.Length; tail++) result[tail] = source[tail];
        return result;
    }
    public static bool MatchesOriginal(byte[] shuffled, byte[] original) {
        if (shuffled.Length != original.Length) return false;
        int words = original.Length / 4;
        for (int plane = 0; plane < 4; plane++)
            for (int word = 0; word < words; word++)
                if (shuffled[plane * words + word] != original[word * 4 + plane]) return false;
        for (int tail = words * 4; tail < original.Length; tail++)
            if (shuffled[tail] != original[tail]) return false;
        return true;
    }
}
'@
    }
    $original = [IO.File]::ReadAllBytes($SourcePath)
    if (-not (Test-Path -LiteralPath $packedPath -PathType Leaf) -or (Hash-File $packedPath) -ne $packedHash) {
        $shuffled = [HueviaFaceSkinPacking]::Shuffle4($original)
        $packed = [IO.MemoryStream]::new()
        try {
            $encoder = [IO.Compression.ZLibStream]::new($packed,[IO.Compression.CompressionLevel]::SmallestSize,$true)
            try { $encoder.Write($shuffled,0,$shuffled.Length) } finally { $encoder.Dispose() }
            $packedData = $packed.ToArray()
            $hash = [Security.Cryptography.SHA256]::Create()
            try { $actualHash = [Convert]::ToHexString($hash.ComputeHash($packedData)).ToLowerInvariant() } finally { $hash.Dispose() }
            if ($packedData.Length -ne $packedBytes -or $actualHash -ne $packedHash) {
                throw 'Face skin packed identity mismatch. The pinned lossless encoder uses the bundled PowerShell .NET 10 ZLibStream SmallestSize runtime.'
            }
            [IO.File]::WriteAllBytes($packedPath,$packedData)
        } finally { $packed.Dispose() }
    }
    if ((Get-Item -LiteralPath $packedPath).Length -ne $packedBytes) { throw 'Face skin packed model length mismatch.' }
    $inputStream = [IO.File]::OpenRead($packedPath)
    try {
        $decoder = [IO.Compression.ZLibStream]::new($inputStream,[IO.Compression.CompressionMode]::Decompress,$true)
        try {
            $decoded = [byte[]]::new($original.Length)
            $decoder.ReadExactly($decoded,0,$decoded.Length)
            if ($decoder.ReadByte() -ne -1 -or -not [HueviaFaceSkinPacking]::MatchesOriginal($decoded,$original)) { throw 'Face skin lossless model round-trip mismatch.' }
        } finally { $decoder.Dispose() }
    } finally { $inputStream.Dispose() }
    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
    Copy-Item -LiteralPath $packedPath -Destination $Destination -Force
}
function Assert-Elf16K([string]$Path) {
    $elf = [IO.File]::ReadAllBytes($Path)
    if ($elf.Length -lt 64 -or $elf[0] -ne 127 -or $elf[1] -ne 69 -or $elf[2] -ne 76 -or $elf[3] -ne 70 -or $elf[5] -ne 1) { throw ('Expected little-endian ELF: ' + $Path) }
    $is64 = $elf[4] -eq 2
    if ($is64) {
        $programOffset = [BitConverter]::ToUInt64($elf,32); $entrySize = [BitConverter]::ToUInt16($elf,54); $entryCount = [BitConverter]::ToUInt16($elf,56)
    } else {
        $programOffset = [BitConverter]::ToUInt32($elf,28); $entrySize = [BitConverter]::ToUInt16($elf,42); $entryCount = [BitConverter]::ToUInt16($elf,44)
    }
    $alignments = [Collections.Generic.List[long]]::new()
    for ($index=0; $index -lt $entryCount; $index++) {
        $offset = [int]($programOffset + $index * $entrySize)
        if ([BitConverter]::ToUInt32($elf,$offset) -ne 1) { continue }
        $alignment = if ($is64) { [BitConverter]::ToUInt64($elf,$offset+48) } else { [BitConverter]::ToUInt32($elf,$offset+28) }
        if ($alignment -lt 16384) { throw ('Face landmark native ELF lacks 16 KiB LOAD alignment: ' + $Path) }
        $alignments.Add([long]$alignment)
    }
    if (-not $alignments.Count) { throw ('ELF has no LOAD segments: ' + $Path) }
    return @($alignments)
}

$sourcePaths = @{}
foreach ($source in $sources) { $sourcePaths[$source.name] = Ensure-Source $source }
$runtimeJar = Join-Path $projectRoot 'app/libs/litert-1.4.1.jar'
$apiJar = Join-Path $projectRoot 'app/libs/litert-api-1.4.1.jar'
$modelPath = Join-Path $projectRoot 'app/src/main/assets/portrait/face_landmarks_detector.tflite'
$skinModelPath = Join-Path $projectRoot 'app/src/main/assets/portrait/face_skin_multiclass.shuffle4.zlib'
$noticeRoot = Join-Path $projectRoot 'app/src/main/assets/third-party/litert'
Copy-ArchiveEntry $sourcePaths['litert-1.4.1.aar'] 'classes.jar' $runtimeJar 'c817a911a50d5c88f63ae6b31b131826198c96bedf72671cd32872d15a35d264'
Copy-ArchiveEntry $sourcePaths['litert-api-1.4.1.aar'] 'classes.jar' $apiJar 'fcdbe3f4eec7a8632fb4793a95b6e585f297db40701b27e6c20bbdaead21f4de'
Copy-ArchiveEntry $sourcePaths['face_landmarker.task'] 'face_landmarks_detector.tflite' $modelPath 'c7d54204ce0448474c7f3fa9af494787c0965cbdd6f20fc72867e43046bd43d5'
Prepare-FaceSkinModel $sourcePaths['selfie_multiclass_256x256.tflite'] $skinModelPath
Copy-ArchiveEntry $sourcePaths['litert-1.4.1.aar'] 'LICENSE' (Join-Path $noticeRoot 'LICENSE-LiteRT.txt')
Copy-Item -LiteralPath $sourcePaths['MEDIAPIPE-LICENSE.txt'] -Destination (Join-Path $noticeRoot 'LICENSE-MediaPipe.txt') -Force

$outputs = [Collections.Generic.List[object]]::new()
foreach ($file in @($runtimeJar,$apiJar,$modelPath,$skinModelPath,(Join-Path $noticeRoot 'LICENSE-LiteRT.txt'),(Join-Path $noticeRoot 'LICENSE-MediaPipe.txt'))) {
    $outputs.Add([ordered]@{path=$file.Substring($projectRoot.Length+1).Replace('\','/');bytes=(Get-Item -LiteralPath $file).Length;sha256=Hash-File $file})
}
foreach ($abi in @('arm64-v8a','armeabi-v7a','x86_64','x86')) {
    $nativePath = Join-Path $projectRoot ('app/src/main/jniLibs/'+$abi+'/libtensorflowlite_jni.so')
    Copy-ArchiveEntry $sourcePaths['litert-1.4.1.aar'] ('jni/'+$abi+'/libtensorflowlite_jni.so') $nativePath
    $alignments = @(Assert-Elf16K $nativePath)
    $outputs.Add([ordered]@{path=$nativePath.Substring($projectRoot.Length+1).Replace('\','/');bytes=(Get-Item -LiteralPath $nativePath).Length;sha256=Hash-File $nativePath;elfLoadAlignmentBytes=$alignments})
}
$identity = [ordered]@{
    schemaVersion=2
    runtime='com.google.ai.edge.litert:litert:1.4.1 + litert-api:1.4.1'
    model='MediaPipe Face mesh detection model v2, bundle version 1; 478 landmarks'
    modelSourcePage='https://developers.google.com/edge/mediapipe/solutions/vision/face_landmarker'
    sources=$sources
    outputs=@($outputs)
    inference=[ordered]@{input='FLOAT32 [1,256,256,3] RGB / 255';landmarksOutput='0: FLOAT32 [1,1,1,1434], 478 * xyz; divide xy by 256 before crop inverse projection';presenceOutput='1: FLOAT32 [1,1,1,1] raw logit; apply sigmoid';unusedOutput='2: FLOAT32 [1,1] (not used as presence)';operators='CONV_2D, PRELU, DEPTHWISE_CONV_2D, ADD, MAX_POOL_2D, PAD, LOGISTIC, RESHAPE, DEQUANTIZE; no CUSTOM/Flex';cpuOnly=$true}
    semanticModel=[ordered]@{
        name='MediaPipe Selfie Multiclass 256x256, float32/version 1'
        sourcePage='https://developers.google.com/edge/mediapipe/solutions/vision/image_segmenter'
        modelCard='https://storage.googleapis.com/mediapipe-assets/Model%20Card%20Multiclass%20Segmentation.pdf'
        license='Apache License, Version 2.0, explicitly identified by the official model card; Adel Ahmadyan (Google), May 10, 2023. LICENSE-MediaPipe.txt is preserved.'
        originalBytes=16371837
        originalSha256='c6748b1253a99067ef71f7e26ca71096cd449baefa8f101900ea23016507e0e0'
        packedAsset='portrait/face_skin_multiclass.shuffle4.zlib'
        packedBytes=13881786
        packedSha256='9920fafc503c9090b3840c6fb433efc7eeb117bb00176b04034bd589c0e19bb0'
        packing='Headerless zlib stream of four byte planes: N=floor(16371837/4)=4092959; decoded[p*N+i]=original[4*i+p], p=0..3, i=0..N-1; final one trailing byte unchanged. .NET 10 ZLibStream SmallestSize. No weights or model metadata are modified.'
        input='FLOAT32 [1,256,256,3] RGB / 127.5 - 1 (embedded mean 127.5, std 127.5)'
        output='0: FLOAT32 [1,256,256,6] raw logits; per pixel apply stable softmax once across 6 labels to obtain probabilities. Output producer is CONV_2D, not SOFTMAX.'
        postprocessing='Embedded SEGMENTER_METADATA (V001) ImageSegmenterOptions.activation=2 (SOFTMAX); official MediaPipe v0.10.32 image_segmenter_graph.cc reads this metadata and TensorsToSegmentationCalculator applies StableSoftmax.'
        postprocessingSource='https://github.com/google-ai-edge/mediapipe/blob/v0.10.32/mediapipe/tasks/cc/vision/image_segmenter/calculators/tensors_to_segmentation_calculator.cc'
        labels=@('background','hair','body-skin','face-skin','clothes','others')
        operators='CONV_2D, DEPTHWISE_CONV_2D, ADD, RESHAPE, TRANSPOSE, MUL, SOFTMAX, SUM, RESIZE_BILINEAR, RESIZE_NEAREST_NEIGHBOR, TRANSPOSE_CONV; no CUSTOM/Flex'
        runtimeLoading='Bundled asset only, streamed through InflaterInputStream into a direct native-order buffer; exact decoded/packed lengths and both SHA-256 hashes verified before caching. No runtime download.'
    }
    packaging='Four ABI bundled JNI, ELF LOAD alignment >= 16 KiB; extractNativeLibs=true; native/dex ZIP CompressionLevel.SmallestSize; precompressed face skin model asset ZIP NoCompression; other assets retain their existing compression rules.'
    runtimeDependencies='Only Android system libc, libm, libdl and liblog. No Tasks SDK, Play Services, data transport, GPU or network/model-download provider.'
    licensing='Preserve complete LiteRT AAR LICENSE (Apache-2.0 plus bundled third-party notices) and upstream MediaPipe LICENSE with official model source attribution. The official Face Mesh V2 model card explicitly states Apache License, Version 2.0. This app uses only the model file, not MediaPipe Tasks runtime.'
    modelCard='https://storage.googleapis.com/mediapipe-assets/Model%20Card%20MediaPipe%20Face%20Mesh%20V2.pdf'
}
[IO.File]::WriteAllText((Join-Path $noticeRoot 'BUILD-IDENTITY.json'),($identity | ConvertTo-Json -Depth 9)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
Write-Output ('Prepared offline portrait models: 2 Java jars, 4 ABI JNI libraries (16 KiB), 2 models (semantic weights lossless); SHA-256 and packed round-trip verified.')
