import 'dart:convert';
import 'dart:io';

/// Safe JSON config merge helpers for AI client mcp.json files.
class JsonConfigEditor {
  const JsonConfigEditor();

  Future<File> backup(File file) async {
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final backup = File('${file.path}.pulse-backup-$stamp');
    if (await file.exists()) {
      await file.copy(backup.path);
    }
    return backup;
  }

  Future<Map<String, dynamic>> readOrEmpty(File file) async {
    if (!await file.exists()) return <String, dynamic>{};
    final text = await file.readAsString();
    if (text.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const FormatException('Config root must be a JSON object');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<void> writeValidated(File file, Map<String, dynamic> root) async {
    final encoded = const JsonEncoder.withIndent('  ').convert(root);
    // Round-trip validate before replace.
    final check = jsonDecode(encoded);
    if (check is! Map) {
      throw const FormatException('Refusing to write non-object JSON');
    }
    final dir = file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString('$encoded\n');
    if (await file.exists()) {
      await file.delete();
    }
    await tmp.rename(file.path);
  }

  Map<String, dynamic> ensureMcpServers(Map<String, dynamic> root) {
    final existing = root['mcpServers'];
    if (existing is Map) {
      root['mcpServers'] = Map<String, dynamic>.from(existing);
    } else {
      root['mcpServers'] = <String, dynamic>{};
    }
    return root;
  }
}
