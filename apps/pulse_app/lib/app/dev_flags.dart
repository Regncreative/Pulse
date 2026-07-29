/// Development feature flags for Pulse UI.
///
/// Enable mock timeline:
/// `flutter run -d windows --dart-define=PULSE_MOCK_TIMELINE=true`
library;

const bool kUseMockTimeline = bool.fromEnvironment(
  'PULSE_MOCK_TIMELINE',
  defaultValue: false,
);
