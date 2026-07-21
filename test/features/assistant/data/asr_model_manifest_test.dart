import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/assistant/data/models/asr_model_manifest.dart';

const _archiveSha = '479759fbd5c69c909e7175d7773105a1bfabf82fa533de68c546c89d85f234e8';
const _treeSha = '8ec5fb017edb1fc389101bf235cbc13063185657b91752b9b17fa649eeade040';

void main() {
  test('retains archive, extracted-tree, and runtime entry metadata', () {
    final manifest = _manifest();

    expect(manifest.downloadUri.scheme, 'https');
    expect(manifest.archiveByteSize, 99459493);
    expect(manifest.archiveSha256, _archiveSha);
    expect(manifest.expandedArchiveByteSize, 132891648);
    expect(manifest.extractedByteSize, 132884963);
    expect(manifest.extractedFileCount, 6);
    expect(manifest.bundleTreeSha256, _treeSha);
    expect(
      manifest.archiveRoot,
      'sherpa-onnx-nemo-streaming-fast-conformer-ctc-en-80ms-int8',
    );
    expect(manifest.modelFilename, 'model.int8.onnx');
    expect(manifest.tokensFilename, 'tokens.txt');
  });

  test('rejects non-network URLs and malformed integrity metadata', () {
    expect(
      () => _manifest(downloadUrl: 'file:///tmp/asr.tar.bz2'),
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
    expect(() => _manifest(archiveByteSize: 0), throwsArgumentError);
    expect(() => _manifest(expandedArchiveByteSize: 0), throwsArgumentError);
    expect(() => _manifest(extractedFileCount: 0), throwsArgumentError);
    expect(() => _manifest(downloadReserveBytes: -1), throwsArgumentError);
  });

  test('rejects paths that can collide or escape the staging root', () {
    expect(() => _manifest(archiveRoot: '..'), throwsArgumentError);
    expect(
      () => _manifest(modelFilename: '../model.int8.onnx'),
      throwsArgumentError,
    );
    expect(
      () => _manifest(tokensFilename: r'folder\tokens.txt'),
      throwsArgumentError,
    );
    expect(
      () => _manifest(
        modelFilename: 'tokens.txt',
        tokensFilename: 'TOKENS.TXT',
      ),
      throwsArgumentError,
    );
    expect(
      () => _manifest(archiveRoot: 'ASR.TAR.BZ2'),
      throwsArgumentError,
    );
  });
}

AsrModelManifest _manifest({
  String downloadUrl = 'https://example.test/sherpa-onnx-nemo-streaming-fast-conformer-ctc-en-80ms-int8.tar.bz2',
  int archiveByteSize = 99459493,
  int expandedArchiveByteSize = 132891648,
  String archiveSha256 = _archiveSha,
  int extractedFileCount = 6,
  String bundleTreeSha256 = _treeSha,
  String archiveRoot = 'sherpa-onnx-nemo-streaming-fast-conformer-ctc-en-80ms-int8',
  String modelFilename = 'model.int8.onnx',
  String tokensFilename = 'tokens.txt',
  int downloadReserveBytes = 33554432,
}) {
  return AsrModelManifest(
    modelId: 'nemo-streaming-fast-conformer-ctc-en-80ms-int8',
    downloadUrl: downloadUrl,
    revision: 'asr-models',
    archiveFilename: 'asr.tar.bz2',
    archiveByteSize: archiveByteSize,
    archiveSha256: archiveSha256,
    expandedArchiveByteSize: expandedArchiveByteSize,
    extractedByteSize: 132884963,
    extractedFileCount: extractedFileCount,
    bundleTreeSha256: bundleTreeSha256,
    archiveRoot: archiveRoot,
    modelFilename: modelFilename,
    tokensFilename: tokensFilename,
    license: 'NVIDIA-NGC-TOU',
    downloadReserveBytes: downloadReserveBytes,
  );
}
