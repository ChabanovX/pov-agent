import 'dart:io';

import 'package:pov_agent/features/assistant/application/models/model_store_state.dart';
import 'package:pov_agent/features/assistant/application/models/verified_asr_model_bundle.dart';
import 'package:pov_agent/features/assistant/application/ports/model_store.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_artifact_downloader.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_bundle_extractor.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_bundle_verifier.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_checksum_verifier.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_directory_provider.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_disk_capacity_gateway.dart';
import 'package:pov_agent/features/assistant/data/models/asr_model_manifest.dart';
import 'package:pov_agent/features/assistant/data/repositories/verified_archive_model_store.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

/// Resolves one pinned ASR archive into a verified local runtime bundle.
///
/// The shared archive store owns download, verification, staging, suspension,
/// and cleanup. This wrapper defines only ASR's required model/token files and
/// application artifact projection.
final class VerifiedAsrModelStore implements CacheVerifyingModelStore<VerifiedAsrModelBundle> {
  /// Creates a store from explicit transport, storage, and archive policies.
  VerifiedAsrModelStore({
    required AsrModelManifest manifest,
    required ModelDirectoryProvider directoryProvider,
    required ModelDiskCapacityGateway diskCapacityGateway,
    required ModelArtifactDownloader downloader,
    required ModelChecksumVerifier checksumVerifier,
    required ModelBundleExtractor bundleExtractor,
    required ModelBundleVerifier bundleVerifier,
  }) : _delegate = VerifiedArchiveModelStore<VerifiedAsrModelBundle>(
         manifest: manifest,
         directoryProvider: directoryProvider,
         diskCapacityGateway: diskCapacityGateway,
         downloader: downloader,
         checksumVerifier: checksumVerifier,
         bundleExtractor: bundleExtractor,
         bundleVerifier: bundleVerifier,
         requiredEntries: [
           ModelBundleEntryRequirement.file(manifest.modelFilename),
           ModelBundleEntryRequirement.file(manifest.tokensFilename),
         ],
         artifactFactory: (directoryPath) => VerifiedAsrModelBundle(
           modelId: manifest.modelId,
           revision: manifest.revision,
           bundleDirectoryPath: directoryPath,
           modelFilePath: _childPath(directoryPath, manifest.modelFilename),
           tokensFilePath: _childPath(directoryPath, manifest.tokensFilename),
           extractedByteSize: manifest.extractedByteSize,
           extractedFileCount: manifest.extractedFileCount,
           bundleTreeSha256: manifest.bundleTreeSha256,
         ),
         closedFailureCode: 'asr_model_store_closed',
         closedFailureMessage: 'The ASR model store is already closed.',
       );

  final VerifiedArchiveModelStore<VerifiedAsrModelBundle> _delegate;

  @override
  ModelStoreState<VerifiedAsrModelBundle> get current => _delegate.current;

  @override
  Stream<ModelStoreState<VerifiedAsrModelBundle>> get states => _delegate.states;

  @override
  Future<AppResult<VerifiedAsrModelBundle>> prepare() => _delegate.prepare();

  @override
  Future<AppResult<bool>> verifyCache() => _delegate.verifyCache();

  @override
  Future<void> suspend() => _delegate.suspend();

  @override
  Future<void> close() => _delegate.close();
}

String _childPath(String parent, String child) {
  return '$parent${Platform.pathSeparator}$child';
}
