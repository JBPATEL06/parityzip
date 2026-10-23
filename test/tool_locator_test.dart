import 'package:flutter_test/flutter_test.dart';
import 'package:parityzip/core/tool_locator.dart';

void main() {
  group('ToolLocator', () {
    test('all found', () {
      final mockBinaries = {'/usr/bin/7z', '/usr/bin/par2'};
      final locator = ToolLocator(
        pathEnv: '/usr/bin',
        isExecutableFile: (path) => mockBinaries.contains(path),
      );

      final status = locator.locate();
      expect(status.allFound, isTrue);
      expect(status.anyMissing, isFalse);
      expect(status.missingTools, isEmpty);
      expect(status.sevenZip.isFound, isTrue);
      expect(status.sevenZip.path, equals('/usr/bin/7z'));
      expect(status.sevenZip.binaryName, equals('7z'));
      expect(status.par2.isFound, isTrue);
      expect(status.par2.path, equals('/usr/bin/par2'));
      expect(status.par2.binaryName, equals('par2'));
    });

    test('7z missing', () {
      final mockBinaries = {'/usr/bin/par2'};
      final locator = ToolLocator(
        pathEnv: '/usr/bin',
        isExecutableFile: (path) => mockBinaries.contains(path),
      );

      final status = locator.locate();
      expect(status.allFound, isFalse);
      expect(status.anyMissing, isTrue);
      expect(status.missingTools, equals(['7z']));
      expect(status.sevenZip.isFound, isFalse);
      expect(status.par2.isFound, isTrue);
      expect(status.par2.path, equals('/usr/bin/par2'));
    });

    test('par2 missing', () {
      final mockBinaries = {'/usr/bin/7z'};
      final locator = ToolLocator(
        pathEnv: '/usr/bin',
        isExecutableFile: (path) => mockBinaries.contains(path),
      );

      final status = locator.locate();
      expect(status.allFound, isFalse);
      expect(status.anyMissing, isTrue);
      expect(status.missingTools, equals(['par2']));
      expect(status.sevenZip.isFound, isTrue);
      expect(status.sevenZip.path, equals('/usr/bin/7z'));
      expect(status.par2.isFound, isFalse);
    });

    test('7zz preferred over 7z', () {
      final mockBinaries = {
        '/usr/local/bin/7z',
        '/usr/bin/7zz',
        '/usr/bin/par2',
      };
      final locator = ToolLocator(
        pathEnv: '/usr/local/bin:/usr/bin',
        isExecutableFile: (path) => mockBinaries.contains(path),
      );

      final status = locator.locate();
      expect(status.sevenZip.isFound, isTrue);
      expect(status.sevenZip.binaryName, equals('7zz'));
      expect(status.sevenZip.path, equals('/usr/bin/7zz'));
    });

    test('7za fallback when 7zz and 7z are absent', () {
      final mockBinaries = {'/usr/bin/7za', '/usr/bin/par2'};
      final locator = ToolLocator(
        pathEnv: '/usr/bin',
        isExecutableFile: (path) => mockBinaries.contains(path),
      );

      final status = locator.locate();
      expect(status.sevenZip.isFound, isTrue);
      expect(status.sevenZip.binaryName, equals('7za'));
      expect(status.sevenZip.path, equals('/usr/bin/7za'));
    });

    test('empty PATH', () {
      final mockBinaries = {'/usr/bin/7z', '/usr/bin/par2'};
      final locatorEmpty = ToolLocator(
        pathEnv: '',
        isExecutableFile: (path) => mockBinaries.contains(path),
      );

      final statusEmpty = locatorEmpty.locate();
      expect(statusEmpty.allFound, isFalse);
      expect(statusEmpty.sevenZip.isFound, isFalse);
      expect(statusEmpty.par2.isFound, isFalse);
      expect(statusEmpty.missingTools, equals(['7z', 'par2']));

      // Test whitespace/empty PATH behavior:
      final locatorWhitespace = ToolLocator(
        pathEnv: '   ',
        isExecutableFile: (path) => mockBinaries.contains(path),
      );
      final statusWhitespace = locatorWhitespace.locate();
      expect(statusWhitespace.allFound, isFalse);
      expect(statusWhitespace.sevenZip.isFound, isFalse);
      expect(statusWhitespace.par2.isFound, isFalse);
    });
  });
}
