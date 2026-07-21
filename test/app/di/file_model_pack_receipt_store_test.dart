import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/app/di/file_model_pack_receipt_store.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_directory_provider.dart';

void main() {
  late Directory sandbox;
  late Directory modelDirectory;
  late FileModelPackReceiptStore store;

  File receiptFile() {
    return File(
      '${modelDirectory.path}${Platform.pathSeparator}model-pack.receipt',
    );
  }

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('pov_pack_receipt_test.');
    modelDirectory = Directory(
      '${sandbox.path}${Platform.pathSeparator}models',
    );
    store = FileModelPackReceiptStore(
      _FixedModelDirectoryProvider(modelDirectory),
    );
  });

  tearDown(() {
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  test('real filesystem boundary creates, replaces, and clears a receipt', () async {
    expect(await store.read(), isNull);

    await store.write('pack-v1');

    expect(await store.read(), 'pack-v1');
    expect(receiptFile().readAsStringSync(), 'pack-v1');
    expect(File('${receiptFile().path}.part').existsSync(), isFalse);

    await store.write('pack-v2');

    expect(await store.read(), 'pack-v2');
    expect(receiptFile().readAsStringSync(), 'pack-v2');
    expect(File('${receiptFile().path}.part').existsSync(), isFalse);

    await store.clear();

    expect(await store.read(), isNull);
    expect(receiptFile().existsSync(), isFalse);
  });

  test('blank or whitespace-only persisted content is treated as absent', () async {
    await modelDirectory.create(recursive: true);
    await receiptFile().writeAsString('  \n');

    expect(await store.read(), isNull);

    await receiptFile().writeAsString('  pack-v3\n');

    expect(await store.read(), 'pack-v3');
  });
}

final class _FixedModelDirectoryProvider implements ModelDirectoryProvider {
  const _FixedModelDirectoryProvider(this.directory);

  final Directory directory;

  @override
  Future<Directory> resolve() async => directory;
}
