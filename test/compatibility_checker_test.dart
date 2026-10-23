import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:parityzip/core/compatibility_checker.dart';

void main() {
  group('CompatibilityChecker - Individual Rules', () {
    test(
      'Rule: Windows-invalid characters (< > : " | ? * \\ and control chars)',
      () {
        final invalidChars = [
          '<',
          '>',
          ':',
          '"',
          '|',
          '?',
          '*',
          '\\',
          '\x01',
          '\x1F',
        ];
        for (final ch in invalidChars) {
          final entries = [ScannedEntry(relativePath: 'test${ch}file.txt')];
          final warnings = CompatibilityChecker.checkEntries(entries);
          expect(
            warnings.any((w) => w.ruleId == 'invalid_character'),
            isTrue,
            reason: 'Expected warning for invalid char: ${ch.codeUnitAt(0)}',
          );
          expect(warnings.first.severity, equals('warning'));
          expect(
            warnings.first.message,
            contains('characters (< > : " | ? * \\'),
          );
          expect(warnings.first.suggestedFix, isNotEmpty);
        }
      },
    );

    test('Rule: Component ending with a space or a dot', () {
      final trailingSpace = [
        ScannedEntry(relativePath: 'folder /file.txt'),
        ScannedEntry(relativePath: 'my_file '),
      ];
      final warningsSpace = CompatibilityChecker.checkEntries(trailingSpace);
      expect(
        warningsSpace.where((w) => w.ruleId == 'trailing_dot_or_space').length,
        equals(2),
      );

      final trailingDot = [
        ScannedEntry(relativePath: 'folder./file.txt'),
        ScannedEntry(relativePath: 'trailing.'),
      ];
      final warningsDot = CompatibilityChecker.checkEntries(trailingDot);
      expect(
        warningsDot.where((w) => w.ruleId == 'trailing_dot_or_space').length,
        equals(2),
      );
    });

    test('Rule: Windows reserved device names (CON, PRN, AUX, NUL, COM1-9, LPT1-9)', () {
      final reserved = [
        'CON',
        'con',
        'CON.txt',
        'aux.log',
        'PRN.tar.gz',
        'nul',
        'NUL',
        'COM1',
        'com9.dat',
        'LPT1',
        'lpt5.doc',
      ];

      for (final name in reserved) {
        final entries = [ScannedEntry(relativePath: 'subfolder/$name')];
        final warnings = CompatibilityChecker.checkEntries(entries);
        expect(
          warnings.any((w) => w.ruleId == 'reserved_name'),
          isTrue,
          reason: 'Expected reserved_name warning for $name',
        );
      }

      // Non-reserved names should NOT trigger warning
      final clean = [
        'constant.txt',
        'contact.dat',
        'null.txt',
        'auxiliary.bin',
        'printer.log',
      ];
      for (final name in clean) {
        final entries = [ScannedEntry(relativePath: 'subfolder/$name')];
        final warnings = CompatibilityChecker.checkEntries(entries);
        expect(
          warnings.any((w) => w.ruleId == 'reserved_name'),
          isFalse,
          reason: 'Did not expect reserved_name warning for $name',
        );
      }
    });

    test('Rule: Component length > 255 bytes in UTF-8', () {
      // 256 ASCII bytes
      final longComp = 'a' * 256;
      final entries = [ScannedEntry(relativePath: 'dir/$longComp')];
      final warnings = CompatibilityChecker.checkEntries(entries);
      expect(warnings.any((w) => w.ruleId == 'component_too_long'), isTrue);

      // UTF-8 multibyte character: 3 bytes each
      // 86 chars * 3 bytes = 258 bytes
      final multibyteLong = 'જ' * 86;
      final mbEntries = [ScannedEntry(relativePath: multibyteLong)];
      final mbWarnings = CompatibilityChecker.checkEntries(mbEntries);
      expect(mbWarnings.any((w) => w.ruleId == 'component_too_long'), isTrue);
    });

    test('Rule: Full relative path > 240 characters', () {
      final longPath = '${'a' * 120}/${'b' * 125}'; // 246 chars
      expect(longPath.length, greaterThan(240));

      final entries = [ScannedEntry(relativePath: longPath)];
      final warnings = CompatibilityChecker.checkEntries(entries);
      expect(warnings.any((w) => w.ruleId == 'path_too_long'), isTrue);

      final shortPath = '${'a' * 50}/${'b' * 50}';
      final shortWarnings = CompatibilityChecker.checkEntries([
        ScannedEntry(relativePath: shortPath),
      ]);
      expect(shortWarnings.any((w) => w.ruleId == 'path_too_long'), isFalse);
    });

    test('Rule: Symlinks', () {
      final entries = [
        const ScannedEntry(relativePath: 'symlink_file', isSymlink: true),
        const ScannedEntry(relativePath: 'normal_file.txt', isSymlink: false),
      ];
      final warnings = CompatibilityChecker.checkEntries(entries);
      expect(warnings.length, equals(1));
      expect(warnings.first.ruleId, equals('symlink'));
      expect(warnings.first.path, equals('symlink_file'));
    });

    test('Rule: Case-collision detection within the same folder', () {
      final entries = [
        const ScannedEntry(relativePath: 'sub/hub_lite'),
        const ScannedEntry(relativePath: 'sub/hub_LITE'),
        const ScannedEntry(
          relativePath: 'other/hub_lite',
        ), // different folder -> no collision
      ];
      final warnings = CompatibilityChecker.checkEntries(entries);
      final caseWarnings = warnings
          .where((w) => w.ruleId == 'case_collision')
          .toList();
      expect(caseWarnings.length, equals(2));
      expect(caseWarnings.any((w) => w.path == 'sub/hub_lite'), isTrue);
      expect(caseWarnings.any((w) => w.path == 'sub/hub_LITE'), isTrue);
      expect(caseWarnings.any((w) => w.path == 'other/hub_lite'), isFalse);
    });

    test('Combined rules: multiple warnings on a single path', () {
      // "CON:name." is a reserved device base, contains colon, ends with dot
      final entries = [const ScannedEntry(relativePath: 'CON:name.')];
      final warnings = CompatibilityChecker.checkEntries(entries);
      final ruleIds = warnings.map((w) => w.ruleId).toSet();
      expect(ruleIds, contains('invalid_character'));
      expect(ruleIds, contains('trailing_dot_or_space'));
      expect(ruleIds, contains('reserved_name'));
    });
  });

  group('CompatibilityScanner - Directory Scanner & Fake File System', () {
    test('Scanner does NOT follow symlinked folders', () async {
      // Fake file system simulating:
      // /parent/clean_dir
      // /parent/clean_dir/file1.txt
      // /parent/symlink_dir (isLink = true)
      // /parent/symlink_dir/secret.txt (should never be scanned!)

      var walkedInsideSymlink = false;

      final scanner = CompatibilityScanner(
        isLinkChecker: (path) => path.contains('symlink'),
        isDirectoryChecker: (path) =>
            path.endsWith('dir') || path.endsWith('clean_dir'),
        directoryLister: (dir) {
          if (dir.path.contains('symlink')) {
            walkedInsideSymlink = true;
            return Stream.fromIterable([File('${dir.path}/secret.txt')]);
          }
          if (dir.path.endsWith('clean_dir')) {
            return Stream.fromIterable([
              File('${dir.path}/file1.txt'),
              Link('${dir.path}/symlink_dir'),
            ]);
          }
          return const Stream.empty();
        },
      );

      final result = await scanner.scan(
        commonParent: '/parent',
        relativeItemNames: ['clean_dir'],
      );

      expect(walkedInsideSymlink, isFalse);
      expect(result.limitReached, isFalse);
      expect(
        result.entries.any(
          (e) => e.relativePath.contains('symlink_dir') && e.isSymlink,
        ),
        isTrue,
      );
      expect(
        result.entries.any((e) => e.relativePath.contains('secret.txt')),
        isFalse,
      );
    });

    test('Scanner enforces scan cap and reports limit reached', () async {
      // Generate a fake directory stream that emits 50 items when cap is 20
      final scanner = CompatibilityScanner(
        isLinkChecker: (_) => false,
        isDirectoryChecker: (path) => path.endsWith('big_dir'),
        directoryLister: (dir) {
          final items = List.generate(
            50,
            (i) => File('${dir.path}/item_$i.txt'),
          );
          return Stream.fromIterable(items);
        },
      );

      final result = await scanner.scan(
        commonParent: '/parent',
        relativeItemNames: ['big_dir'],
        maxEntries: 20,
      );

      expect(result.limitReached, isTrue);
      expect(result.totalScanned, greaterThanOrEqualTo(20));
      expect(result.entries.length, lessThanOrEqualTo(25));
    });
  });
}
