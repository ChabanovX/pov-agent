import 'dart:io';

import 'package:pov_agent/app/model_pack/model_pack_receipt_store.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_directory_provider.dart';

/// Stores one model-pack fingerprint beside verified model artifacts.
final class FileModelPackReceiptStore implements ModelPackReceiptStore {
  /// Creates the receipt store for the configured model directory.
  const FileModelPackReceiptStore(this._directoryProvider);

  final ModelDirectoryProvider _directoryProvider;

  @override
  Future<String?> read() async {
    final file = await _receiptFile();
    // Root setup runs on the UI isolate, so keep its metadata probe asynchronous.
    // ignore: avoid_slow_async_io
    if (!await file.exists()) return null;
    final fingerprint = (await file.readAsString()).trim();
    return fingerprint.isEmpty ? null : fingerprint;
  }

  @override
  Future<void> write(String fingerprint) async {
    final directory = await _directoryProvider.resolve();
    await directory.create(recursive: true);
    final target = File(
      '${directory.path}${Platform.pathSeparator}model-pack.receipt',
    );
    final staging = File('${target.path}.part');
    await staging.writeAsString(fingerprint, flush: true);
    await staging.rename(target.path);
  }

  @override
  Future<void> clear() async {
    final file = await _receiptFile();
    // Root setup runs on the UI isolate, so keep its metadata probe asynchronous.
    // ignore: avoid_slow_async_io
    if (await file.exists()) await file.delete();
  }

  Future<File> _receiptFile() async {
    final directory = await _directoryProvider.resolve();
    return File(
      '${directory.path}${Platform.pathSeparator}model-pack.receipt',
    );
  }
}
