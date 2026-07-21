import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

Future<void> main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final code = input.config.code;
    if (code.targetOS != OS.iOS &&
        code.targetOS != OS.macOS &&
        code.targetOS != OS.android) {
      throw UnsupportedError(
        'The POV llama.cpp runtime supports iOS, macOS, and Android only.',
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
      '-DGGML_BLAS=OFF',
      ..._backendArguments(code.targetOS),
      ..._targetArguments(code),
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

    final library = Uri.file(
      '${buildDirectory.path}/out/${_libraryFilename(code.targetOS)}',
    );
    if (!File.fromUri(library).existsSync()) {
      throw StateError(
        'The llama.cpp build did not produce ${library.path}.',
      );
    }

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'features/assistant/data/ffi/llama_bridge_bindings.dart',
        linkMode: DynamicLoadingBundled(),
        file: library,
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

List<String> _backendArguments(OS targetOS) {
  if (targetOS == OS.android) {
    return const [
      '-DGGML_ACCELERATE=OFF',
      '-DGGML_LLAMAFILE=OFF',
      '-DGGML_METAL=OFF',
      '-DGGML_METAL_EMBED_LIBRARY=OFF',
    ];
  }
  // Xcode compiles the iOS shader into Runner.app/default.metallib. Embedded
  // source compilation can fail intermittently on-device.
  return [
    '-DGGML_ACCELERATE=ON',
    '-DGGML_METAL=ON',
    '-DGGML_METAL_EMBED_LIBRARY=${targetOS == OS.iOS ? 'OFF' : 'ON'}',
    '-DGGML_METAL_NDEBUG=ON',
  ];
}

List<String> _targetArguments(CodeConfig code) {
  if (code.targetOS == OS.android) {
    return _androidTargetArguments(code);
  }
  return _appleTargetArguments(code);
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

List<String> _androidTargetArguments(CodeConfig code) {
  final ndkDirectory = _androidNdkDirectory();
  final toolchain = File(
    '${ndkDirectory.path}/build/cmake/android.toolchain.cmake',
  );
  return [
    '-DCMAKE_TOOLCHAIN_FILE=${toolchain.path}',
    '-DANDROID_ABI=${_androidAbi(code.targetArchitecture)}',
    '-DANDROID_PLATFORM=android-${code.android.targetNdkApi}',
    '-DANDROID_STL=c++_static',
  ];
}

Directory _androidNdkDirectory() {
  for (final variable in const [
    'ANDROID_NDK',
    'ANDROID_NDK_HOME',
    'ANDROID_NDK_LATEST_HOME',
    'ANDROID_NDK_ROOT',
  ]) {
    final path = Platform.environment[variable];
    if (path != null && _isPinnedAndroidNdk(Directory(path))) {
      return Directory(path);
    }
  }

  for (final variable in const ['ANDROID_HOME', 'ANDROID_SDK_ROOT']) {
    final sdkPath = Platform.environment[variable];
    if (sdkPath != null) {
      final pinnedNdk = Directory('$sdkPath/ndk/$_androidNdkVersion');
      if (_isPinnedAndroidNdk(pinnedNdk)) return pinnedNdk;
    }
  }

  throw StateError(
    'Android NDK $_androidNdkVersion is required. Install that version under '
    'ANDROID_HOME/ndk, ANDROID_SDK_ROOT/ndk, or point an ANDROID_NDK '
    'environment variable at that exact revision.',
  );
}

bool _isPinnedAndroidNdk(Directory directory) {
  final toolchainExists = File(
    '${directory.path}/build/cmake/android.toolchain.cmake',
  ).existsSync();
  final properties = File('${directory.path}/source.properties');
  if (!toolchainExists || !properties.existsSync()) return false;
  return properties.readAsLinesSync().any(
    (line) => line.trim() == 'Pkg.Revision = $_androidNdkVersion',
  );
}

String _androidAbi(Architecture architecture) {
  return switch (architecture) {
    Architecture.arm => 'armeabi-v7a',
    Architecture.arm64 => 'arm64-v8a',
    Architecture.ia32 => 'x86',
    Architecture.x64 => 'x86_64',
    final unsupported => throw UnsupportedError(
      'Unsupported Android architecture: ${unsupported.name}.',
    ),
  };
}

String _libraryFilename(OS targetOS) {
  return targetOS == OS.android ? 'libpov_llama.so' : 'libpov_llama.dylib';
}

const _androidNdkVersion = '28.2.13676358';

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
