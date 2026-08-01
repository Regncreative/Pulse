import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

/// Resolves a Task Manager–style friendly process title.
///
/// Prefers version-resource FileDescription / ProductName when an executable
/// path is known; otherwise well-known heuristics; finally the raw image name.
class ProcessDisplayNames {
  static final Map<String, String?> _versionCache = {};
  static final Map<String, Future<String?>> _inflight = {};

  /// Synchronous best-effort label (heuristics only).
  static String friendlySync(String imageName) {
    final heuristic = _heuristicFriendly(imageName);
    if (heuristic != null) return heuristic;
    final trimmed = imageName.trim();
    if (trimmed.isEmpty) return '—';
    return trimmed;
  }

  /// Primary label + optional secondary executable name for list rows.
  static ({String primary, String? secondary}) splitLabels({
    required String imageName,
    String? productName,
  }) {
    final exe = imageName.trim();
    final product = productName?.trim();
    if (product != null && product.isNotEmpty) {
      final secondary =
          exe.isNotEmpty && !_sameIgnoreCase(product, exe) ? exe : null;
      return (primary: product, secondary: secondary);
    }
    final heuristic = _heuristicFriendly(exe);
    if (heuristic != null) {
      final secondary =
          exe.isNotEmpty && !_sameIgnoreCase(heuristic, exe) ? exe : null;
      return (primary: heuristic, secondary: secondary);
    }
    return (primary: exe.isEmpty ? '—' : exe, secondary: null);
  }

  /// Async FileDescription / ProductName from the executable on disk.
  static Future<String?> productNameForPath(String path) {
    final key = path.trim().toLowerCase();
    if (key.isEmpty) return Future<String?>.value(null);
    if (_versionCache.containsKey(key)) {
      return Future<String?>.value(_versionCache[key]);
    }
    final existing = _inflight[key];
    if (existing != null) return existing;
    final future = compute(_readVersionFriendlyName, path).then((value) {
      _versionCache[key] = value;
      _inflight.remove(key);
      return value;
    });
    _inflight[key] = future;
    return future;
  }

  static String? _heuristicFriendly(String imageName) {
    final base = _baseName(imageName).toLowerCase();
    if (base.isEmpty) return null;
    const map = <String, String>{
      'explorer.exe': 'Windows Explorer',
      'chrome.exe': 'Google Chrome',
      'msedge.exe': 'Microsoft Edge',
      'firefox.exe': 'Mozilla Firefox',
      'discord.exe': 'Discord',
      'cursor.exe': 'Cursor',
      'code.exe': 'Visual Studio Code',
      'devenv.exe': 'Visual Studio',
      'slack.exe': 'Slack',
      'spotify.exe': 'Spotify',
      'teams.exe': 'Microsoft Teams',
      'ms-teams.exe': 'Microsoft Teams',
      'system': 'System',
      'registry': 'Registry',
      'memory compression': 'Memory Compression',
      'secure system': 'Secure System',
      'csrss.exe': 'Client Server Runtime Process',
      'smss.exe': 'Windows Session Manager',
      'wininit.exe': 'Windows Start-Up Application',
      'services.exe': 'Service Control Manager',
      'lsass.exe': 'Local Security Authority Process',
      'winlogon.exe': 'Windows Logon Application',
      'svchost.exe': 'Service Host',
      'dwm.exe': 'Desktop Window Manager',
      'taskhostw.exe': 'Windows Task Host',
      'conhost.exe': 'Console Window Host',
      'fontdrvhost.exe': 'Usermode Font Driver Host',
      'sihost.exe': 'Shell Infrastructure Host',
      'runtimebroker.exe': 'Runtime Broker',
      'searchhost.exe': 'Windows Search',
      'startmenuexperiencehost.exe': 'Start',
      'shellexperiencehost.exe': 'Windows Shell Experience Host',
      'applicationframehost.exe': 'Application Frame Host',
      'systemsettings.exe': 'Settings',
      'taskmgr.exe': 'Task Manager',
    };
    return map[base];
  }

  static String _baseName(String pathOrName) {
    final t = pathOrName.trim();
    if (t.isEmpty) return '';
    final slash = t.replaceAll('/', '\\').lastIndexOf('\\');
    return slash < 0 ? t : t.substring(slash + 1);
  }

  static bool _sameIgnoreCase(String a, String b) =>
      a.toLowerCase() == b.toLowerCase();
}

/// Runs in a worker isolate — must not touch Flutter bindings.
String? _readVersionFriendlyName(String path) {
  if (!Platform.isWindows) return null;
  final trimmed = path.trim();
  if (trimmed.isEmpty) return null;
  final pathPtr = trimmed.toNativeUtf16();
  try {
    final dummy = calloc<DWORD>();
    try {
      final size = GetFileVersionInfoSize(pathPtr, dummy);
      if (size == 0) return null;
      final buffer = calloc<BYTE>(size);
      try {
        if (GetFileVersionInfo(pathPtr, 0, size, buffer) == 0) return null;
        final desc = _queryVersionValue(buffer, 'FileDescription');
        if (desc != null && desc.isNotEmpty) return desc;
        final product = _queryVersionValue(buffer, 'ProductName');
        if (product != null && product.isNotEmpty) return product;
        return null;
      } finally {
        calloc.free(buffer);
      }
    } finally {
      calloc.free(dummy);
    }
  } finally {
    calloc.free(pathPtr);
  }
}

String? _queryVersionValue(Pointer<BYTE> buffer, String key) {
  final translateLen = calloc<UINT>();
  final translatePtr = calloc<Pointer<Void>>();
  try {
    final translatePath = r'\VarFileInfo\Translation'.toNativeUtf16();
    try {
      if (VerQueryValue(
            buffer,
            translatePath,
            translatePtr,
            translateLen,
          ) ==
          0) {
        return null;
      }
    } finally {
      calloc.free(translatePath);
    }
    if (translateLen.value < 4 || translatePtr.value == nullptr) return null;
    final lang = translatePtr.value.cast<Uint16>();
    final langId = lang[0];
    final codePage = lang[1];
    final sub =
        '\\StringFileInfo\\${langId.toRadixString(16).padLeft(4, '0')}'
        '${codePage.toRadixString(16).padLeft(4, '0')}\\$key';
    final valueLen = calloc<UINT>();
    final valuePtr = calloc<Pointer<Void>>();
    final subPtr = sub.toNativeUtf16();
    try {
      if (VerQueryValue(buffer, subPtr, valuePtr, valueLen) == 0) {
        return null;
      }
      if (valuePtr.value == nullptr || valueLen.value == 0) return null;
      return valuePtr.value.cast<Utf16>().toDartString().trim();
    } finally {
      calloc.free(subPtr);
      calloc.free(valueLen);
      calloc.free(valuePtr);
    }
  } finally {
    calloc.free(translateLen);
    calloc.free(translatePtr);
  }
}
