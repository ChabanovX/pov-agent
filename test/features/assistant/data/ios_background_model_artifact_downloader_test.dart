import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pov_agent/features/assistant/data/datasources/ios_background_model_artifact_downloader.dart';
import 'package:pov_agent/features/assistant/data/datasources/model_artifact_downloader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/background_model_download');
  late StreamController<Object?> progressEvents;
  late MethodChannelIosBackgroundModelTransferBridge bridge;

  setUp(() {
    progressEvents = StreamController<Object?>.broadcast(sync: true);
    bridge = MethodChannelIosBackgroundModelTransferBridge.withChannels(
      channel,
      rawProgressEvents: progressEvents.stream,
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    await progressEvents.close();
  });

  test(
    'passes stable identity and reconciles native progress before completion',
    () async {
      MethodCall? downloadCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        downloadCall = call;
        final arguments = call.arguments! as Map<Object?, Object?>;
        progressEvents
          ..add({
            'transferId': arguments['transferId'],
            'receivedBytes': 32,
            'expectedBytes': 128,
          })
          ..add({
            'transferId': arguments['transferId'],
            'receivedBytes': 128,
            'expectedBytes': 128,
          });
        return {
          'transferId': arguments['transferId'],
          'receivedBytes': 128,
        };
      });
      final downloader = IosBackgroundModelArtifactDownloader(bridge: bridge);
      final progress = <int>[];

      await downloader.download(
        source: Uri.parse('https://models.example.test/tiny.gguf'),
        destinationPath: '/app/support/models/tiny.gguf.part',
        expectedBytes: 128,
        onProgress: progress.add,
        cancellation: ModelDownloadCancellation(),
      );

      expect(downloadCall?.method, 'download');
      final arguments = downloadCall!.arguments! as Map<Object?, Object?>;
      expect(arguments['sourceUrl'], 'https://models.example.test/tiny.gguf');
      expect(
        arguments['destinationPath'],
        '/app/support/models/tiny.gguf.part',
      );
      expect(arguments['expectedBytes'], 128);
      expect(arguments['transferId'], matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(progress, [32, 128]);
    },
  );

  test('explicit cancellation waits for the native cancel boundary', () async {
    final downloadStarted = Completer<void>();
    final releaseDownload = Completer<void>();
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'download':
          downloadStarted.complete();
          await releaseDownload.future;
          throw PlatformException(code: 'MODEL_DOWNLOAD_CANCELLED');
        case 'cancel':
          releaseDownload.complete();
          return null;
        default:
          throw MissingPluginException();
      }
    });
    final cancellation = ModelDownloadCancellation();
    final download =
        IosBackgroundModelArtifactDownloader(
          bridge: bridge,
        ).download(
          source: Uri.parse('https://models.example.test/tiny.gguf'),
          destinationPath: '/app/support/models/tiny.gguf.part',
          expectedBytes: 128,
          onProgress: (_) {},
          cancellation: cancellation,
        );
    await downloadStarted.future;

    cancellation.cancel();

    await expectLater(
      download,
      throwsA(isA<ModelDownloadCancelledException>()),
    );
    expect(calls.map((call) => call.method), ['download', 'cancel']);
    expect(
      (calls.last.arguments! as Map<Object?, Object?>)['transferId'],
      (calls.first.arguments! as Map<Object?, Object?>)['transferId'],
    );
  });

  test('maps native HTTP status to the existing store transport contract', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(
        code: 'MODEL_DOWNLOAD_HTTP_STATUS',
        details: {'statusCode': 404},
      );
    });

    await expectLater(
      IosBackgroundModelArtifactDownloader(bridge: bridge).download(
        source: Uri.parse('https://models.example.test/missing.gguf'),
        destinationPath: '/app/support/models/missing.gguf.part',
        expectedBytes: 128,
        onProgress: (_) {},
        cancellation: ModelDownloadCancellation(),
      ),
      throwsA(
        isA<ModelHttpStatusException>().having(
          (error) => error.statusCode,
          'statusCode',
          404,
        ),
      ),
    );
  });

  test('rejects a malformed native completion payload', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => {'receivedBytes': 128},
    );

    await expectLater(
      IosBackgroundModelArtifactDownloader(bridge: bridge).download(
        source: Uri.parse('https://models.example.test/tiny.gguf'),
        destinationPath: '/app/support/models/tiny.gguf.part',
        expectedBytes: 128,
        onProgress: (_) {},
        cancellation: ModelDownloadCancellation(),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
