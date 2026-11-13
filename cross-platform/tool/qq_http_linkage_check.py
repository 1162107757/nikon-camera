#!/usr/bin/env python3
"""Verify the pinned QQ JAR's real HTTP ABI, plus loopback HTTP body/cache I/O.

This command uses supplied jars, javac and java; it never downloads or runs Gradle.
Pass OkHttp, Okio, and (for Okio 3) Kotlin stdlib together in --classpath.
"""
import argparse
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[2]


def references(jar, prefix):
    result = set()
    with ZipFile(jar) as archive:
        for name in archive.namelist():
            if not name.endswith('.class'):
                continue
            data = archive.read(name)
            if data[:4] != b'\xca\xfe\xba\xbe':
                raise ValueError('Invalid Java class')
            count = struct.unpack_from('>H', data, 8)[0]
            pool = [None] * count
            cursor, index = 10, 1
            while index < count:
                tag = data[cursor]
                cursor += 1
                if tag == 1:
                    length = struct.unpack_from('>H', data, cursor)[0]
                    cursor += 2
                    pool[index] = (tag, data[cursor:cursor + length].decode('utf-8', errors='replace'))
                    cursor += length
                elif tag in (7, 8, 16, 19, 20):
                    pool[index] = (tag, struct.unpack_from('>H', data, cursor)[0])
                    cursor += 2
                elif tag in (9, 10, 11, 12, 18, 17):
                    pool[index] = (tag, *struct.unpack_from('>HH', data, cursor))
                    cursor += 4
                elif tag in (3, 4):
                    cursor += 4
                elif tag in (5, 6):
                    cursor += 8
                    index += 1
                elif tag == 15:
                    cursor += 3
                else:
                    raise ValueError('Unsupported Java constant pool tag')
                index += 1
            for item in pool:
                if not item or item[0] not in (9, 10, 11):
                    continue
                owner = pool[pool[item[1]][1]][1]
                if owner.startswith(prefix):
                    signature = pool[item[2]]
                    result.add((str(item[0]), owner.replace('/', '.'), pool[signature[1]][1], pool[signature[2]][1]))
    return sorted(result)


