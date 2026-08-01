import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:win32/win32.dart';

import '../../../app/theme/pulse_theme.dart';

/// Loads a native Windows shell icon for a process (read-only).
///
/// Prefer [path] from IPC. When empty, resolve via [pid] then known SystemRoot
/// binaries. Letter avatar is the last fallback only.
///
/// Icons are extracted at the device-pixel size (via [PrivateExtractIcons]) so
/// HiDPI displays stay sharp without upscaling a 16×16 bitmap.
class ProcessAppIcon extends StatefulWidget {
  const ProcessAppIcon({
    super.key,
    required this.path,
    required this.name,
    this.pid = 0,
    this.size = 16,
  });

  final String path;
  final String name;
  final int pid;

  /// Logical CSS pixels. Prefer 20 for list rows; 16 for nested children.
  final double size;

  @override
  State<ProcessAppIcon> createState() => _ProcessAppIconState();
}

class _ProcessAppIconState extends State<ProcessAppIcon> {
  ui.Image? _image;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void didUpdateWidget(covariant ProcessAppIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.pid != widget.pid ||
        oldWidget.name != widget.name ||
        oldWidget.size != widget.size) {
      setState(() => _image = null);
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final dpr =
        MediaQuery.maybeDevicePixelRatioOf(context) ??
            View.of(context).devicePixelRatio;
    final targetPx =
        math.max(16, (widget.size * dpr).round()).clamp(16, 64);

    final candidates = <String>[];
    void addCandidate(String? p) {
      final t = p?.trim() ?? '';
      if (t.isEmpty) return;
      final key = t.toLowerCase();
      if (candidates.any((c) => c.toLowerCase() == key)) return;
      candidates.add(t);
    }

    addCandidate(widget.path);
    if (widget.path.trim().isEmpty && widget.pid > 0) {
      addCandidate(_ProcessPathCache.resolve(widget.pid, widget.name));
    }
    addCandidate(knownSystemExecutablePath(widget.name));

    ui.Image? img;
    for (final path in candidates) {
      img = await _ProcessIconCache.load(path, targetPx);
      if (img != null) break;
    }

    if (!mounted || generation != _loadGeneration) return;
    setState(() => _image = img);
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final img = _image;
    if (img != null) {
      return SizedBox(
        width: size,
        height: size,
        child: RawImage(
          image: img,
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          alignment: Alignment.center,
        ),
      );
    }
    return _FallbackGlyph(name: widget.name, size: size);
  }
}

/// Maps common system process names to on-disk executables under SystemRoot.
String? knownSystemExecutablePath(String name) {
  final file = _baseFileName(name).toLowerCase();
  if (file.isEmpty) return null;

  final root = _systemRoot();
  if (root == null || root.isEmpty) return null;
  final sys = '$root\\System32';

  if (file == 'explorer.exe') {
    return '$root\\explorer.exe';
  }

  const system32 = <String>{
    'svchost.exe',
    'dwm.exe',
    'csrss.exe',
    'wininit.exe',
    'services.exe',
    'lsass.exe',
    'winlogon.exe',
    'smss.exe',
    'fontdrvhost.exe',
    'sihost.exe',
    'taskhostw.exe',
    'runtimebroker.exe',
    'conhost.exe',
    'taskmgr.exe',
    'dllhost.exe',
    'ctfmon.exe',
    'searchindexer.exe',
    'spoolsv.exe',
  };
  if (system32.contains(file)) {
    return '$sys\\$file';
  }
  return null;
}

String _baseFileName(String pathOrName) {
  final trimmed = pathOrName.trim();
  if (trimmed.isEmpty) return '';
  final slash = trimmed.replaceAll('/', '\\').lastIndexOf('\\');
  return slash < 0 ? trimmed : trimmed.substring(slash + 1);
}

String? _systemRoot() {
  final fromEnv =
      Platform.environment['SystemRoot'] ?? Platform.environment['SYSTEMROOT'];
  if (fromEnv != null && fromEnv.trim().isNotEmpty) {
    return fromEnv.trim();
  }
  final buf = wsalloc(MAX_PATH);
  try {
    final n = GetSystemDirectory(buf, MAX_PATH);
    if (n == 0 || n > MAX_PATH) return null;
    final sys = buf.toDartString().trim();
    if (sys.isEmpty) return null;
    final slash = sys.replaceAll('/', '\\').lastIndexOf('\\');
    if (slash <= 0) return null;
    return sys.substring(0, slash);
  } finally {
    calloc.free(buf);
  }
}

class _ProcessPathCache {
  static final Map<String, String?> _paths = {};

  static String? resolve(int pid, String name) {
    if (pid <= 0) return null;
    final key = '$pid:${name.trim().toLowerCase()}';
    if (_paths.containsKey(key)) return _paths[key];
    final path = _queryProcessImagePath(pid);
    _paths[key] = path;
    return path;
  }
}

