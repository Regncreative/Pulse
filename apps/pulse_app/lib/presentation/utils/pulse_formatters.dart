/// Runtime formatting preferences synced from [SettingsController].
///
/// Set from [PulseApp]'s builder so health/diagnostics formatters stay
/// consistent without threading settings through every call site.
abstract final class PulseFormatters {
  /// When true, byte sizes use binary units (KiB/MiB, base 1024).
  /// When false, decimal units (KB/MB, base 1000).
  static bool binaryUnits = true;

  /// When true, temperatures display in Celsius; otherwise Fahrenheit.
  static bool temperatureCelsius = true;

  /// When true, clocks use 24-hour format.
  static bool clock24h = true;
}
