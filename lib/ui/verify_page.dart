import 'package:flutter/material.dart';

import 'widgets/log_panel.dart';

class VerifyPage extends StatelessWidget {
  const VerifyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Text('Coming in M4', style: TextStyle(fontSize: 18)),
            ),
          ),
          SizedBox(height: 16),
          LogPanel(),
        ],
      ),
    );
  }
}
