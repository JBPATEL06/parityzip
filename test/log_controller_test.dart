import 'package:flutter_test/flutter_test.dart';
import 'package:parityzip/state/log_controller.dart';

void main() {
  group('LogController', () {
    test('starts empty', () {
      final controller = LogController();
      expect(controller.lineCount, equals(0));
      expect(controller.lines, isEmpty);
      expect(controller.fullText, isEmpty);
    });

    test('adds text and splits on newlines and carriage returns', () {
      final controller = LogController();
      controller.addText('line 1\nline 2\r\nline 3\rline 4');

      expect(controller.lineCount, equals(4));
      expect(
        controller.lines,
        equals(['line 1', 'line 2', 'line 3', 'line 4']),
      );
      expect(controller.fullText, equals('line 1\nline 2\nline 3\nline 4'));
    });

    test('log cap at 5000 lines (drops oldest lines)', () {
      final controller = LogController();

      // Add 5100 lines
      final inputLines = List.generate(5100, (i) => 'Line $i');
      controller.addLines(inputLines);

      expect(controller.lineCount, equals(5000));
      expect(controller.lines.length, equals(5000));
      // First line should now be 'Line 100' (0 to 99 were dropped)
      expect(controller.lines.first, equals('Line 100'));
      expect(controller.lines.last, equals('Line 5099'));
    });

    test('clear resets lines', () {
      final controller = LogController();
      controller.addLine('some line');
      expect(controller.lineCount, equals(1));

      controller.clear();
      expect(controller.lineCount, equals(0));
      expect(controller.lines, isEmpty);
      expect(controller.fullText, isEmpty);
    });

    test('notifies listeners when lines are added', () {
      final controller = LogController();
      var notifications = 0;
      controller.addListener(() {
        notifications++;
      });

      controller.addLine('hello');
      controller.addLines(['world 1', 'world 2']);
      controller.clear();

      expect(notifications, equals(3));
    });
  });
}
