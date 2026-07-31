import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:win32/win32.dart';

import '../../../app/theme/pulse_theme.dart';

/// Loads a Windows shell file icon for a process (read-only, presentation-only).
///
/// Prefer [path] from IPC (`HealthProcessEntry.path` / executable path). When
/// empty, optionally resolve via [pid] in the UI session — LocalService often
/// cannot [OpenProcess] interactive user apps, so the service may leave path
/// blank for Chrome/Cursor/etc.
///
/// If the path is still unknown (or icon extraction fails), try a well-known
/// `%SystemRoot%` location for common system binaries, then the letter avatar.
class ProcessAppIcon extends StatefulWidget {
  const ProcessAppIcon({
    super.key,
    required this.path,
    required this.name,
    this.pid = 0,
    this.size = 28,
  });

  /// Executable path from PulseService when available.
  final String path;
  final String name;

  /// Used only when [path] is empty (LocalService gap). Prefer service paths.
  final int pid;
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
    _load();
  }

  @override
  void didUpdateWidget(covariant ProcessAppIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.pid != widget.pid ||
        oldWidget.name != widget.name) {
      setState(() => _image = null);
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
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
      img = await _ProcessIconCache.load(path);
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
      return ClipRRect(
        borderRadius: BorderRadius.circular(PulseTokens.radiusProcessIcon),
        child: RawImage(
          image: img,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }
    return _FallbackGlyph(name: widget.name, size: size);
  }
}

/// Maps common system process names to on-disk executables under SystemRoot.
///
/// Returns null when the name is not a known system binary.
@visibleForTesting
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
  // Fallback: parent of GetSystemDirectoryW (…\Windows\System32 → …\Windows).
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

/// Resolves process image paths by PID (cached).
///
/// Fallback for when PulseService (LocalService) cannot open the process.
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

/// Process-wide icon cache + single-flight extractor queue.
class _ProcessIconCache {
  static final Map<String, ui.Image?> _images = {};
  static final Map<String, Future<ui.Image?>> _inflight = {};
  static Future<void> _tail = Future<void>.value();

  static Future<ui.Image?> load(String path) {
    final key = path.trim().toLowerCase();
    if (key.isEmpty) return Future<ui.Image?>.value(null);
    if (_images.containsKey(key)) {
      return Future<ui.Image?>.value(_images[key]);
    }
    final existing = _inflight[key];
    if (existing != null) return existing;

    final future = _enqueue(path).then((img) {
      _images[key] = img;
      _inflight.remove(key);
      return img;
    });
    _inflight[key] = future;
    return future;
  }

  /// One extraction at a time — SHGetFileInfo is not thread-safe.
  static Future<ui.Image?> _enqueue(String path) {
    final completer = Completer<ui.Image?>();
    _tail = _tail.then((_) async {
      try {
        final packed = await compute(_extractIconBytes, path);
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
        borderRadius: BorderRadius.circular(PulseTokens.radiusProcessIcon),
        border: Border.all(color: PulseTokens.strokeSubtle),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: PulseTokens.accent,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.42,
        ),
      ),
    );
  }
}

/// Returns `[Uint8List bytes, int width, int height]` or null.
///
/// Runs inside [compute]; must initialize COM on this isolate first.
List<Object>? _extractIconBytes(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return null;

  final hr = CoInitializeEx(
    nullptr,
    COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE,
  );
  final comReady = hr == S_OK || hr == S_FALSE || hr == RPC_E_CHANGED_MODE;
  if (!comReady) return null;

  final pathPtr = trimmed.toNativeUtf16();
  try {
    final fromShell = _iconFromShell(pathPtr);
    if (fromShell != null) return fromShell;
    return _iconFromExtractIconEx(trimmed);
  } catch (_) {
    return null;
  } finally {
    calloc.free(pathPtr);
    if (hr == S_OK) {
      CoUninitialize();
    }
  }
}

List<Object>? _iconFromShell(Pointer<Utf16> pathPtr) {
  final sfi = calloc<SHFILEINFO>();
  try {
    var result = SHGetFileInfo(
      pathPtr,
      0,
      sfi,
      sizeOf<SHFILEINFO>(),
      SHGFI_ICON | SHGFI_SMALLICON,
    );
    if (result == 0) {
      result = SHGetFileInfo(
        pathPtr,
        0,
        sfi,
        sizeOf<SHFILEINFO>(),
        SHGFI_ICON | SHGFI_LARGEICON,
      );
    }
    if (result == 0) {
      result = SHGetFileInfo(
        pathPtr,
        FILE_ATTRIBUTE_NORMAL,
        sfi,
        sizeOf<SHFILEINFO>(),
        SHGFI_ICON | SHGFI_SMALLICON | SHGFI_USEFILEATTRIBUTES,
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

List<Object>? _iconFromExtractIconEx(String path) {
  final shell32 = DynamicLibrary.open('shell32.dll');
  final extractIconEx = shell32.lookupFunction<_ExtractIconExWNative, _ExtractIconExWDart>(
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
    final hIcon = hSmall != 0 ? hSmall : hLarge;
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
          // Some GDI icon bitmaps report alpha as 0 for every pixel even when
          // color data is valid — treat fully-zero alpha as opaque.
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
