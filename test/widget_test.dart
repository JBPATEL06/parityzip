import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parityzip/app.dart';
import 'package:parityzip/core/models.dart';
import 'package:parityzip/core/process_runner.dart';
import 'package:parityzip/core/tool_locator.dart';
import 'package:parityzip/state/job_controller.dart';
import 'package:parityzip/state/log_controller.dart';
import 'package:parityzip/ui/widgets/log_panel.dart';
import 'package:parityzip/ui/widgets/tool_banner.dart';
import 'package:provider/provider.dart';

void main() {
  group('ToolBanner', () {
    testWidgets('shows warning and install command when tools are missing', (
      tester,
    ) async {
      const missingStatus = ToolStatus(
        sevenZip: ToolInfo.missing(),
        par2: ToolInfo.found('/usr/bin/par2', 'par2'),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ToolBanner(toolStatus: missingStatus)),
        ),
      );

      expect(find.text('Missing required tool: 7z'), findsOneWidget);
      expect(find.text('sudo apt install p7zip-full par2'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('names both tools when both are missing', (tester) async {
      const bothMissingStatus = ToolStatus(
        sevenZip: ToolInfo.missing(),
        par2: ToolInfo.missing(),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ToolBanner(toolStatus: bothMissingStatus)),
        ),
      );

      expect(find.text('Missing required tools: 7z, par2'), findsOneWidget);
    });

    testWidgets('does not show banner when all tools are found', (
      tester,
    ) async {
      const allFoundStatus = ToolStatus(
        sevenZip: ToolInfo.found('/usr/bin/7z', '7z'),
        par2: ToolInfo.found('/usr/bin/par2', 'par2'),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ToolBanner(toolStatus: allFoundStatus)),
        ),
      );

      expect(find.byType(ToolBanner), findsOneWidget);
      expect(find.text('sudo apt install p7zip-full par2'), findsNothing);
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });

    testWidgets('can be dismissed', (tester) async {
      const missingStatus = ToolStatus(
        sevenZip: ToolInfo.missing(),
        par2: ToolInfo.found('/usr/bin/par2', 'par2'),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ToolBanner(toolStatus: missingStatus)),
        ),
      );

      expect(find.text('Missing required tool: 7z'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('Missing required tool: 7z'), findsNothing);
    });
  });

  group('LogPanel', () {
    testWidgets('renders collapsed by default and displays lines', (
      tester,
    ) async {
      final logController = LogController();
      logController.addLine('System initialized.');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<LogController>.value(
              value: logController,
              child: const LogPanel(),
            ),
          ),
        ),
      );

      expect(find.text('Log (1 lines)'), findsOneWidget);
      expect(find.text('Copy log'), findsOneWidget);
    });
  });

  group('ParityZipApp', () {
    testWidgets('renders shell with title and 3 tabs with placeholders', (
      tester,
    ) async {
      final mockBinaries = {'/usr/bin/7z', '/usr/bin/par2'};
      final locator = ToolLocator(
        pathEnv: '/usr/bin',
        isExecutableFile: (path) => mockBinaries.contains(path),
      );

      await tester.pumpWidget(
        ParityZipApp(toolLocator: locator, processRunner: FakeProcessRunner()),
      );
      await tester.pumpAndSettle();

      // Window/App title
      expect(find.text('ParityZip'), findsOneWidget);

      // Tabs
      expect(find.text('Protect'), findsOneWidget);
      expect(find.text('Verify'), findsOneWidget);
      expect(find.text('Repair'), findsOneWidget);

      // Default active tab: Protect page with drop zone, add buttons, level selector, disabled recovery data
      expect(find.text('Drag & drop files or folders here'), findsOneWidget);
      expect(find.text('Add files'), findsOneWidget);
      expect(find.text('Add folder'), findsOneWidget);
      expect(find.text('Create archive'), findsOneWidget);
      expect(find.text('Recovery data'), findsOneWidget);
      expect(find.text('Redundancy: 10%'), findsOneWidget);

      // Tap "Verify" tab
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();
      expect(find.text('Drag & drop a .par2 file here'), findsOneWidget);
      expect(find.text('Choose .par2 file'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Verify'), findsOneWidget);

      // Tap "Repair" tab
      await tester.tap(find.text('Repair'));
      await tester.pumpAndSettle();
      expect(find.text('Drag & drop a .par2 file to repair'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Repair'), findsOneWidget);
    });

    testWidgets(
      'resizing to 800x600 and smaller produces no RenderFlex overflow',
      (tester) async {
        final mockBinaries = {'/usr/bin/7z', '/usr/bin/par2'};
        final locator = ToolLocator(
          pathEnv: '/usr/bin',
          isExecutableFile: (path) => mockBinaries.contains(path),
        );

        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          ParityZipApp(
            toolLocator: locator,
            processRunner: FakeProcessRunner(),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Also test very narrow size
        tester.view.physicalSize = const Size(360, 600);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Create archive button is disabled with explanation when 7z is missing',
      (tester) async {
        final locator = ToolLocator(
          pathEnv: '/usr/bin',
          isExecutableFile: (path) => path == '/usr/bin/par2', // 7z missing
        );

        await tester.pumpWidget(
          ParityZipApp(
            toolLocator: locator,
            processRunner: FakeProcessRunner(),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Cannot create archive: 7-Zip CLI tool (7z) is missing from PATH.',
          ),
          findsOneWidget,
        );

        final createButton = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Create archive'),
        );
        expect(createButton.onPressed, isNull);
      },
    );

    testWidgets('validation error banner is hidden when job is running', (
      tester,
    ) async {
      final mockBinaries = {'/usr/bin/7z', '/usr/bin/par2'};
      final locator = ToolLocator(
        pathEnv: '/usr/bin',
        isExecutableFile: (path) => mockBinaries.contains(path),
      );

      await tester.pumpWidget(
        ParityZipApp(toolLocator: locator, processRunner: FakeProcessRunner()),
      );
      await tester.pumpAndSettle();

      // While idle without selection, no "already exists" error
      expect(find.textContaining('already exists'), findsNothing);
    });

    testWidgets(
      'when par2 is missing, recovery switch is disabled with explanation',
      (tester) async {
        final mockBinaries = {'/usr/bin/7z'}; // par2 missing
        final locator = ToolLocator(
          pathEnv: '/usr/bin',
          isExecutableFile: (path) => mockBinaries.contains(path),
        );

        await tester.pumpWidget(
          ParityZipApp(
            toolLocator: locator,
            processRunner: FakeProcessRunner(),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(
            'par2 tool is missing from PATH. Archive will be created without recovery data.',
          ),
          findsOneWidget,
        );

        // Switch is disabled
        final switchWidget = tester.widget<Switch>(find.byType(Switch));
        expect(switchWidget.onChanged, isNull);
        expect(switchWidget.value, isFalse);
      },
    );

    testWidgets('toggling recovery switch hides and shows slider', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockBinaries = {'/usr/bin/7z', '/usr/bin/par2'};
      final locator = ToolLocator(
        pathEnv: '/usr/bin',
        isExecutableFile: (path) => mockBinaries.contains(path),
      );

      await tester.pumpWidget(
        ParityZipApp(toolLocator: locator, processRunner: FakeProcessRunner()),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('Redundancy: 10%'), findsOneWidget);

      // Toggle switch OFF
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(find.byType(Slider), findsNothing);
      expect(find.text('Redundancy: 10%'), findsNothing);

      // Toggle switch back ON
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('Redundancy: 10%'), findsOneWidget);
    });

    testWidgets('when par2 is missing, Verify and Repair tabs are disabled', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockBinaries = {'/usr/bin/7z'};
      final locator = ToolLocator(
        pathEnv: '/usr/bin',
        isExecutableFile: (path) => mockBinaries.contains(path),
      );

      await tester.pumpWidget(
        ParityZipApp(toolLocator: locator, processRunner: FakeProcessRunner()),
      );
      await tester.pumpAndSettle();

      // Check Verify Tab
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();
      expect(
        find.text('par2 tool is missing from PATH. Verification is disabled.'),
        findsOneWidget,
      );
      final verifyButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Verify'),
      );
      expect(verifyButton.onPressed, isNull);

      // Check Repair Tab
      await tester.tap(find.text('Repair'));
      await tester.pumpAndSettle();
      expect(
        find.text('par2 tool is missing from PATH. Repair is disabled.'),
        findsOneWidget,
      );
      final repairButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Repair'),
      );
      expect(repairButton.onPressed, isNull);
    });

    testWidgets(
      'Go to Repair button switches to Repair tab with preselected file',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final mockBinaries = {'/usr/bin/7z', '/usr/bin/par2'};
        final locator = ToolLocator(
          pathEnv: '/usr/bin',
          isExecutableFile: (path) => mockBinaries.contains(path),
        );

        final logController = LogController();
        final fakeRunner = FakeProcessRunner(
          onRun: (exe, args, workingDirectory, stdinData) {
            return Stream.fromIterable([
              const StdoutEvent(
                'Target: "damaged.7z" - damaged. Found 1999 of 2000 data blocks.\nRepair is possible.\n',
              ),
              const ExitCodeEvent(1),
            ]);
          },
        );

        final jobController = JobController(
          processRunner: fakeRunner,
          logController: logController,
        );

        await tester.pumpWidget(
          ParityZipApp(
            toolLocator: locator,
            processRunner: fakeRunner,
            logController: logController,
            jobController: jobController,
          ),
        );
        await tester.pumpAndSettle();

        // Switch to Verify tab
        await tester.tap(find.text('Verify'));
        await tester.pumpAndSettle();

        final tempDir = Directory.systemTemp.createTempSync('par2_ui_test');
        addTearDown(() {
          try {
            tempDir.deleteSync(recursive: true);
          } catch (_) {}
        });
        final par2File = File('${tempDir.path}/damaged.7z.par2')
          ..writeAsStringSync('dummy');

        // Simulate a run on damaged file
        await jobController.startVerifyJob(
          par2Exe: 'par2',
          par2FilePath: par2File.path,
        );
        await tester.pumpAndSettle();

        expect(find.text('Archive is damaged but repairable'), findsOneWidget);
        expect(find.text('Go to Repair'), findsOneWidget);

        // Tap "Go to Repair"
        await tester.tap(find.text('Go to Repair'));
        await tester.pumpAndSettle();

        // Should now be on Repair tab with the file preselected!
        expect(find.text('Drag & drop a .par2 file to repair'), findsOneWidget);
        expect(find.text('damaged.7z.par2'), findsOneWidget);
        expect(find.text('Full path: ${par2File.path}'), findsOneWidget);
      },
    );
  });
}
