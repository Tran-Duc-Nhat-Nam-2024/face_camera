import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:face_camera/src/extension/nv21_converter.dart';

import '../models/detected_image.dart';

class FaceIdentifier {
  static Future<DetectedFace?> scanImage(
      {required CameraImage cameraImage,
      required CameraController? controller,
      required FaceDetectorMode performanceMode,
      double offSetX = 5, double offSetY = 5, double offSetZ = 5, double boundingLeft = -1000, double boundingRight = 2000, double boundingTop = -1000, double boundingBottom = 4000}) async {
    final orientations = {
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };

    DetectedFace? result;
    final face = await _detectFace(
        performanceMode: performanceMode,
        visionImage:
            _inputImageFromCameraImage(cameraImage, controller, orientations)
        , offSetX: offSetX, offSetY: offSetY, offSetZ: offSetZ, boundingLeft: boundingLeft, boundingRight:  boundingRight, boundingTop: boundingTop, boundingBottom: boundingBottom);
    if (face != null) {
      result = face;
    }

    return result;
  }

  static InputImage? _inputImageFromCameraImage(CameraImage image,
      CameraController? controller, Map<DeviceOrientation, int> orientations) {
    // get image rotation
    // it is used in android to convert the InputImage from Dart to Java
    // `rotation` is not used in iOS to convert the InputImage from Dart to Obj-C
    // in both platforms `rotation` and `camera.lensDirection` can be used to compensate `x` and `y` coordinates on a canvas
    final camera = controller!.description;
    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation =
          orientations[controller.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      if (camera.lensDirection == CameraLensDirection.front) {
        // front-facing
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        // back-facing
        rotationCompensation =
            (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    if (rotation == null) return null;

    // get image format
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    // validate format depending on platform
    // only supported formats:
    // * bgra8888 for iOS
    if (format == null ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) return null;
    if (image.planes.isEmpty) return null;

    final bytes = Platform.isAndroid
        ? image.getNv21Uint8List()
        : Uint8List.fromList(
            image.planes.fold(
                <int>[],
                (List<int> previousValue, element) =>
                    previousValue..addAll(element.bytes)),
          );

    // compose InputImage using bytes
    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation, // used only in Android
        format: format, // used only in iOS
        bytesPerRow: image.planes.first.bytesPerRow, // used only in iOS
      ),
    );
  }

  static Future<DetectedFace?> _detectFace(
      {required InputImage? visionImage,
      required FaceDetectorMode performanceMode,
        double offSetX = 5, double offSetY = 5, double offSetZ = 5, double boundingLeft = -1000, double boundingRight = 2000, double boundingTop = -1000, double boundingBottom = 4000}) async {
    if (visionImage == null) return null;
    final options = FaceDetectorOptions(
        enableLandmarks: true,
        enableTracking: true,
        performanceMode: performanceMode);
    final faceDetector = FaceDetector(options: options);
    try {
      final List<Face> faces = await faceDetector.processImage(visionImage);
      final faceDetect = _extractFace(faces, offSetX: offSetX, offSetY: offSetY, offSetZ: offSetZ, boundingLeft: boundingLeft, boundingRight:  boundingRight, boundingTop: boundingTop, boundingBottom: boundingBottom);
      return faceDetect;
    } catch (error) {
      debugPrint(error.toString());
      return null;
    }
  }

  static _extractFace(List<Face> faces, {
  double offSetX = 5, double offSetY = 5, double offSetZ = 5, double boundingLeft = -1000, double boundingRight = 2000, double boundingTop = -1000, double boundingBottom = 4000}) {
    //List<Rect> rect = [];
    bool wellPositioned = false;
    Face? detectedFace;

    for (Face face in faces) {
      detectedFace = face;

      if (face.headEulerAngleX! < offSetX && face.headEulerAngleX! > -offSetX && face.headEulerAngleY! < offSetY && face.headEulerAngleY! > -offSetY && face.headEulerAngleZ! < offSetZ && face.headEulerAngleZ! > -offSetZ) {
        wellPositioned = true;
      }

      if (face.boundingBox.left < boundingLeft && face.boundingBox.right > boundingRight && face.boundingBox.top < boundingTop && face.boundingBox.bottom > boundingBottom) {
        wellPositioned = false;
      }
    }

    return DetectedFace(wellPositioned: wellPositioned, face: detectedFace);
  }
}
