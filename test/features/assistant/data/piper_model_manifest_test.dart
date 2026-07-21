import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/assistant/data/models/piper_model_manifest.dart';

const _archiveSha = '24dc3bd77dd48c291e52c297878d3437c9492f245d823d7f6a06c4bbb67f4b6b';
const _treeSha = 'a38256a8fada764a1e7b450c5f307b7b5de159e137af1a6aae0b2326f355bc3b';

void main() {
  test('retains archive and extracted-tree integrity metadata', () {
    final manifest = _manifest();

    expect(manifest.downloadUri.scheme, 'https');
    expect(manifest.archiveByteSize, 21090429);
    expect(manifest.archiveSha256, _archiveSha);
    expect(manifest.expandedArchiveByteSize, 37662720);
    expect(manifest.extractedByteSize, 37347875);
    expect(manifest.extractedFileCount, 359);
    expect(manifest.bundleTreeSha256, _treeSha);
    expect(manifest.archiveRoot, 'vits-piper-en_US-ljspeech-medium-int8');
    expect(manifest.modelFilename, 'en_US-ljspeech-medium.onnx');
    expect(manifest.tokensFilename, 'tokens.txt');
    expect(manifest.espeakDataDirectory, 'espeak-ng-data');
  });

  test('rejects non-network URLs and malformed integrity metadata', () {
    expect(
      () => _manifest(downloadUrl: 'file:///tmp/piper.tar.bz2'),
      throwsArgumentError,
    );
    expect(
      () => _manifest(archiveSha256: _archiveSha.toUpperCase()),
      throwsArgumentError,
    );
    expect(
      () => _manifest(bundleTreeSha256: 'short'),
      throwsArgumentError,
    );
    expect(
      () => _manifest(archiveByteSize: 0),
      throwsArgumentError,
    );
    expect(
      () => _manifest(expandedArchiveByteSize: 0),
      throwsArgumentError,
    );
    expect(
      () => _manifest(extractedFileCount: 0),
      throwsArgumentError,
    );
  });

  test('rejects archive paths that could escape the staging root', () {
    expect(
      () => _manifest(archiveRoot: '..'),
      throwsArgumentError,
    );
    expect(
      () => _manifest(modelFilename: '../voice.onnx'),
      throwsArgumentError,
    );
    expect(
      () => _manifest(tokensFilename: r'folder\tokens.txt'),
      throwsArgumentError,
    );
    expect(
      () => _manifest(espeakDataDirectory: 'data/espeak-ng-data'),
      throwsArgumentError,
    );
    expect(
      () => _manifest(
        modelFilename: 'voice.onnx',
        tokensFilename: 'VOICE.ONNX',
      ),
      throwsArgumentError,
    );
    expect(
      () => _manifest(archiveRoot: 'PIPER.TAR.BZ2'),
      throwsArgumentError,
    );
  });
}

PiperModelManifest _manifest({
  String downloadUrl = 'https://example.test/vits-piper-en_US-ljspeech-medium-int8.tar.bz2',
  int archiveByteSize = 21090429,
  int expandedArchiveByteSize = 37662720,
  String archiveSha256 = _archiveSha,
  int extractedFileCount = 359,
  String bundleTreeSha256 = _treeSha,
  String archiveRoot = 'vits-piper-en_US-ljspeech-medium-int8',
  String modelFilename = 'en_US-ljspeech-medium.onnx',
  String tokensFilename = 'tokens.txt',
  String espeakDataDirectory = 'espeak-ng-data',
}) {
  return PiperModelManifest(
    modelId: 'piper-ljspeech',
    downloadUrl: downloadUrl,
    revision: 'tts-models',
    archiveFilename: 'piper.tar.bz2',
    archiveByteSize: archiveByteSize,
    archiveSha256: archiveSha256,
    expandedArchiveByteSize: expandedArchiveByteSize,
    extractedByteSize: 37347875,
    extractedFileCount: extractedFileCount,
    bundleTreeSha256: bundleTreeSha256,
    archiveRoot: archiveRoot,
    modelFilename: modelFilename,
    tokensFilename: tokensFilename,
    espeakDataDirectory: espeakDataDirectory,
    license: 'Public-Domain',
    downloadReserveBytes: 33554432,
  );
}
