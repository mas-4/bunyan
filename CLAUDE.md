# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Bunyan is a minimalist Flutter app for timestamped logging of daily events and symptoms. Users can quickly log words/phrases that get automatically timestamped and stored in CSV format for later analysis.

## Development Commands

### Common Flutter Commands
- `flutter run` - Run the app on connected device/emulator
- `flutter build apk` - Build Android APK
- `flutter build ios` - Build iOS app (requires Xcode on macOS)
- `flutter build web` - Build web version
- `flutter test` - Run unit tests
- `flutter analyze` - Run static analysis (uses flutter_lints rules)
- `flutter clean` - Clean build artifacts

### Platform-Specific
- `cd android && ./gradlew assembleDebug` - Build Android debug APK directly
- `cd android && ./gradlew assembleRelease` - Build Android release APK

## Architecture

### Single-File Architecture
The entire app is contained in `lib/main.dart` (~940 lines). This is intentional for simplicity and includes:

- **DateTimeFormatter**: Custom class for formatting timestamps in various formats (date, time, days ago)
- **WordEntry**: Data model for log entries with CSV serialization
- **WordLoggerHome**: Main screen with entry list, filtering, and CSV file management
- **EditEntryScreen**: Edit individual entries with tag suggestions

### Key Features
- **CSV Storage**: All data stored in device documents directory as `bunyan.csv`
- **Tag System**: Special characters (`!@#^&~+=\|`) trigger tag suggestions from existing entries
- **Bulk Edit**: Long-press entries to enter bulk selection mode for batch datetime updates
- **Swipe Actions**: Swipe left to delete, swipe right to add again
- **Import/Export**: Share CSV files or import existing data

### Data Flow
1. User types in TextField, optionally using tag characters for suggestions
2. Entry saved immediately to CSV file on submit
3. In-memory list (`_entries`) updated and re-sorted by timestamp
4. Display list (`_displayEntries`) filtered based on search text
5. File operations are async but UI updates immediately for responsiveness

### File Structure
- Single Dart file contains all logic
- No separate models, services, or screens
- Uses standard Flutter material design
- Supports both light/dark themes via system settings

## Dependencies

Core packages in `pubspec.yaml`:
- `path_provider` - Access device storage directories
- `share_plus` - Share CSV files with other apps
- `file_picker` - Import CSV files from device storage
- `flutter_lints` - Static analysis rules

## Testing

Currently no test files exist. When adding tests:
- Use `flutter test` command
- Test files should go in `test/` directory
- Focus on WordEntry CSV serialization and DateTimeFormatter logic