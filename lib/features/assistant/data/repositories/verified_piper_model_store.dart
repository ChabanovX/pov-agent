import 'dart:io';

import 'package:pov_agent/features/assistant/application/models/model_store_state.dart';
import 'package:pov_agent/features/assistant/application/models/verified_piper_model_bundle.dart';
import 'package:pov_agent/features/assistant/application/ports/model_store.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_artifact_downloader.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_checksum_verifier.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_directory_provider.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_disk_capacity_gateway.dart';
import 'package:pov_agent/features/assistant/data/datasources/piper_bundle_extractor.dart';
import 'package:pov_agent/features/assistant/data/datasources/piper_bundle_verifier.dart';
import 'package:pov_agent/features/assistant/data/models/piper_model_manifest.dart';
import 'package:pov_agent/features/assistant/data/repositories/verified_archive_model_store.dart';
import 'package:pov_agent/shared/domain/app_result.dart';

/// Resolves one pinned Piper archive into a verified local voice bundle.
///
/// The shared archive store owns download, verification, staging, suspension,
/// and cleanup. This wrapper defines only Piper's required runtime entries and
/// application artifact projection.
final class VerifiedPiperModelStore implements ModelStore<VerifiedPiperModelBundle> {
  /// Creates a store from explicit transport, storage, and archive policies.
  VerifiedPiperModelStore({
    required PiperModelManifest manifest,
    required ModelDirectoryProvider directoryProvider,
    required ModelDiskCapacityGateway diskCapacityGateway,
    required ModelArtifactDownloader downloader,
    required ModelChecksumVerifier checksumVerifier,
    required PiperBundleExtractor bundleExtractor,
    required PiperBundleVerifier bundleVerifier,
  }) : _delegate = VerifiedArchiveModelStore<VerifiedPiperModelBundle>(
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
           ModelBundleEntryRequirement.directory(manifest.espeakDataDirectory),
         ],
         artifactFactory: (directoryPath) => VerifiedPiperModelBundle(
           modelId: manifest.modelId,
           revision: manifest.revision,
           bundleDirectoryPath: directoryPath,
           modelFilePath: _childPath(directoryPath, manifest.modelFilename),
           tokensFilePath: _childPath(directoryPath, manifest.tokensFilename),
           espeakDataDirectoryPath: _childPath(
             directoryPath,
             manifest.espeakDataDirectory,
           ),
           extractedByteSize: manifest.extractedByteSize,
           extractedFileCount: manifest.extractedFileCount,
           bundleTreeSha256: manifest.bundleTreeSha256,
         ),
         closedFailureCode: 'piper_model_store_closed',
         closedFailureMessage: 'The Piper model store is already closed.',
       );

  final VerifiedArchiveModelStore<VerifiedPiperModelBundle> _delegate;

  @override
  ModelStoreState<VerifiedPiperModelBundle> get current => _delegate.current;

  @override
  Stream<ModelStoreState<VerifiedPiperModelBundle>> get states => _delegate.states;

  @override
  Future<AppResult<VerifiedPiperModelBundle>> prepare() => _delegate.prepare();

  @override
  Future<void> suspend() => _delegate.suspend();

  @override
  Future<void> close() => _delegate.close();
}

String _childPath(String parent, String child) {
  return '$parent${Platform.pathSeparator}$child';
}
