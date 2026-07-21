import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:pov_agent/features/assistant/data/models/model_store_exceptions.dart';

/// Extracts one checksum-verified Piper archive into caller-owned staging.
// Extraction remains injectable so repository tests can control lifecycle races.
// ignore: one_member_abstracts
abstract interface class PiperBundleExtractor {
  /// Expands [archivePath] below an empty [destinationPath].
  ///
  /// [temporaryTarPath] must be on the same capacity-accounted filesystem and
  /// is removed before this operation settles, including on extraction error.
  Future<void> extract({
    required String archivePath,
    required String destinationPath,
    required String temporaryTarPath,
    required int expectedTarByteSize,
  });
}

/// Streams tar.bz2 extraction on a background isolate.
final class IsolatePiperBundleExtractor implements PiperBundleExtractor {
  /// Creates the production archive extractor.
  const IsolatePiperBundleExtractor();

  @override
  Future<void> extract({
    required String archivePath,
    required String destinationPath,
    required String temporaryTarPath,
    required int expectedTarByteSize,
  }) {
    return Isolate.run(
      () => _extractArchive(
        archivePath: archivePath,
        destinationPath: destinationPath,
        temporaryTarPath: temporaryTarPath,
        expectedTarByteSize: expectedTarByteSize,
      ),
      debugName: 'pov-piper-extraction',
    );
  }
}

void _extractArchive({
  required String archivePath,
  required String destinationPath,
  required String temporaryTarPath,
  required int expectedTarByteSize,
}) {
  final destination = Directory(destinationPath);
  final temporaryTar = File(temporaryTarPath);
  destination.createSync(recursive: true);
  if (temporaryTar.existsSync()) temporaryTar.deleteSync();

  try {
    _expandBzip2Archive(
      archivePath: archivePath,
      temporaryTarPath: temporaryTarPath,
    );
    final actualTarByteSize = temporaryTar.lengthSync();
    if (actualTarByteSize != expectedTarByteSize) {
      throw ModelIntegrityException(
        reason:
            'the expanded Piper archive contained $actualTarByteSize '
            'bytes; expected $expectedTarByteSize',
      );
    }
    _extractTar(
      temporaryTarPath: temporaryTarPath,
      destinationPath: destination.absolute.path,
    );
  } on FileSystemException {
    rethrow;
  } on ModelIntegrityException {
    rethrow;
  } on Object catch (error) {
    throw ModelIntegrityException(
      reason: 'the pinned Piper archive could not be extracted: $error',
    );
  } finally {
    if (temporaryTar.existsSync()) temporaryTar.deleteSync();
  }
}

void _expandBzip2Archive({
  required String archivePath,
  required String temporaryTarPath,
}) {
  final input = InputFileStream(archivePath);
  final output = OutputFileStream(temporaryTarPath);
  try {
    final decoded = BZip2Decoder().decodeStream(
      input,
      output,
      verify: true,
    );
    if (!decoded) {
      throw const ModelIntegrityException(
        reason: 'the pinned Piper bzip2 stream is malformed',
      );
    }
  } finally {
    input.closeSync();
    output.closeSync();
  }
}

void _extractTar({
  required String temporaryTarPath,
  required String destinationPath,
}) {
  final input = InputFileStream(temporaryTarPath);
  Archive? archive;
  try {
    archive = TarDecoder().decodeStream(input);
    for (final entry in archive) {
      if (entry.isSymbolicLink) {
        throw const ModelIntegrityException(
          reason: 'the pinned Piper archive contains a symbolic link',
        );
      }
      final relativePath = _safeRelativePath(entry.name);
      final outputPath = '$destinationPath${Platform.pathSeparator}$relativePath';
      if (entry.isDirectory) {
        Directory(outputPath).createSync(recursive: true);
      } else if (entry.isFile) {
        File(outputPath).parent.createSync(recursive: true);
        final output = OutputFileStream(outputPath);
        try {
          entry.writeContent(output);
        } finally {
          output.closeSync();
        }
      } else {
        throw const ModelIntegrityException(
          reason: 'the pinned Piper archive contains an unsupported entry',
        );
      }
    }
  } finally {
    input.closeSync();
    archive?.clearSync();
  }
}

String _safeRelativePath(String archivePath) {
  final portablePath = archivePath.replaceAll(r'\', '/');
  if (portablePath.startsWith('/')) {
    throw const ModelIntegrityException(
      reason: 'the pinned Piper archive contains an absolute path',
    );
  }
  final segments = portablePath.split('/').where((segment) => segment.isNotEmpty).toList();
  if (segments.isEmpty || segments.any((segment) => segment == '.' || segment == '..')) {
    throw const ModelIntegrityException(
      reason: 'the pinned Piper archive contains a path outside staging',
    );
  }
  return segments.join(Platform.pathSeparator);
}
