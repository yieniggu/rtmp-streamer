import 'dart:async';

import 'package:flutter/material.dart';
import "package:flutter/services.dart";
import 'package:rtmp_broadcaster/camera.dart';
import 'package:wakelock/wakelock.dart';
import 'package:rtmp_broadcaster_test/models/config.dart';
import 'package:intl/intl.dart';

List<CameraDescription> cameras = [];

void logError(String code, String message) =>
    print('Error: $code\nError Message: $message');

/// Returns a suitable camera icon for [direction].
IconData getCameraLensIcon(CameraLensDirection? direction) {
  switch (direction) {
    case CameraLensDirection.back:
      return Icons.camera_rear;
    case CameraLensDirection.front:
      return Icons.camera_front;
    case CameraLensDirection.external:
    default:
      return Icons.camera;
  }
}

Future<void> main() async {
  // Ensure that plugin services are initialized so that `availableCameras()`
  // can be called before `runApp()`
  try {
    WidgetsFlutterBinding.ensureInitialized();
    cameras = await availableCameras();

    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  } on CameraException catch (e) {
    logError(e.code, e.description ?? "No description found");
  }

  ConfigProvider configProvider = ConfigProvider();
  await configProvider.open();

  Config storeConfig = await configProvider.getConfig(1);
  print("first store config: ${storeConfig.toString()}");

  if (storeConfig.id != 1) {
    await configProvider
        .insert(Config(1, "test", 12, 12, false, "111.222.33.44"));
    storeConfig = await configProvider.getConfig(1);
    print("second store config: ${storeConfig.toString()}");
  }

  runApp(
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: TakePictureScreen(
          // Pass the appropriate camera to the TakePictureScreen widget.
          config: storeConfig,
          configProvider: configProvider),
    ),
  );
}

// A screen that allows users to take a picture using a given camera.
class TakePictureScreen extends StatefulWidget {
  TakePictureScreen(
      {super.key, required this.config, required this.configProvider});

  ConfigProvider configProvider;
  Config config;

  @override
  TakePictureScreenState createState() => TakePictureScreenState();
}

