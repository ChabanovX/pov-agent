import 'package:camera/camera.dart' as plugin;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:some_camera_with_llm/features/camera/data/datasources/flutter_camera_driver.dart';

/// Renders the native preview owned by the application camera session.
final class NativeCameraPreview extends StatelessWidget {
  const NativeCameraPreview({
    required this.driver,
    super.key,
  });

  final FlutterCameraDriver driver;

  @override
  Widget build(BuildContext context) {
    final controller = driver.previewController;
    return LayoutBuilder(
      builder: (context, constraints) {
        final orientation = controller.value.deviceOrientation;
        final landscape =
            orientation == DeviceOrientation.landscapeLeft || orientation == DeviceOrientation.landscapeRight;
        final previewAspectRatio = landscape ? controller.value.aspectRatio : 1 / controller.value.aspectRatio;
        final viewportAspectRatio = constraints.maxWidth / constraints.maxHeight;
        final previewWidth = previewAspectRatio > viewportAspectRatio
            ? constraints.maxHeight * previewAspectRatio
            : constraints.maxWidth;
        final previewHeight = previewAspectRatio > viewportAspectRatio
            ? constraints.maxHeight
            : constraints.maxWidth / previewAspectRatio;

        return ClipRect(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints.tightFor(
                width: previewWidth,
                height: previewHeight,
              ),
              child: plugin.CameraPreview(controller),
            ),
          ),
        );
      },
    );
  }
}
