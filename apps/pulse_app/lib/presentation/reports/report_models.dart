/// Report kinds available on the Reports page (existing Pulse data only).
enum ReportTemplate {
  healthSnapshot,
  timeline,
  diagnostics,
  hardwareInventory,
}

/// On-disk export encodings.
enum ReportFormat {
  json,
  csv,
  html,
  pdf,
}

extension ReportTemplateX on ReportTemplate {
  String get title => switch (this) {
        ReportTemplate.healthSnapshot => 'System Health snapshot',
        ReportTemplate.timeline => 'Timeline events',
        ReportTemplate.diagnostics => 'Diagnostics',
        ReportTemplate.hardwareInventory => 'Hardware inventory',
      };

  String get description => switch (this) {
        ReportTemplate.healthSnapshot =>
          'Current CPU, memory, GPU, disk, and network metrics plus system identity.',
        ReportTemplate.timeline =>
          'Events currently loaded in the Timeline session.',
        ReportTemplate.diagnostics =>
          'Service identity, IPC stats, pipeline stages, and client metrics.',
        ReportTemplate.hardwareInventory =>
          'Static hardware inventory from the last health snapshot.',
      };

  String get fileStem => switch (this) {
        ReportTemplate.healthSnapshot => 'pulse-health',
        ReportTemplate.timeline => 'pulse-timeline',
        ReportTemplate.diagnostics => 'pulse-diagnostics',
        ReportTemplate.hardwareInventory => 'pulse-hardware',
      };

  /// CSV fits tabular templates; diagnostics is structured JSON/HTML/PDF only.
  bool get supportsCsv => switch (this) {
        ReportTemplate.diagnostics => false,
        _ => true,
      };
}

extension ReportFormatX on ReportFormat {
  String get label => switch (this) {
        ReportFormat.json => 'JSON',
        ReportFormat.csv => 'CSV',
        ReportFormat.html => 'HTML',
        ReportFormat.pdf => 'PDF',
      };

  String get fileExtension => switch (this) {
        ReportFormat.json => 'json',
        ReportFormat.csv => 'csv',
        ReportFormat.html => 'html',
        ReportFormat.pdf => 'pdf',
      };
}
