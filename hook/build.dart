import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

Future<void> main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final code = input.config.code;
    if (code.targetOS != OS.iOS && code.targetOS != OS.macOS) {
      throw UnsupportedError(
        'The POV llama.cpp runtime supports Apple targets only.',
      );
    }

    final packageRoot = input.packageRoot.toFilePath();
    final nativeDirectory = '$packageRoot/native';
    final llamaDirectory = '$nativeDirectory/third_party/llama.cpp';
    final buildDirectory = Directory(
      input.outputDirectory.resolve('pov_llama_build/').toFilePath(),
    )..createSync(recursive: true);

    final configureArguments = <String>[
      '-S',
      nativeDirectory,
      '-B',
      buildDirectory.path,
      '-G',
      'Ninja',
      '-DLLAMA_CPP_DIR=$llamaDirectory',
      '-DCMAKE_BUILD_TYPE=Release',
      '-DCMAKE_POSITION_INDEPENDENT_CODE=ON',
      '-DCMAKE_CXX_STANDARD=17',
      '-DBUILD_SHARED_LIBS=OFF',
      '-DLLAMA_BUILD_COMMON=OFF',
      '-DLLAMA_BUILD_APP=OFF',
      '-DLLAMA_BUILD_TESTS=OFF',
      '-DLLAMA_BUILD_TOOLS=OFF',
      '-DLLAMA_BUILD_EXAMPLES=OFF',
      '-DLLAMA_BUILD_MTMD=OFF',
      '-DLLAMA_BUILD_SERVER=OFF',
      '-DLLAMA_BUILD_UI=OFF',
      '-DLLAMA_USE_PREBUILT_UI=OFF',
      '-DLLAMA_OPENSSL=OFF',
      '-DGGML_BACKEND_DL=OFF',
      '-DGGML_NATIVE=OFF',
      '-DGGML_OPENMP=OFF',
      '-DGGML_ACCELERATE=ON',
      '-DGGML_BLAS=OFF',
      '-DGGML_METAL=ON',
      // Xcode compiles the iOS shader into Runner.app/default.metallib. The
      // embedded mode stores source and compiles it on-device, which can fail
      // intermittently with an internal Metal compiler error.
      '-DGGML_METAL_EMBED_LIBRARY=${code.targetOS == OS.iOS ? 'OFF' : 'ON'}',
      '-DGGML_METAL_NDEBUG=ON',
      ..._appleTargetArguments(code),
    ];

    await _runChecked(
      'cmake',
      configureArguments,
      workingDirectory: packageRoot,
      operation: 'configure llama.cpp',
    );
    await _runChecked(
      'cmake',
      [
        '--build',
        buildDirectory.path,
        '--target',
        'pov_llama',
        '--parallel',
      ],
      workingDirectory: packageRoot,
      operation: 'build llama.cpp',
    );

    final dylib = Uri.file('${buildDirectory.path}/out/libpov_llama.dylib');
    if (!File.fromUri(dylib).existsSync()) {
      throw StateError('The llama.cpp build did not produce ${dylib.path}.');
    }

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'features/assistant/data/ffi/llama_bridge_bindings.dart',
        linkMode: DynamicLoadingBundled(),
        file: dylib,
      ),
    );
    output.dependencies.addAll([
      input.packageRoot.resolve('native/CMakeLists.txt'),
      input.packageRoot.resolve('native/llama_bridge/exports.txt'),
      input.packageRoot.resolve('native/llama_bridge/llama_bridge.cpp'),
      input.packageRoot.resolve('native/llama_bridge/llama_bridge.h'),
      ..._llamaSourceDependencies(llamaDirectory),
    ]);
  });
}

Iterable<Uri> _llamaSourceDependencies(String llamaDirectory) sync* {
  const sourceExtensions = {
    '.c',
    '.cc',
    '.cmake',
    '.cpp',
    '.cxx',
    '.h',
    '.hpp',
    '.in',
    '.inc',
    '.m',
    '.metal',
    '.mm',
    '.s',
  };
  final dependencies = <Uri>[Uri.file('$llamaDirectory/CMakeLists.txt')];
  for (final relativeDirectory in ['cmake', 'ggml', 'include', 'src']) {
    for (final entity in Directory(
      '$llamaDirectory/$relativeDirectory',
    ).listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final filename = entity.uri.pathSegments.last;
      final dot = filename.lastIndexOf('.');
      final extension = dot < 0 ? '' : filename.substring(dot).toLowerCase();
      if (filename == 'CMakeLists.txt' || sourceExtensions.contains(extension)) {
        dependencies.add(entity.uri);
      }
    }
  }
  dependencies.sort((left, right) => left.path.compareTo(right.path));
  yield* dependencies;
}

List<String> _appleTargetArguments(CodeConfig code) {
  final architecture = switch (code.targetArchitecture) {
    Architecture.arm64 => 'arm64',
    Architecture.x64 => 'x86_64',
    final unsupported => throw UnsupportedError(
      'Unsupported Apple architecture: ${unsupported.name}.',
    ),
  };

  if (code.targetOS == OS.iOS) {
    final sdk = switch (code.iOS.targetSdk) {
      IOSSdk.iPhoneOS => 'iphoneos',
      IOSSdk.iPhoneSimulator => 'iphonesimulator',
      final unsupported => throw UnsupportedError(
        'Unsupported iOS SDK: ${unsupported.type}.',
      ),
    };
    return [
      '-DCMAKE_SYSTEM_NAME=iOS',
      '-DCMAKE_OSX_SYSROOT=$sdk',
      '-DCMAKE_OSX_ARCHITECTURES=$architecture',
      '-DCMAKE_OSX_DEPLOYMENT_TARGET=${code.iOS.targetVersion}',
    ];
  }

  return [
    '-DCMAKE_OSX_SYSROOT=macosx',
    '-DCMAKE_OSX_ARCHITECTURES=$architecture',
    '-DCMAKE_OSX_DEPLOYMENT_TARGET=${code.macOS.targetVersion}',
  ];
}

Future<void> _runChecked(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required String operation,
}) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  if (result.exitCode == 0) return;

  stderr
    ..writeln(result.stdout)
    ..writeln(result.stderr);
  throw StateError('Could not $operation (exit ${result.exitCode}).');
}
