import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:some_camera_with_llm/app/app.dart';
import 'package:some_camera_with_llm/app/di/app_di.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final runtime = configureDependencies();
  runApp(const SomeCameraWithLlmApp());
  unawaited(runtime.start());
}
