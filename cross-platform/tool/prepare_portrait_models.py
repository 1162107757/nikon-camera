#!/usr/bin/env python3
"""Prepare identical pinned portrait assets without reading the original app tree.

macOS/Linux build the .NET 10 encoder's zlib-ng 2.2.5 from its pinned upstream
source. Windows uses PowerShell's .NET ZLibStream. Both must produce the exact
existing packed identity and recover the exact official model bytes.
"""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[2]
SOURCES = {
    'face_landmarker.task': ('https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task', '64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff', 3758596),
    'selfie_multiclass_256x256.tflite': ('https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_multiclass_256x256/float32/1/selfie_multiclass_256x256.tflite', 'c6748b1253a99067ef71f7e26ca71096cd449baefa8f101900ea23016507e0e0', 16371837),
    'LICENSE-MediaPipe.txt': ('https://raw.githubusercontent.com/google-ai-edge/mediapipe/v0.10.32/LICENSE', '8707eef0533987efc5b155d64761eeb6e20793f50b9bd1a68dad1cf4719d0ed8', 12331),
    'zlib-ng-2.2.5.tar.gz': ('https://codeload.github.com/zlib-ng/zlib-ng/tar.gz/refs/tags/2.2.5', '5b3b022489f3ced82384f06db1e13ba148cbce38c7941e424d6cb414416acd18', 2417402),
}
DETECTOR_SHA = 'c7d54204ce0448474c7f3fa9af494787c0965cbdd6f20fc72867e43046bd43d5'
PACKED_SHA = '9920fafc503c9090b3840c6fb433efc7eeb117bb00176b04034bd589c0e19bb0'
PACKED_BYTES = 13881786


def digest(data):
    return hashlib.sha256(data).hexdigest()


def atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink():
        raise ValueError('Refusing symlink output: ' + str(path))
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix=path.name + '.', suffix='.partial', delete=False) as stream:
        temporary = Path(stream.name)
        try:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        except BaseException:
            temporary.unlink(missing_ok=True)
            raise
    try:
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def source(cache, name):
    url, expected, length = SOURCES[name]
    path = cache / name
    if path.is_file() and not path.is_symlink():
        data = path.read_bytes()
        if len(data) == length and digest(data) == expected:
            return data
    failure = None
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, timeout=60) as response:
                data = response.read(length + 1)
            if len(data) != length or digest(data) != expected:
                raise ValueError('Pinned source identity mismatch: ' + name)
            atomic_write(path, data)
            return data
        except (OSError, ValueError) as error:
            failure = error
    raise RuntimeError('Could not prepare pinned source: ' + name) from failure


def shuffle4(original):
    words = len(original) // 4
    return b''.join(original[plane:words * 4:4] for plane in range(4)) + original[words * 4:]


PACKER_C = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "zlib.h"
int main(int argc, char **argv) {
  if (argc != 3 || strcmp(zlibVersion(), "1.3.1.zlib-ng") != 0) return 2;
  FILE *input = fopen(argv[1], "rb"); if (!input) return 3;
  if (fseek(input, 0, SEEK_END)) return 4;
  long length = ftell(input); if (length != 16371837 || fseek(input, 0, SEEK_SET)) return 5;
  unsigned char *data = (unsigned char *)malloc((size_t)length);
  if (!data || fread(data, 1, (size_t)length, input) != (size_t)length) return 6;
  fclose(input);
  uLongf capacity = compressBound((uLong)length);
  unsigned char *packed = (unsigned char *)malloc(capacity);
  if (!packed || compress2(packed, &capacity, data, (uLong)length, 9) != Z_OK) return 7;
  FILE *output = fopen(argv[2], "wb"); if (!output) return 8;
  if (fwrite(packed, 1, capacity, output) != capacity || fclose(output)) return 9;
  free(packed); free(data); return 0;
}
'''


def pack_unix(cache, shuffled):
    archive = source(cache, 'zlib-ng-2.2.5.tar.gz')
    build_root = cache / ('encoder-2.2.5-' + platform.system().lower() + '-' + platform.machine().lower())
    source_root = build_root / 'zlib-ng-2.2.5'
    build_root.mkdir(parents=True, exist_ok=True)
    # Only regular pinned files/directories; reject links and traversal before writing.
    with tarfile.open(fileobj=io.BytesIO(archive), mode='r:gz') as tar:
        entries = tar.getmembers()
        for entry in entries:
            target = build_root / entry.name
            if not target.resolve().is_relative_to(build_root.resolve()) or not (entry.isfile() or entry.isdir()):
                raise ValueError('Unsafe encoder archive entry')
        for entry in entries:
            target = build_root / entry.name
            if entry.isdir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                atomic_write(target, tar.extractfile(entry).read())
    project = build_root / 'driver'
    project.mkdir(exist_ok=True)
    atomic_write(project / 'packer.c', PACKER_C.encode('utf-8'))
    atomic_write(project / 'CMakeLists.txt', b'''cmake_minimum_required(VERSION 3.15)