String? _queryProcessImagePath(int pid) {
  final handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (handle == 0) return null;

  try {
    var capacity = MAX_PATH;
    for (var attempt = 0; attempt < 3; attempt++) {
      final buf = wsalloc(capacity);
      final size = calloc<DWORD>()..value = capacity;
      try {
        final ok = QueryFullProcessImageName(handle, 0, buf, size);
        if (ok != 0) {
          final path = buf.toDartString().trim();
          return path.isEmpty ? null : path;
        }
        if (GetLastError() == ERROR_INSUFFICIENT_BUFFER) {
          final needed = size.value;
          capacity = needed > capacity ? needed + 1 : capacity * 2;
          continue;
        }
        return null;
      } finally {
        calloc.free(buf);
        calloc.free(size);
      }
    }
  } finally {
    CloseHandle(handle);
  }
  return null;
}

/// Process-wide icon cache keyed by path + pixel size.
class _ProcessIconCache {
  static final Map<String, ui.Image?> _images = {};
  static final Map<String, Future<ui.Image?>> _inflight = {};
  static Future<void> _tail = Future<void>.value();

  static Future<ui.Image?> load(String path, int targetPx) {
    final key = '${path.trim().toLowerCase()}@$targetPx';
    if (key.startsWith('@')) return Future<ui.Image?>.value(null);
    if (_images.containsKey(key)) {
      return Future<ui.Image?>.value(_images[key]);
    }
    final existing = _inflight[key];
    if (existing != null) return existing;

    final future = _enqueue(path, targetPx).then((img) {
      _images[key] = img;
      _inflight.remove(key);
      return img;
    });
    _inflight[key] = future;
    return future;
  }

  static Future<ui.Image?> _enqueue(String path, int targetPx) {
    final completer = Completer<ui.Image?>();
    _tail = _tail.then((_) async {
      try {
        final packed = await compute(_extractIconBytes, <Object>[path, targetPx]);
        if (packed == null || packed.length < 3) {
          completer.complete(null);
          return;
        }
        final bytes = packed[0] as Uint8List;
        final width = packed[1] as int;
        final height = packed[2] as int;
        final img = await _decodeRgba(bytes, width, height);
        completer.complete(img);
      } catch (_) {
        completer.complete(null);
      }
    });
    return completer.future;
  }

  static Future<ui.Image?> _decodeRgba(
    Uint8List bytes,
    int width,
    int height,
  ) {
    final completer = Completer<ui.Image?>();
    ui.decodeImageFromPixels(
      bytes,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }
}

class _FallbackGlyph extends StatelessWidget {
  const _FallbackGlyph({required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final base = name.replaceAll(RegExp(r'\.exe$', caseSensitive: false), '');
    final letter = base.isNotEmpty ? base[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: PulseTokens.accentSoft,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: PulseTokens.strokeSubtle),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: PulseTokens.accent,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.55,
          height: 1,
        ),
      ),
    );
  }
}

/// Returns `[Uint8List bytes, int width, int height]` or null.
List<Object>? _extractIconBytes(List<Object> args) {
  final path = (args[0] as String).trim();
  final targetPx = args[1] as int;
  if (path.isEmpty) return null;

  final hr = CoInitializeEx(
    nullptr,
    COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE,
  );
  final comReady = hr == S_OK || hr == S_FALSE || hr == RPC_E_CHANGED_MODE;
  if (!comReady) return null;

  try {
    final fromPrivate = _iconFromPrivateExtract(path, targetPx);
    if (fromPrivate != null) return fromPrivate;

    final pathPtr = path.toNativeUtf16();
    try {
      // Prefer small shell icons — never pull LARGE just to stretch it.
      final fromShell = _iconFromShell(pathPtr, small: true);
      if (fromShell != null) return fromShell;
      return _iconFromExtractIconEx(path, preferSmall: true);
    } finally {
      calloc.free(pathPtr);
    }
  } catch (_) {
    return null;
  } finally {
    if (hr == S_OK) {
      CoUninitialize();
    }
  }
}

List<Object>? _iconFromPrivateExtract(String path, int px) {
  final pathPtr = path.toNativeUtf16();
  final icons = calloc<IntPtr>();
  try {
    final count = PrivateExtractIcons(
      pathPtr,
      0,
      px,
      px,
      icons,
      nullptr,
      1,
      0,
    );
    if (count == 0 || icons.value == 0) return null;
    final hIcon = icons.value;
    try {
      return _hiconToBytes(hIcon);
    } finally {
      DestroyIcon(hIcon);
    }
  } finally {
    calloc.free(pathPtr);
    calloc.free(icons);
  }
}

List<Object>? _iconFromShell(Pointer<Utf16> pathPtr, {required bool small}) {
  final sfi = calloc<SHFILEINFO>();
  try {
    final flags = SHGFI_ICON | (small ? SHGFI_SMALLICON : SHGFI_LARGEICON);
    var result = SHGetFileInfo(pathPtr, 0, sfi, sizeOf<SHFILEINFO>(), flags);
    if (result == 0) {
      result = SHGetFileInfo(
        pathPtr,
        FILE_ATTRIBUTE_NORMAL,
        sfi,
        sizeOf<SHFILEINFO>(),
        flags | SHGFI_USEFILEATTRIBUTES,
      );
    }
    if (result == 0) return null;
    final hIcon = sfi.ref.hIcon;
    if (hIcon == 0) return null;
    try {
      return _hiconToBytes(hIcon);
    } finally {
      DestroyIcon(hIcon);
    }
  } finally {
    calloc.free(sfi);
  }
}

