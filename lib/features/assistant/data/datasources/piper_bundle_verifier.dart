import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:pov_agent/features/assistant/data/models/model_store_exceptions.dart';

/// Integrity facts derived from every regular file in a Piper bundle.
final class PiperBundleVerification {
  /// Creates one canonical bundle-tree result.
  const PiperBundleVerification({
    required this.byteSize,
    required this.fileCount,
    required this.treeSha256,
  });

  /// Sum of all regular-file byte lengths.
  final int byteSize;

  /// Number of regular files included in [treeSha256].
  final int fileCount;

  /// SHA-256 of sorted `<file-sha>  <relative-path>\n` records.
  final String treeSha256;
}

/// Computes canonical integrity metadata for an extracted Piper bundle.
// Verification remains injectable so repository tests can control lifecycle races.
// ignore: one_member_abstracts
abstract interface class PiperBundleVerifier {
  /// Hashes all regular files below [bundleDirectoryPath].
  Future<PiperBundleVerification> verify(String bundleDirectoryPath);
}

/// Hashes the complete bundle tree away from Flutter's UI isolate.
final class IsolatePiperBundleVerifier implements PiperBundleVerifier {
  /// Creates the production bundle verifier.
  const IsolatePiperBundleVerifier();

  @override
  Future<PiperBundleVerification> verify(String bundleDirectoryPath) {
    return Isolate.run(
      () => _verifyBundle(bundleDirectoryPath),
      debugName: 'pov-piper-verification',
    );
  }
}

Future<PiperBundleVerification> _verifyBundle(
  String bundleDirectoryPath,
) async {
  final root = Directory(bundleDirectoryPath).absolute;
  // Do not follow a cache-root link: lexical child checks cannot prove that
  // its target remains inside the application-owned model directory.
  final rootType = FileSystemEntity.typeSync(root.path, followLinks: false);
  if (rootType != FileSystemEntityType.directory) {
    throw const ModelIntegrityException(
      reason: 'the extracted Piper bundle root is missing or is not a directory',
    );
  }

  final files = <({File file, String relativePath})>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is Link) {
      throw const ModelIntegrityException(
        reason: 'the extracted Piper bundle contains a symbolic link',
      );
    }
    if (entity is! File) continue;
    final absolutePath = entity.absolute.path;
    final rootPrefix = '${root.path}${Platform.pathSeparator}';
    if (!absolutePath.startsWith(rootPrefix)) {
      throw const ModelIntegrityException(
        reason: 'the extracted Piper bundle escaped its cache root',
      );
    }
    files.add((
      file: entity,
      relativePath: absolutePath.substring(rootPrefix.length).replaceAll(Platform.pathSeparator, '/'),
    ));
  }
  files.sort((left, right) => left.relativePath.compareTo(right.relativePath));

  var byteSize = 0;
  final canonicalRecords = StringBuffer();
  for (final entry in files) {
    byteSize += await entry.file.length();
    final digest = await sha256.bind(entry.file.openRead()).first;
    canonicalRecords
      ..write(digest)
      ..write('  ')
      ..write(entry.relativePath)
      ..write('\n');
  }

  return PiperBundleVerification(
    byteSize: byteSize,
    fileCount: files.length,
    treeSha256: sha256.convert(utf8.encode(canonicalRecords.toString())).toString(),
  );
}