project(HueviaPinnedModelPacking C)
set(ZLIB_COMPAT ON CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(ZLIB_ENABLE_TESTS OFF CACHE BOOL "" FORCE)
set(ZLIBNG_ENABLE_TESTS OFF CACHE BOOL "" FORCE)
set(WITH_GTEST OFF CACHE BOOL "" FORCE)
set(WITH_GZFILEOP OFF CACHE BOOL "" FORCE)
set(WITH_OPTIM OFF CACHE BOOL "" FORCE)
set(WITH_RUNTIME_CPU_DETECTION OFF CACHE BOOL "" FORCE)
add_subdirectory(../zlib-ng-2.2.5 zlib-ng)
add_executable(huevia-model-packer packer.c)
target_link_libraries(huevia-model-packer PRIVATE zlib)
target_include_directories(huevia-model-packer PRIVATE ${CMAKE_CURRENT_BINARY_DIR}/zlib-ng ${CMAKE_CURRENT_SOURCE_DIR}/../zlib-ng-2.2.5)
''')
    build = build_root / 'build'
    cmake = shutil.which('cmake')
    if not cmake:
        raise RuntimeError('CMake and a host C compiler are required to reproduce the pinned zlib-ng model asset')
    subprocess.run([cmake, '-S', str(project), '-B', str(build), '-DCMAKE_BUILD_TYPE=Release'], check=True)
    subprocess.run([cmake, '--build', str(build), '--config', 'Release', '--parallel', '2'], check=True)
    input_path, output_path = build_root / 'shuffled.bin', build_root / 'packed.zlib'
    atomic_write(input_path, shuffled)
    try:
        subprocess.run([str(build / 'huevia-model-packer'), str(input_path), str(output_path)], check=True)
        return output_path.read_bytes()
    finally:
        input_path.unlink(missing_ok=True)
        output_path.unlink(missing_ok=True)


def pack_windows(cache, shuffled):
    # Match the original PowerShell script without executing it or writing app/.
    # Output identity below is mandatory, including when the installed runtime changes.
    pwsh = shutil.which('pwsh')
    if not pwsh:
        raise RuntimeError('PowerShell with .NET 10 ZLibStream is required on Windows')
    with tempfile.TemporaryDirectory(dir=cache, prefix='encoder-') as temp:
        directory = Path(temp)
        atomic_write(directory / 'shuffled.bin', shuffled)
        script = directory / 'pack.ps1'
        atomic_write(script, b'''$ErrorActionPreference = 'Stop'
$inputBytes = [IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'shuffled.bin'))
$packed = [IO.MemoryStream]::new()
try {
  $encoder = [IO.Compression.ZLibStream]::new($packed, [IO.Compression.CompressionLevel]::SmallestSize, $true)
  try { $encoder.Write($inputBytes, 0, $inputBytes.Length) } finally { $encoder.Dispose() }
  [IO.File]::WriteAllBytes((Join-Path $PSScriptRoot 'packed.zlib'), $packed.ToArray())
} finally { $packed.Dispose() }
''')
        subprocess.run([pwsh, '-NoProfile', '-NonInteractive', '-File', str(script)], check=True)
        return (directory / 'packed.zlib').read_bytes()


def prepare(cache, destination):
    cache.mkdir(parents=True, exist_ok=True)
    task = source(cache, 'face_landmarker.task')
    original = source(cache, 'selfie_multiclass_256x256.tflite')
    license_bytes = source(cache, 'LICENSE-MediaPipe.txt')
    with zipfile.ZipFile(io.BytesIO(task)) as archive:
        entry = archive.getinfo('face_landmarks_detector.tflite')
        if entry.file_size != 2553590:
            raise ValueError('Unexpected face detector size')
        detector = archive.read(entry)
    if digest(detector) != DETECTOR_SHA:
        raise ValueError('Extracted detector SHA-256 mismatch')
    shuffled = shuffle4(original)
    packed_path = cache / 'face_skin_multiclass.shuffle4.zlib'
    packed = packed_path.read_bytes() if packed_path.is_file() and not packed_path.is_symlink() else b''
    if len(packed) != PACKED_BYTES or digest(packed) != PACKED_SHA:
        packed = pack_windows(cache, shuffled) if os.name == 'nt' else pack_unix(cache, shuffled)
    if len(packed) != PACKED_BYTES or digest(packed) != PACKED_SHA:
        raise ValueError('Encoder did not reproduce the pinned original packed asset')
    decoder = zlib.decompressobj()
    decoded = decoder.decompress(packed, len(original) + 1)
    if not decoder.eof or decoder.unused_data or decoder.unconsumed_tail or decoded != shuffled:
        raise ValueError('Packed model lossless round-trip mismatch')
    words = len(original) // 4
    restored = bytearray(len(original))
    for plane in range(4):
        restored[plane:words * 4:4] = decoded[plane * words:(plane + 1) * words]
    restored[words * 4:] = decoded[words * 4:]
    if digest(restored) != SOURCES['selfie_multiclass_256x256.tflite'][1]:
        raise ValueError('Restored official semantic model SHA-256 mismatch')
    atomic_write(packed_path, packed)
    outputs = {'face_landmarks_detector.tflite': detector, 'face_skin_multiclass.shuffle4.zlib': packed}
    for name, data in outputs.items():
        atomic_write(destination / name, data)
    atomic_write(destination.parent / 'third-party/portrait-models/LICENSE-MediaPipe.txt', license_bytes)
    if os.name != 'nt':
        with tarfile.open(fileobj=io.BytesIO(source(cache, 'zlib-ng-2.2.5.tar.gz')), mode='r:gz') as archive:
            atomic_write(destination.parent / 'third-party/portrait-models/LICENSE-zlib-ng.txt', archive.extractfile('zlib-ng-2.2.5/LICENSE.md').read())
    identity = {'schema': 1, 'sources': [{'name': name, 'url': value[0], 'sha256': value[1], 'bytes': value[2]} for name, value in SOURCES.items()],
                'outputs': [{'name': name, 'bytes': len(data), 'sha256': digest(data)} for name, data in outputs.items()],
                'restoredSemanticSha256': digest(restored), 'packing': 'four byte planes, trailing byte preserved; zlib-ng 2.2.5 level 9; exact original packed SHA required'}
    atomic_write(destination.parent / 'third-party/portrait-models/BUILD-IDENTITY.json', (json.dumps(identity, indent=2) + '\n').encode('utf-8'))
    print(json.dumps({'prepared': identity['outputs'], 'restoredSemanticSha256': digest(restored), 'originalAppTreeRead': False}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache', type=Path, default=ROOT / '.tooling/portrait-models')
    parser.add_argument('--destination', type=Path, default=ROOT / 'cross-platform/native/ios/Assets/portrait')
    args = parser.parse_args()
    destination = args.destination.resolve()
    if destination.is_relative_to((ROOT / 'app').resolve()) or destination.is_relative_to((ROOT / 'ios').resolve()):
        parser.error('Original application source trees are read-only')
    prepare(args.cache.resolve(), destination)


if __name__ == '__main__':
    main()
