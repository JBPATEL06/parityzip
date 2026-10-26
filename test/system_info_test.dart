import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parityzip/core/models.dart';
import 'package:parityzip/core/system_info.dart';
import 'package:parityzip/ui/widgets/about_dialog.dart';

void main() {
  group('SystemInfo', () {
    test('getOsName parses PRETTY_NAME with and without quotes', () {
      final tempDir = Directory.systemTemp.createTempSync('sysinfo_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final osFile = File('${tempDir.path}/os-release');
      osFile.writeAsStringSync(
        'ID=ubuntu\nPRETTY_NAME="Ubuntu 24.04 LTS"\nVERSION_ID="24.04"\n',
      );

      expect(
        SystemInfo.getOsName(osReleasePath: osFile.path),
        equals('Ubuntu 24.04 LTS'),
      );

      osFile.writeAsStringSync('ID=debian\nNAME=Debian\n');
      expect(
        SystemInfo.getOsName(osReleasePath: osFile.path),
        equals('Debian'),
      );
    });

    test('getOsName falls back safely when file is missing', () {
      final osName = SystemInfo.getOsName(osReleasePath: '/non/existent/path');
      expect(osName, isNotEmpty);
    });

    test(
      'formatDiagnosticDetails formats correctly and contains no secrets',
      () {
        final report = SystemInfo.formatDiagnosticDetails(
          osName: 'Ubuntu 24.04 LTS',
          sevenZipPath: '/usr/bin/7z',
          sevenZipVersion: '7-Zip 26.00 (x64)',
          par2Path: '/usr/bin/par2',
          par2Version: 'par2cmdline version 1.1.1',
        );

        expect(report, contains('ParityZip v0.1.0'));
        expect(report, contains('OS: Ubuntu 24.04 LTS'));
        expect(report, contains('License: MIT'));
        expect(
          report,
          contains('Repository: https://github.com/JBPATEL06/parityzip'),
        );
        expect(report, contains('7-Zip: /usr/bin/7z (7-Zip 26.00 (x64))'));
        expect(
          report,
          contains('PAR2: /usr/bin/par2 (par2cmdline version 1.1.1)'),
        );
      },
    );
  });

  group('ParityZipAboutDialog Widget', () {
    testWidgets('renders dialog with version, license, links and details', (
      tester,
    ) async {
      const toolStatus = ToolStatus(
        sevenZip: ToolInfo.found('/usr/bin/7z', '7z'),
        par2: ToolInfo.found('/usr/bin/par2', 'par2'),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ParityZipAboutDialog(toolStatus: toolStatus)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ParityZip'), findsOneWidget);
      expect(find.text('v0.1.0 • MIT License'), findsOneWidget);
      expect(
        find.text('https://github.com/JBPATEL06/parityzip'),
        findsOneWidget,
      );
      expect(find.text('Copy details'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);

      // Tap Copy details button
      await tester.tap(find.text('Copy details'));
      await tester.pump();

      expect(find.text('Copied!'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
    });
  });
}