class TakePictureScreenState extends State<TakePictureScreen>
    with WidgetsBindingObserver {
  late TimeOfDay initDate;
  late TimeOfDay endDate;

  final TextEditingController _storeNameController =
      TextEditingController(text: "Tienda Nueva");
  final TextEditingController _rtmpIpEndpointController =
      TextEditingController(text: "111.222.33.44");
  final currentTime = DateTime.now();
  late Timer timer;
  late bool isCapturing;

  // rtmp broadcaster definitions
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  CameraController? controller;
  String? url;
  bool enableAudio = true;
  bool useOpenGL = true;
  bool get isStreaming => controller?.value.isStreamingVideoRtmp ?? false;
  bool isVisible = true;

  bool get isControllerInitialized => controller?.value.isInitialized ?? false;

  bool get isStreamingVideoRtmp =>
      controller?.value.isStreamingVideoRtmp ?? false;

  bool get isRecordingVideo => controller?.value.isRecordingVideo ?? false;

  bool get isRecordingPaused => controller?.value.isRecordingPaused ?? false;

  bool get isStreamingPaused => controller?.value.isStreamingPaused ?? false;

  bool get isTakingPicture => controller?.value.isTakingPicture ?? false;

  @override
  void initState() {
    super.initState();

    _storeNameController.text = widget.config.name;
    _rtmpIpEndpointController.text = widget.config.RTMPIPEndpoint;
    isCapturing = widget.config.capturing;
    initDate = TimeOfDay(hour: widget.config.openHour, minute: 0);
    endDate = TimeOfDay(hour: widget.config.closeHour, minute: 0);

    WidgetsBinding.instance.addObserver(this);

    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      print("[TIMER] new tick - iscapturing?: ${isCapturing}");

      // Check if it is in hours of streaming
      if ((endDate.hour == 0 && initDate.hour >= 0) ||
          (TimeOfDay.now().hour >= initDate.hour &&
              TimeOfDay.now().hour < endDate.hour)) {
        print("[TIMER] In hour of streaming");
        if (isCapturing) {
          // check if it's not streaming
          if (isStreamingVideoRtmp) {
            print("[TIMER] Already streaming...");
          } else {
            if (controller != null && isControllerInitialized) {
              print("[TIMER] Starting streaming...");
              startVideoStreaming();
            }
          }
        }
      } else {
        print("[TIMER] Out of hour of streaming");
        if (isCapturing) {
          if (isStreamingVideoRtmp) {
            print("[TIMER] Stopping stream...");
            stopVideoStreaming();
          }
        }
      }
    });

    // print("initDate: ${initDate.hour} - type: ${initDate.hour.runtimeType}");
    // print("initDate: ${initDate}");
  }

  @override
  void dispose() {
    // Dispose of the controller when the widget is disposed.
    WidgetsBinding.instance.removeObserver(this);
    Wakelock.disable();
    timer.cancel();
    super.dispose();
  }

  void updateConfig(Config config) async {
    await widget.configProvider.update(config);
  }

  /// Display the preview from the camera (or a message if the preview is not available).
  Widget _cameraPreviewWidget() {
    if (controller == null || !isControllerInitialized) {
      return const Text(
        'Tap a camera',
        style: TextStyle(
          color: Colors.white,
          fontSize: 24.0,
          fontWeight: FontWeight.w900,
        ),
      );
    }

    return AspectRatio(
      aspectRatio: controller!.value.aspectRatio,
      child: CameraPreview(controller!),
    );
  }

  /// Toggle recording audio
  Widget _toggleAudioWidget() {
    return Padding(
      padding: const EdgeInsets.only(left: 25),
      child: Row(
        children: <Widget>[
          const Text('Enable Audio:'),
          Switch(
            value: enableAudio,
            onChanged: (bool value) {
              enableAudio = value;
              if (controller != null) {
                onNewCameraSelected(controller!.description);
              }
            },
          ),
        ],
      ),
    );
  }

  /// Display the control bar with buttons to take pictures and record videos.
  Widget _captureControlRowWidget() {
    if (controller == null) return Container();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      mainAxisSize: MainAxisSize.max,
      children: <Widget>[
        IconButton(
          icon: const Icon(Icons.watch),
          color: Colors.blue,
          onPressed: controller != null &&
                  isControllerInitialized &&
                  !isStreamingVideoRtmp
              ? onVideoStreamingButtonPressed
              : null,
        ),
        IconButton(
          icon: controller != null && isStreamingPaused
              ? Icon(Icons.play_arrow)
              : Icon(Icons.pause),
          color: Colors.blue,
          onPressed: controller != null &&
                  isControllerInitialized &&
                  isStreamingVideoRtmp
              ? (controller != null && isStreamingPaused
                  ? onResumeStreamingButtonPressed
                  : onPauseStreamingButtonPressed)
              : null,
        ),
        IconButton(
          icon: const Icon(Icons.stop),
          color: Colors.red,
          onPressed: controller != null &&
                  isControllerInitialized &&
                  (isRecordingVideo || isStreamingVideoRtmp)
              ? onStopButtonPressed
              : null,
        )
      ],
    );
  }

  /// Display a row of toggle to select the camera (or a message if no camera is available).
  Widget _cameraTogglesRowWidget() {
    final List<Widget> toggles = <Widget>[];

    if (cameras.isEmpty) {
      return const Text('No camera found');
    } else {
      for (CameraDescription cameraDescription in cameras) {
        toggles.add(
          SizedBox(
            width: 90.0,
            child: RadioListTile<CameraDescription>(
              title: Icon(getCameraLensIcon(cameraDescription.lensDirection)),
              groupValue: controller?.description,
              value: cameraDescription,
              onChanged: (CameraDescription? cld) =>
                  isRecordingVideo ? null : onNewCameraSelected(cld),
            ),
          ),
        );
      }
    }

    return Row(children: toggles);
  }

  String timestamp() => DateTime.now().millisecondsSinceEpoch.toString();

  void showInSnackBar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void onNewCameraSelected(CameraDescription? cameraDescription) async {
    if (cameraDescription == null) return;

    if (controller != null) {
      await stopVideoStreaming();
      await controller?.dispose();
    }
    controller = CameraController(
      cameraDescription,
      ResolutionPreset.medium,
      enableAudio: enableAudio,
      androidUseOpenGL: useOpenGL,
    );

    // If the controller is updated then update the UI.
    controller!.addListener(() async {
      if (mounted) setState(() {});

      if (controller != null) {
        if (controller!.value.hasError) {
          showInSnackBar('Camera error ${controller!.value.errorDescription}');
          await stopVideoStreaming();
        } else {
          try {
            final Map<dynamic, dynamic> event =
                controller!.value.event as Map<dynamic, dynamic>;
            print('Event $event');
            final String eventType = event['eventType'] as String;
            if (isVisible && isStreaming && eventType == 'rtmp_retry') {
              showInSnackBar('BadName received, endpoint in use.');
              await stopVideoStreaming();
            }
          } catch (e) {
            print(e);
          }
        }
      }
    });

    try {
      await controller!.initialize();
    } on CameraException catch (e) {
      _showCameraException(e);
    }

    if (mounted) {
      setState(() {});
    }
  }

  void onVideoStreamingButtonPressed() {
    // set capturing flag to true
    if (!isCapturing) {
      setState(() {
        isCapturing = true;

        Config temp = Config(
            widget.config.id,
            _storeNameController.text,
            initDate.hour,
            endDate.hour,
            isCapturing,
            _rtmpIpEndpointController.text);
        updateConfig(temp);
      });
    }

    startVideoStreaming().then((String? url) {
      if (mounted) setState(() {});
      showInSnackBar('Streaming video to $url');
      Wakelock.enable();
    });
  }

  void onStopButtonPressed() {
    // set capturing flag to false
    if (isCapturing) {
      setState(() {
        isCapturing = false;

        Config temp = Config(
            widget.config.id,
            _storeNameController.text,
            initDate.hour,
            endDate.hour,
            isCapturing,
            _rtmpIpEndpointController.text);
        updateConfig(temp);
      });
    }

    if (this.isStreamingVideoRtmp) {
      stopVideoStreaming().then((_) {
        if (mounted) setState(() {});
        showInSnackBar('Video streamed to: $url');
      });
    }
    Wakelock.disable();
  }

  void onPauseStreamingButtonPressed() {
    pauseVideoStreaming().then((_) {
      if (mounted) setState(() {});
      showInSnackBar('Video streaming paused');
    });
  }

  void onResumeStreamingButtonPressed() {
    resumeVideoStreaming().then((_) {
      if (mounted) setState(() {});
      showInSnackBar('Video streaming resumed');
    });
  }

  
  Future<String?> startVideoStreaming() async {
    await stopVideoStreaming();
    if (controller == null) {
      return null;
    }
    if (!isControllerInitialized) {
      showInSnackBar('Error: select a camera first.');
      return null;
    }

    if (controller?.value.isStreamingVideoRtmp ?? false) {
      return null;
    }

    List<String> splittedStoreName = _storeNameController.text.split(" ");
    String urlStoreParam = splittedStoreName.join("_");

    DateTime now = DateTime.now();

    String formatted = DateFormat('yyyy_MM_dd').format(now);

    // Open up a dialog for the url
    String myUrl =
        'rtmp://${_rtmpIpEndpointController.text}/live/${urlStoreParam}-${formatted}-raw';

    print("url: ${myUrl}");

    try {
      url = myUrl;
      await controller!.startVideoStreaming(url!);
    } on CameraException catch (e) {
      _showCameraException(e);
      return null;
    }
    return url;
  }

  Future<void> stopVideoStreaming() async {
    if (controller == null || !isControllerInitialized) {
      return;
    }
    if (!isStreamingVideoRtmp) {
      return;
    }

    try {
      await controller!.stopVideoStreaming();
    } on CameraException catch (e) {
      _showCameraException(e);
      return null;
    }
  }

  Future<void> pauseVideoStreaming() async {
    if (!isStreamingVideoRtmp) {
      return null;
    }

    try {
      await controller!.pauseVideoStreaming();
    } on CameraException catch (e) {
      _showCameraException(e);
      rethrow;
    }
  }

  Future<void> resumeVideoStreaming() async {
    if (!isStreamingVideoRtmp) {
      return null;
    }

    try {
      await controller!.resumeVideoStreaming();
    } on CameraException catch (e) {
      _showCameraException(e);
      rethrow;
    }
  }

  void _showCameraException(CameraException e) {
    logError(e.code, e.description ?? "No description found");
    showInSnackBar(
        'Error: ${e.code}\n${e.description ?? "No description found"}');
  }

  Widget layout(BuildContext context) {
    Color color = Colors.grey;

    if (controller != null) {
      if (controller!.value.isRecordingVideo ?? false) {
        color = Colors.redAccent;
      } else if (controller!.value.isStreamingVideoRtmp ?? false) {
        color = Colors.blueAccent;
      }
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Text(
          _storeNameController.text,
          style: const TextStyle(color: Colors.white),
        ),
        SizedBox(
          width: 250,
          child: TextField(
            onSubmitted: (value) => setState(() {
              _storeNameController.text = value;
              Config temp = Config(widget.config.id, value, initDate.hour,
                  endDate.hour, isCapturing, _rtmpIpEndpointController.text);

              updateConfig(temp);
            }),
            controller: _storeNameController,
            decoration: const InputDecoration(
                border: OutlineInputBorder(), labelText: "Tienda"),
          ),
        ),
        SizedBox(
          width: 250,
          child: TextField(
            onSubmitted: (value) => setState(() {
              _rtmpIpEndpointController.text = value;
              Config temp = Config(widget.config.id, _storeNameController.text, initDate.hour,
                  endDate.hour, isCapturing, value);

              updateConfig(temp);
            }),
            controller: _rtmpIpEndpointController,
            decoration: const InputDecoration(
                border: OutlineInputBorder(), labelText: "RTMP Ip Endpoint"),
          ),
        ),
        Expanded(
          child: Container(
            child: Padding(
              padding: const EdgeInsets.all(1.0),
              child: Center(
                child: _cameraPreviewWidget(),
              ),
            ),
            decoration: BoxDecoration(
              color: Colors.black,
              border: Border.all(
                color: color,
                width: 3.0,
              ),
            ),
          ),
        ),
        _captureControlRowWidget(),
        _toggleAudioWidget(),
        Padding(
          padding: const EdgeInsets.all(5.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              _cameraTogglesRowWidget(),
            ],
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Column(
              children: [
                ElevatedButton(
                    onPressed: () async {
                      TimeOfDay? initTime = await showTimePicker(
                          context: context, initialTime: initDate);
                      if (initTime != null) {
                        setState(() {
                          initDate = initTime;
                          Config temp = Config(
                              widget.config.id,
                              _storeNameController.text,
                              initDate.hour,
                              endDate.hour,
                              isCapturing,
                              _rtmpIpEndpointController.text);

                          updateConfig(temp);
                        });
                      }
                    },
                    child: const Text("Hora Inicio")),
                Text(
                  "${initDate.hour < 10 ? "0${initDate.hour}" : initDate.hour}:${initDate.minute < 10 ? "0${initDate.minute}" : initDate.minute}",
                  style: const TextStyle(color: Colors.white),
                )
              ],
            ),
            Column(
              children: [
                ElevatedButton(
                    onPressed: () async {
                      TimeOfDay? endTime = await showTimePicker(
                          context: context, initialTime: endDate);
                      if (endTime != null) {
                        setState(() {
                          endDate = endTime;

                          Config temp = Config(
                              widget.config.id,
                              _storeNameController.text,
                              initDate.hour,
                              endDate.hour,
                              isCapturing,
                              _rtmpIpEndpointController.text);

                          updateConfig(temp);
                        });
                      }
                    },
                    child: const Text("Hora Final")),
                Text(
                  "${endDate.hour < 10 ? "0${endDate.hour}" : endDate.hour}:${endDate.minute < 10 ? "0${endDate.minute}" : endDate.minute}",
                  style: const TextStyle(color: Colors.white),
                )
              ],
            )
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('Live RTMP')),
        // You must wait until the controller is initialized before displaying the
        // camera preview. Use a FutureBuilder to display a loading spinner until the
        // controller has finished initializing.
        body: layout(context));
  }
}
