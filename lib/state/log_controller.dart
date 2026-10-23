import 'package:flutter/foundation.dart';

class LogController extends ChangeNotifier {
  static const int maxLines = 5000;
  final List<String> _lines = [];

  List<String> get lines => List.unmodifiable(_lines);
  int get lineCount => _lines.length;
  String get fullText => _lines.join('\n');

  void addText(String text) {
    if (text.isEmpty) return;

    final splitLines = text.split(RegExp(r'\r\n|\r|\n'));
    for (final line in splitLines) {
      if (line.isNotEmpty) {
        _lines.add(line);
      }
    }

    _truncateToCap();
    notifyListeners();
  }

  void addLine(String line) {
    addText(line);
  }

  void addLines(Iterable<String> lines) {
    for (final line in lines) {
      final splitLines = line.split(RegExp(r'\r\n|\r|\n'));
      for (final l in splitLines) {
        if (l.isNotEmpty) {
          _lines.add(l);
        }
      }
    }
    _truncateToCap();
    notifyListeners();
  }

  void _truncateToCap() {
    if (_lines.length > maxLines) {
      _lines.removeRange(0, _lines.length - maxLines);
    }
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }
}
