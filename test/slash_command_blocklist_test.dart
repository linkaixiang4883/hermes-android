import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/controllers/slash_command_controller.dart';
import 'package:hermes_android/core/models/slash_command.dart';

void main() {
  test('blocked commands are hidden and cannot execute', () async {
    final controller = SlashCommandController(
      loadCatalog: () async => SlashCommandCatalog.fromResult({
        'pairs': [
          ['compress', 'Compact context'],
          ['mobile-disabled', 'Not useful on a phone'],
        ],
      }),
      blockedCommands: const {'mobile-disabled'},
    );

    expect(await controller.ensureCatalog(), isTrue);
    expect(controller.matches.map((command) => command.name), isNot(contains('mobile-disabled')));
    expect(controller.isExecutable('mobile-disabled'), isFalse);
    expect(controller.isExecutable('compress'), isTrue);
  });
}
