import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../logging/app_logger.dart';

/// Keeps the optional LM Studio API token out of settings files.
///
/// The token is a secret: it is never written to SharedPreferences, the
/// settings export, logs, reports or diagnostics bundles. Only its presence
/// is shown in the UI.
abstract class LocalAiTokenStore {
  /// The saved token, or null when none is saved or it cannot be read.
  String? read();

  /// Saves [token]. Returns false (and logs why) when Windows refused.
  bool write(String token);

  /// Removes the saved token. Returns true when none is left.
  bool delete();
}

/// Windows Credential Manager store for the current user on this PC.
///
/// Uses a generic credential with CRED_PERSIST_LOCAL_MACHINE, so it stays on
/// this PC and does not roam with the user profile.
class WindowsCredentialTokenStore implements LocalAiTokenStore {
  WindowsCredentialTokenStore({
    required this.logger,
    this.targetName = defaultTargetName,
  });

  final AppLogger logger;

  /// Credential name shown in Windows Credential Manager. Tests pass their
  /// own so they never touch the user's saved key.
  final String targetName;

  static const String defaultTargetName = 'Pulse/Assistant/LMStudio';
  static const String _component = 'AssistantToken';

  /// CRED_MAX_CREDENTIAL_BLOB_SIZE (wincred.h): 5 * 512 bytes.
  static const int maxTokenBytes = 5 * 512;

  @override
  String? read() {
    if (!Platform.isWindows) return null;
    final target = targetName.toNativeUtf16();
    final out = calloc<Pointer<CREDENTIAL>>();
    try {
      if (CredRead(target, CRED_TYPE_GENERIC, 0, out) == FALSE) {
        // The last-error value is not always preserved across Dart FFI
        // calls, so 0 is treated like "not found" rather than as a failure.
        final error = GetLastError();
        if (error != ERROR_NOT_FOUND && error != ERROR_SUCCESS) {
          logger.warn(_component, 'Could not read the saved token ($error)');
        }
        return null;
      }
      try {
        final credential = out.value.ref;
        if (credential.CredentialBlobSize == 0) return null;
        final bytes = credential.CredentialBlob
            .asTypedList(credential.CredentialBlobSize);
        final token = utf8.decode(bytes, allowMalformed: false);
        return token.isEmpty ? null : token;
      } finally {
        CredFree(out.value);
      }
    } on FormatException {
      logger.warn(_component, 'The saved token is not valid UTF-8');
      return null;
    } finally {
      calloc.free(out);
      calloc.free(target);
    }
  }

  @override
  bool write(String token) {
    if (!Platform.isWindows) return false;
    final bytes = utf8.encode(token);
    if (bytes.isEmpty || bytes.length > maxTokenBytes) {
      logger.warn(_component, 'Token length rejected (${bytes.length} bytes)');
      return false;
    }
    final target = targetName.toNativeUtf16();
    final blob = calloc<Uint8>(bytes.length);
    final credential = calloc<CREDENTIAL>();
    try {
      blob.asTypedList(bytes.length).setAll(0, bytes);
      credential.ref
        ..Type = CRED_TYPE_GENERIC
        ..TargetName = target
        ..CredentialBlobSize = bytes.length
        ..CredentialBlob = blob
        ..Persist = CRED_PERSIST_LOCAL_MACHINE;
      if (CredWrite(credential, 0) == FALSE) {
        logger.error(
          _component,
          'Windows refused to save the token (${GetLastError()})',
        );
        return false;
      }
      logger.info(_component, 'Token saved to Windows Credential Manager');
      return true;
    } finally {
      // Wipe the plaintext copy before releasing it.
      blob.asTypedList(bytes.length).fillRange(0, bytes.length, 0);
      calloc.free(blob);
      calloc.free(credential);
      calloc.free(target);
    }
  }

  @override
  bool delete() {
    if (!Platform.isWindows) return true;
    final target = targetName.toNativeUtf16();
    try {
      if (CredDelete(target, CRED_TYPE_GENERIC, 0) == FALSE) {
        final error = GetLastError();
        // Nothing saved is success. Checking with a read is reliable even
        // when the last-error value was lost.
        if (error == ERROR_NOT_FOUND || read() == null) return true;
        logger.error(_component, 'Could not remove the token ($error)');
        return false;
      }
      logger.info(_component, 'Token removed from Windows Credential Manager');
      return true;
    } finally {
      calloc.free(target);
    }
  }
}

/// In-memory store for tests.
class MemoryLocalAiTokenStore implements LocalAiTokenStore {
  MemoryLocalAiTokenStore([this._token]);

  String? _token;

  @override
  String? read() => _token;

  @override
  bool write(String token) {
    if (token.isEmpty) return false;
    _token = token;
    return true;
  }

  @override
  bool delete() {
    _token = null;
    return true;
  }
}
