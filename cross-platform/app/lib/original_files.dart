import 'dart:convert';

import 'package:flutter/services.dart';

import 'domain.dart';

/// Native, persistent folder grants. Only the opaque ID crosses into the app.
class OriginalFiles {
  static const channel = MethodChannel('cc.huevia/file-publication');
  static Future<Json?> chooseTarget(String owner) async {
    try {
      final result = await channel.invokeMethod<String>('chooseTarget', {
        'owner': owner,
      });
      if (result == null) return null;
      final target = object(jsonDecode(result));
      if (target['id'] is! String ||
          !RegExp(r'^[0-9a-f]{32}$').hasMatch(target['id'] as String) ||
          target['name'] is! String) {
        throw const AppFailure('系统未返回有效的文件夹授权。');
      }
      return target;
    } on PlatformException catch (failure) {
      throw AppFailure(failure.message ?? '文件夹选择未完成。');
    }
  }
}