JAVA = r'''
import java.lang.invoke.MethodType;
import java.lang.reflect.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.io.*;
import java.util.*;
import com.sun.net.httpserver.HttpServer;
import okhttp3.*;
public final class QqHttpLinkage {
  static Method method(Class<?> type, String name, Class<?>[] args, Class<?> result) throws Exception {
    // Covariant Kotlin/JVM bridge methods may share a name and parameters but
    // have distinct return descriptors. JVM linkage matches the complete descriptor.
    for (Method candidate : type.getDeclaredMethods()) {
      if (candidate.getName().equals(name) && Arrays.equals(candidate.getParameterTypes(), args)
          && candidate.getReturnType() == result) return candidate;
    }
    for (Class<?> parent : type.getInterfaces()) {
      try { return method(parent, name, args, result); } catch (NoSuchMethodException absent) {}
    }
    if (type.getSuperclass() != null) return method(type.getSuperclass(), name, args, result);
    throw new NoSuchMethodException(type.getName() + "." + name);
  }
  static Field field(Class<?> type, String name) throws Exception {
    try { return type.getDeclaredField(name); } catch (NoSuchFieldException absent) {}
    for (Class<?> parent : type.getInterfaces()) {
      try { return field(parent, name); } catch (NoSuchFieldException absent) {}
    }
    if (type.getSuperclass() != null) return field(type.getSuperclass(), name);
    throw new NoSuchFieldException(type.getName() + "." + name);
  }
  static void verify(String[] ref) throws Exception {
    ClassLoader loader = QqHttpLinkage.class.getClassLoader();
    Class<?> owner = Class.forName(ref[1], false, loader);
    if (ref[0].equals("9")) {
      Class<?> expected = MethodType.fromMethodDescriptorString("()" + ref[3], loader).returnType();
      if (field(owner, ref[2]).getType() != expected) throw new AssertionError(Arrays.toString(ref));
      return;
    }
    MethodType signature = MethodType.fromMethodDescriptorString(ref[3], loader);
    if (ref[2].equals("<init>")) owner.getDeclaredConstructor(signature.parameterArray());
    else method(owner, ref[2], signature.parameterArray(), signature.returnType());
  }
  public static void main(String[] args) throws Exception {
    String[][] references = REFERENCES;
    for (String[] ref : references) verify(ref);
    if (!okhttp3.internal.Version.userAgent().equals("okhttp/3.14.9")) throw new AssertionError("QQ requires pinned OkHttp3");
    HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
    int[] hits = {0};
    server.createContext("/", exchange -> {
      hits[0]++;
      ByteArrayOutputStream request = new ByteArrayOutputStream();
      byte[] buffer = new byte[1024]; int read;
      while ((read = exchange.getRequestBody().read(buffer)) != -1) request.write(buffer, 0, read);
      byte[] body = (exchange.getRequestMethod() + ":" + new String(request.toByteArray(), StandardCharsets.UTF_8)).getBytes(StandardCharsets.UTF_8);
      exchange.getResponseHeaders().set("Cache-Control", "max-age=60");
      exchange.sendResponseHeaders(200, body.length);
      exchange.getResponseBody().write(body); exchange.close();
    });
    Path directory = Files.createTempDirectory("qq-http-cache-");
    Cache cache = new Cache(directory.toFile(), 1024 * 1024);
    OkHttpClient client = new OkHttpClient.Builder().cache(cache).build();
    try {
      server.start();
      String url = "http://127.0.0.1:" + server.getAddress().getPort() + "/";
      Request get = new Request.Builder().url(url).build();
      for (int i = 0; i < 2; i++) try (Response response = client.newCall(get).execute()) {
        if (!response.body().string().equals("GET:")) throw new AssertionError("Response body I/O");
        if (i == 1 && response.cacheResponse() == null) throw new AssertionError("Disk cache read");
      }
      RequestBody form = new FormBody.Builder().add("nickname", "test value").build();
      try (Response response = client.newCall(new Request.Builder().url(url).post(form).build()).execute()) {
        if (!response.body().string().equals("POST:nickname=test%20value")) throw new AssertionError("Form I/O");
      }
      RequestBody multipart = new MultipartBody.Builder().setType(MultipartBody.FORM).addFormDataPart("file", "test.bin", RequestBody.create(MediaType.get("application/octet-stream"), new byte[]{1, 2, 3})).build();
      try (Response response = client.newCall(new Request.Builder().url(url).post(multipart).build()).execute()) {
        if (!response.body().string().contains("test.bin")) throw new AssertionError("Multipart I/O");
      }
      if (hits[0] != 3) throw new AssertionError("Cache bypassed");
      System.out.println("QQ_HTTP_LINKAGE_PASS members=" + references.length + " loopback=GET,FORM,MULTIPART,DISK_CACHE");
    } finally {
      server.stop(0); cache.delete(); client.connectionPool().evictAll(); client.dispatcher().executorService().shutdownNow();
      Files.deleteIfExists(directory);
    }
  }
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--classpath', required=True, help='OS-separated OkHttp3, Okio and optional Kotlin jar paths')
    parser.add_argument('--javac', default='javac')
    parser.add_argument('--java', default='java')
    args = parser.parse_args()
    jars = [Path(value).resolve(strict=True) for value in args.classpath.split(os.pathsep)]
    args.classpath = os.pathsep.join(map(str, jars))
    okhttp = next(path for path in jars if path.name == 'okhttp-3.14.9.jar')
    refs = references(ROOT / 'app/libs/open_sdk_3.5.19_r9483ffc7_lite.jar', 'okhttp3/') + references(okhttp, 'okio/')
    if not refs:
        raise ValueError('No HTTP member references were found')
    literal = '{' + ','.join('{' + ','.join(json.dumps(value) for value in ref) + '}' for ref in refs) + '}'
    with tempfile.TemporaryDirectory(prefix='qq-http-linkage-') as temp:
        source = Path(temp) / 'QqHttpLinkage.java'
        source.write_text(JAVA.replace('REFERENCES', literal), encoding='utf-8')
        subprocess.run([args.javac, '-encoding', 'UTF-8', '-classpath', args.classpath, str(source)], check=True)
        subprocess.run([args.java, '-classpath', temp + os.pathsep + args.classpath, 'QqHttpLinkage'], check=True)


if __name__ == '__main__':
    main()
