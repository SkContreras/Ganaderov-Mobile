import 'dart:convert';
import 'dart:io';

import 'package:ganaderov/core/config/test_backend_config.dart';

void main(List<String> arguments) {
  try {
    if (arguments.length != 2) {
      throw const FormatException(
        'Uso: dart run tool/prepare_test_apk.dart <dart-defines.json> <build-info.json>. Proporciona D4_CLIENT_CONFIG o D4_CLIENT_CONFIG_FILE y ENABLE_D4_SYNC=true|false.',
      );
    }
    final environment = Platform.environment;
    final input = environment['D4_CLIENT_CONFIG']?.trim() ?? '';
    final inputFile = environment['D4_CLIENT_CONFIG_FILE']?.trim() ?? '';
    if ((input.isEmpty && inputFile.isEmpty) ||
        (input.isNotEmpty && inputFile.isNotEmpty)) {
      throw const FormatException(
        'Proporciona exactamente una configuración cliente verificada: JSON o archivo.',
      );
    }
    final flag = environment['ENABLE_D4_SYNC'] ?? 'false';
    if (flag != 'true' && flag != 'false') {
      throw const FormatException('ENABLE_D4_SYNC debe ser true o false.');
    }
    final decoded = jsonDecode(
      input.isNotEmpty ? input : File(inputFile).readAsStringSync(),
    );
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'La configuración cliente debe ser un objeto JSON.',
      );
    }
    final config = TestBackendConfig.parse(decoded, enableD4: flag == 'true');
    const encoder = JsonEncoder.withIndent('  ');
    File(arguments[0])
        .writeAsStringSync('${encoder.convert(config.dartDefines)}\n');
    File(arguments[1]).writeAsStringSync(
      '${encoder.convert({...config.buildInfo, 'gitCommit': environment['GITHUB_SHA'] ?? '', 'workflowRun': environment['GITHUB_RUN_ID'] ?? '', 'webBackendCommit': environment['WEB_BACKEND_REF'] ?? '', 'flutterVersion': '3.50.1'})}\n',
    );
    stdout.writeln(
      'Configuración ${config.profile} validada. D4: ${config.enableD4}. No se imprime la clave cliente.',
    );
  } on FormatException catch (error) {
    stderr.writeln('Configuración de APK rechazada: ${error.message}');
    exitCode = 64;
  } on FileSystemException {
    stderr.writeln('No se pudo leer o escribir la configuración del APK.');
    exitCode = 74;
  }
}