typedef _ExtractIconExWNative = Int32 Function(
  Pointer<Utf16> lpszFile,
  Int32 nIconIndex,
  Pointer<IntPtr> phiconLarge,
  Pointer<IntPtr> phiconSmall,
  Uint32 nIcons,
);
typedef _ExtractIconExWDart = int Function(
  Pointer<Utf16> lpszFile,
  int nIconIndex,
  Pointer<IntPtr> phiconLarge,
  Pointer<IntPtr> phiconSmall,
  int nIcons,
);

List<Object>? _iconFromExtractIconEx(String path, {required bool preferSmall}) {
  final shell32 = DynamicLibrary.open('shell32.dll');
  final extractIconEx =
      shell32.lookupFunction<_ExtractIconExWNative, _ExtractIconExWDart>(
    'ExtractIconExW',
  );
  final pathPtr = path.toNativeUtf16();
  final large = calloc<IntPtr>();
  final small = calloc<IntPtr>();
  try {
    final count = extractIconEx(pathPtr, 0, large, small, 1);
    if (count <= 0) return null;
    final hSmall = small.value;
    final hLarge = large.value;
    final hIcon = preferSmall
        ? (hSmall != 0 ? hSmall : hLarge)
        : (hLarge != 0 ? hLarge : hSmall);
    if (hIcon == 0) return null;
    try {
      return _hiconToBytes(hIcon);
    } finally {
      if (hLarge != 0) DestroyIcon(hLarge);
      if (hSmall != 0) DestroyIcon(hSmall);
    }
  } finally {
    calloc.free(pathPtr);
    calloc.free(large);
    calloc.free(small);
  }
}

List<Object>? _hiconToBytes(int hIcon) {
  final iconInfo = calloc<ICONINFO>();
  try {
    if (GetIconInfo(hIcon, iconInfo) == 0) return null;
    final hbmColor = iconInfo.ref.hbmColor;
    final hbmMask = iconInfo.ref.hbmMask;
    final hbm = hbmColor != 0 ? hbmColor : hbmMask;
    if (hbm == 0) return null;

    final hdc = GetDC(NULL);
    final bmp = calloc<BITMAP>();
    try {
      if (GetObject(hbm, sizeOf<BITMAP>(), bmp) == 0) return null;
      final width = bmp.ref.bmWidth;
      final height = bmp.ref.bmHeight.abs();
      if (width <= 0 || height <= 0 || width > 256 || height > 256) {
        return null;
      }

      final bmi = calloc<BITMAPINFO>();
      bmi.ref.bmiHeader.biSize = sizeOf<BITMAPINFOHEADER>();
      bmi.ref.bmiHeader.biWidth = width;
      bmi.ref.bmiHeader.biHeight = -height;
      bmi.ref.bmiHeader.biPlanes = 1;
      bmi.ref.bmiHeader.biBitCount = 32;
      bmi.ref.bmiHeader.biCompression = BI_RGB;

      final byteCount = width * height * 4;
      final bits = calloc<Uint8>(byteCount);
      try {
        final got = GetDIBits(
          hdc,
          hbm,
          0,
          height,
          bits,
          bmi,
          DIB_RGB_COLORS,
        );
        if (got == 0) return null;

        final rgba = Uint8List(byteCount);
        var opaqueCount = 0;
        for (var i = 0; i < byteCount; i += 4) {
          final b = bits[i];
          final g = bits[i + 1];
          final r = bits[i + 2];
          var a = bits[i + 3];
          if (a == 0 && (r | g | b) != 0) {
            a = 255;
          }
          if (a != 0) opaqueCount++;
          rgba[i] = r;
          rgba[i + 1] = g;
          rgba[i + 2] = b;
          rgba[i + 3] = a;
        }
        if (opaqueCount == 0) return null;
        return <Object>[rgba, width, height];
      } finally {
        calloc.free(bits);
        calloc.free(bmi);
      }
    } finally {
      if (hbmColor != 0) DeleteObject(hbmColor);
      if (hbmMask != 0) DeleteObject(hbmMask);
      ReleaseDC(NULL, hdc);
      calloc.free(bmp);
    }
  } finally {
    calloc.free(iconInfo);
  }
}

IconData processFallbackIcon(String name) {
  final n = name.toLowerCase();
  if (n.contains('chrome') || n.contains('msedge') || n.contains('firefox')) {
    return LucideIcons.globe;
  }
  if (n.contains('code') || n.contains('cursor') || n.contains('devenv')) {
    return LucideIcons.code;
  }
  if (n.contains('discord') || n.contains('slack') || n.contains('teams')) {
    return LucideIcons.messageCircle;
  }
  if (n.contains('dwm') || n.contains('explorer') || n.contains('system')) {
    return LucideIcons.monitor;
  }
  return LucideIcons.appWindow;
}
