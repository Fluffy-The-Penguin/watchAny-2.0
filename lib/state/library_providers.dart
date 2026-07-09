import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/app_database.dart' as db;
import 'library_state.dart';

// Expose the Drift database instance to Riverpod
final databaseProvider = Provider<db.AppDatabase>((ref) {
  return LibraryState().database;
});

// Watch library items by mode reactively from SQLite database
final libraryItemsProvider = StreamProvider.family<List<db.LibraryItem>, String>((ref, mode) {
  final appDb = ref.watch(databaseProvider);
  return (appDb.select(appDb.libraryItems)..where((tbl) => tbl.mode.equals(mode))).watch();
});

// Watch categories by mode reactively from SQLite database
final libraryCategoriesProvider = StreamProvider.family<List<db.LibraryCategory>, String>((ref, mode) {
  final appDb = ref.watch(databaseProvider);
  return (appDb.select(appDb.libraryCategories)..where((tbl) => tbl.mode.equals(mode))).watch();
});

// Surgical provider for notification badge counts to avoid rebuilding entire UI trees
final animeNotificationCountProvider = StateProvider<int>((ref) => 0);
final mangaNotificationCountProvider = StateProvider<int>((ref) => 0);
final moviesNotificationCountProvider = StateProvider<int>((ref) => 0);

// Global reference container to update Riverpod state from legacy code contexts
class RiverpodContainerHolder {
  static ProviderContainer? container;
}
