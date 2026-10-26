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

        // Recovery switch is disabled
        final switchWidget = tester.widget<Switch>(find.byType(Switch).first);
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

      final recoverySwitch = find.byType(Switch).first;

      // Toggle switch OFF
      await tester.tap(recoverySwitch);
      await tester.pumpAndSettle();

      expect(find.byType(Slider), findsNothing);
      expect(find.text('Redundancy: 10%'), findsNothing);

      // Toggle switch back ON
      await tester.tap(recoverySwitch);
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

    testWidgets(
      'Format selector toggles between 7z and ZIP and updates suffix and hint text',
      (tester) async {
        final locator = ToolLocator(
          pathEnv: '/mock/bin',
          isExecutableFile: (p) => true,
        );
        final fakeRunner = FakeProcessRunner();
        final logController = LogController();
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

        // 7z is selected by default
        expect(find.text('.7z'), findsOneWidget);
        expect(
          find.text(
            'ZIP opens on Windows and macOS without extra software. 7z compresses better but needs a tool on macOS and older Windows.',
          ),
          findsOneWidget,
        );

        // Tap ZIP
        await tester.tap(find.text('ZIP'));
        await tester.pumpAndSettle();

        // Suffix updates to .zip
        expect(find.text('.zip'), findsOneWidget);

        // Tap 7z
        await tester.tap(find.text('7z'));
        await tester.pumpAndSettle();

        // Suffix updates back to .7z
        expect(find.text('.7z'), findsOneWidget);
      },
    );

    testWidgets('Encryption section UI, toggling, validation, and clearing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final locator = ToolLocator(
        pathEnv: '/mock/bin',
        isExecutableFile: (p) => true,
      );
      final fakeRunner = FakeProcessRunner();
      final logController = LogController();
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

      // Encryption card is present, switch is off
      expect(find.text('Encryption'), findsOneWidget);
      expect(
        find.text(
          'Protect archive with AES-256 encryption and hide file names.',
        ),
        findsOneWidget,
      );
      expect(find.text('Password'), findsNothing);

      // Find encryption switch (second switch on screen: first is recovery data, second is encryption)
      final switches = find.byType(Switch);
      expect(switches, findsNWidgets(2));
      final encryptSwitch = switches.at(1);

      // Turn on encryption
      await tester.tap(encryptSwitch);
      await tester.pumpAndSettle();

      // Password fields, hint, AES-256 text, and checkbox appear
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Confirm password'), findsOneWidget);
      expect(find.text('Minimum 8 characters'), findsOneWidget);
      expect(find.text('File names are hidden too (AES-256)'), findsOneWidget);
      expect(
        find.text('I understand that a lost password cannot be recovered'),
        findsOneWidget,
      );

      // Select ZIP format -> encryption switch should be disabled with explanation
      await tester.tap(find.text('ZIP'));
      await tester.pumpAndSettle();

      expect(find.text('Encryption is available for 7z only.'), findsOneWidget);
      // Fields are hidden when ZIP is active
      expect(find.text('Minimum 8 characters'), findsNothing);

      // Switch back to 7z -> encryption restored
      await tester.tap(find.text('7z'));
      await tester.pumpAndSettle();

      expect(find.text('Minimum 8 characters'), findsOneWidget);
      expect(find.text('File names are hidden too (AES-256)'), findsOneWidget);
    });

    testWidgets('ProgressCard shows Encrypted (AES-256) badge and note', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final locator = ToolLocator(
        pathEnv: '/mock/bin',
        isExecutableFile: (p) => true,
      );
      final fakeRunner = FakeProcessRunner();
      final logController = LogController();
      final jobController = JobController(
        processRunner: fakeRunner,
        logController: logController,
      );

      // Simulate a completed encrypted job
      jobController.setResultForTest(
        const JobResult.success(
          outputPath: '/tmp/test_enc.7z',
          format: ArchiveFormat.sevenZip,
          outputSizeBytes: 1024,
          isEncrypted: true,
        ),
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

      expect(find.text('Encrypted (AES-256)'), findsOneWidget);
      expect(
        find.text(
          'Open it with 7-Zip or another tool that supports 7z with passwords.',
        ),
        findsOneWidget,
      );
    });
  });
}
