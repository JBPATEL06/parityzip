import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yaru/yaru.dart';

import 'core/models.dart';
import 'core/process_runner.dart';
import 'core/tool_locator.dart';
import 'state/log_controller.dart';
import 'ui/protect_page.dart';
import 'ui/repair_page.dart';
import 'ui/verify_page.dart';
import 'ui/widgets/tool_banner.dart';

class ParityZipApp extends StatelessWidget {
  final ToolLocator? toolLocator;
  final ProcessRunner? processRunner;
  final LogController? logController;

  const ParityZipApp({
    super.key,
    this.toolLocator,
    this.processRunner,
    this.logController,
  });

  @override
  Widget build(BuildContext context) {
    final locator = toolLocator ?? ToolLocator();
    final toolStatus = locator.locate();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LogController>(
          create: (_) => logController ?? LogController(),
        ),
        Provider<ToolStatus>.value(value: toolStatus),
        Provider<ProcessRunner>.value(
          value: processRunner ?? const RealProcessRunner(),
        ),
      ],
      child: YaruTheme(
        builder: (context, yaru, child) {
          return MaterialApp(
            title: 'ParityZip',
            debugShowCheckedModeBanner: false,
            theme: yaru.theme,
            darkTheme: yaru.darkTheme,
            themeMode: ThemeMode.system,
            home: const AppShell(),
          );
        },
      ),
    );
  }
}

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ParityZip'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Protect'),
              Tab(text: 'Verify'),
              Tab(text: 'Repair'),
            ],
          ),
        ),
        body: Column(
          children: const [
            ToolBanner(),
            Expanded(
              child: TabBarView(
                children: [ProtectPage(), VerifyPage(), RepairPage()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
