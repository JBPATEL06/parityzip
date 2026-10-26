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

    test('redacts secret password string from added text and fullText', () {
      final controller = LogController();
      controller.setRedactSecret('MySuperSecretPassword123');

      controller.addLine(
        'User entered command with MySuperSecretPassword123 as arg',
      );
      controller.addLines([
        'Error: failed with password MySuperSecretPassword123!',
        'Normal line without secret',
      ]);

      expect(
        controller.lines[0],
        equals('User entered command with *** as arg'),
      );
      expect(controller.lines[1], equals('Error: failed with password ***!'));
      expect(controller.lines[2], equals('Normal line without secret'));

      expect(controller.fullText, isNot(contains('MySuperSecretPassword123')));
      expect(controller.fullText, contains('***'));

      // Clearing secret returns to normal adding
      controller.setRedactSecret(null);
      controller.addLine('Now secret MySuperSecretPassword123 is not redacted');
      expect(controller.lines.last, contains('MySuperSecretPassword123'));
    });
  });
}
