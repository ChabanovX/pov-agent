import 'dart:io';

Future<void> main(List<String> arguments) async {
  final launcher = File.fromUri(Platform.script).absolute;
  final projectRoot = launcher.parent.parent.absolute;
  final harnessRoot = Directory(
    '${projectRoot.path}${Platform.pathSeparator}tool${Platform.pathSeparator}flutter_agentic_harness',
  );
  final toolDirectory = Directory(
    '${harnessRoot.path}${Platform.pathSeparator}tool'
    '${Platform.pathSeparator}agent_harness',
  );
  final pubspec = File(
    '${toolDirectory.path}${Platform.pathSeparator}pubspec.yaml',
  );
  final packageConfig = File(
    '${toolDirectory.path}${Platform.pathSeparator}.dart_tool'
    '${Platform.pathSeparator}package_config.json',
  );

  if (!pubspec.existsSync()) {
    stderr.writeln(
      'Harness package not found at ${toolDirectory.path}. '
      'Run git submodule update --init --recursive.',
    );
    exitCode = 66;
    return;
  }

  final needsPubGet =
      !packageConfig.existsSync() || pubspec.lastModifiedSync().isAfter(packageConfig.lastModifiedSync());
  if (needsPubGet) {
    stdout.writeln('Preparing local agent harness dependencies...');
    final pubGet = await Process.start(
      Platform.resolvedExecutable,
      const ['pub', 'get'],
      workingDirectory: toolDirectory.path,
      mode: ProcessStartMode.inheritStdio,
      runInShell: Platform.isWindows,
    );
    final pubGetCode = await pubGet.exitCode;
    if (pubGetCode != 0) {
      exitCode = pubGetCode;
      return;
    }
  }

  final hasExplicitRoot = arguments.any(
    (argument) => argument == '--root' || argument.startsWith('--root='),
  );
  final forwarded = <String>[
    'run',
    'bin/agent_harness.dart',
    if (!hasExplicitRoot) ...['--root', projectRoot.path],
    ...arguments,
  ];
  final process = await Process.start(
    Platform.resolvedExecutable,
    forwarded,
    workingDirectory: toolDirectory.path,
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows,
  );
  exitCode = await process.exitCode;
}
