import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parityzip/app.dart';
import 'package:parityzip/core/models.dart';
import 'package:parityzip/core/process_runner.dart';
import 'package:parityzip/core/tool_locator.dart';
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

      // Default active tab: Protect -> "Coming in M2"
      expect(find.text('Coming in M2'), findsOneWidget);

      // Tap "Verify" tab
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();
      expect(find.text('Coming in M4'), findsOneWidget);

      // Tap "Repair" tab
      await tester.tap(find.text('Repair'));
      await tester.pumpAndSettle();
      expect(find.text('Coming in M4'), findsOneWidget);
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
  });
}
