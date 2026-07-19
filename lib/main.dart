import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:pov_agent/app/app.dart';
import 'package:pov_agent/app/di/app_di.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final runtime = configureDependencies();
  runApp(const PovAgentApp());
  unawaited(runtime.start());
}
