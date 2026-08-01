import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/application/timeline_library_controller.dart';
import 'package:pulse/features/timeline/timeline_query.dart';
import 'package:pulse/logging/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TimelineLibraryController', () {
    test('persists bookmarks and pins across reload', () async {
      SharedPreferences.setMockInitialValues({});
      final logger = AppLogger();
      final a = TimelineLibraryController(logger: logger);
      await a.load();
      await a.toggleBookmark('System|1|1000');
      await a.togglePin('System|2|41');
      expect(a.isBookmarked('System|1|1000'), isTrue);
      expect(a.isPinned('System|2|41'), isTrue);

      final b = TimelineLibraryController(logger: logger);
      await b.load();
      expect(b.isBookmarked('System|1|1000'), isTrue);
      expect(b.isPinned('System|2|41'), isTrue);
      expect(b.isBookmarked('missing'), isFalse);
    });

    test('saved search roundtrips query fields', () async {
      SharedPreferences.setMockInitialValues({});
      final c = TimelineLibraryController(logger: AppLogger());
      await c.load();
      const q = TimelineQuery(
        severity: TimelineSeverityFilter.errors,
        category: TimelineCategoryFilter.power,
        searchQuery: 'kernel',
        eventIdEquals: '41',
        providerContains: 'Kernel-Power',
      );
      await c.saveSearch(name: 'Kernel 41', query: q);
      expect(c.savedSearches, hasLength(1));
      final restored = c.queryFromSaved(c.savedSearches.first)!;
      expect(restored.severity, TimelineSeverityFilter.errors);
      expect(restored.category, TimelineCategoryFilter.power);
      expect(restored.searchQuery, 'kernel');
      expect(restored.eventIdEquals, '41');
      expect(restored.providerContains, 'Kernel-Power');

      final d = TimelineLibraryController(logger: AppLogger());
      await d.load();
      expect(d.savedSearches, hasLength(1));
      expect(d.savedSearches.first.name, 'Kernel 41');
    });
  });
}
