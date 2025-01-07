import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  final firstCamera = cameras.first;
  runApp(MyApp(camera: firstCamera));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.camera});

  final CameraDescription camera;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Camera Example',
      theme: ThemeData(),
      home: TakePictureScreen(camera: camera),
    );
  }
}

class TakePictureScreen extends StatefulWidget {
  const TakePictureScreen({super.key, required this.camera});

  final CameraDescription camera;

  @override
  TakePictureScreenState createState() => TakePictureScreenState();
}

class TakePictureScreenState extends State<TakePictureScreen>
    with SingleTickerProviderStateMixin {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  late StreamSubscription<AccelerometerEvent> _accelerometerSubscription;
  double _rotationAngle = 0.0;
  final List<Offset> _tapPositions = [];
  final List<double> _arrowAngles = [];
  late AnimationController _animationController;
  final Random _random = Random();
  bool _showVectors = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();

    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium,
    );

    _initializeControllerFuture = _controller.initialize().catchError((e) {
      // Handle camera initialization error
      print('Error initializing camera: $e');
    });

    _accelerometerSubscription =
        accelerometerEvents.listen((AccelerometerEvent event) {
      setState(() {
        _rotationAngle = -0.2 * event.y;
      });
    });

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    _accelerometerSubscription.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTapDown: (details) async {
          setState(() {
            _isLoading = true;
          });
          await Future.delayed(const Duration(seconds: 1));

          setState(() {
            _tapPositions.add(details.localPosition);
            if (_tapPositions.length == 1) {
              _arrowAngles.add(0);
            } else {
              double randomAngle = _rotationAngle +
                  (_random.nextDouble() * 60 - 30) * (pi / 180);
              _arrowAngles.add(randomAngle);
            }
            _isLoading = false;
          });
        },
        onLongPressMoveUpdate: (details) {
          setState(() {
            for (int i = 0; i < _tapPositions.length; i++) {
              if ((_tapPositions[i] - details.localPosition).distance < 50) {
                _tapPositions.removeAt(i);
                _arrowAngles.removeAt(i);
                break;
              }
            }
          });
        },
        child: Stack(
          children: [
            FutureBuilder<void>(
              future: _initializeControllerFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done) {
                  final scale = MediaQuery.of(context).size.width /
                      _controller.value.previewSize!.height;
                  return Center(
                    child: Transform.scale(
                      scale: scale,
                      child: AspectRatio(
                        aspectRatio: _controller.value.aspectRatio,
                        child: CameraPreview(_controller),
                      ),
                    ),
                  );
                } else {
                  return const Center(child: CircularProgressIndicator());
                }
              },
            ),
            if (_tapPositions.isEmpty)
              Container(
                color: Colors.black54,
                child: Center(
                  child: Text(
                    'タップをしてください',
                    style: TextStyle(color: Colors.white, fontSize: 24),
                  ),
                ),
              ),
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(),
              ),
            AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                return Stack(
                  children: [
                    for (int i = 0; i < _tapPositions.length; i++)
                      Positioned(
                        left: _tapPositions[i].dx - 50,
                        top: _tapPositions[i].dy -
                            50 +
                            10 * sin(_animationController.value * 2 * pi + i),
                        child: Transform.rotate(
                          angle: _arrowAngles[i],
                          child: Transform.scale(
                            scaleY: -2.0,
                            child: Icon(
                              Icons.arrow_upward,
                              size: 100,
                              color: Colors.red,
                            ),
                          ),
                        ),
                      ),
                    if (_showVectors && _tapPositions.isNotEmpty)
                      CustomPaint(
                        size: Size.infinite,
                        painter:
                            VectorFieldPainter(_tapPositions, _arrowAngles),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.camera_alt),
            label: 'カメラ',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'マップ',
          ),
        ],
        onTap: (index) async {
          if (index == 0) {
            try {
              final image = await _controller.takePicture();
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) =>
                      DisplayPictureScreen(imagePath: image.path),
                  fullscreenDialog: true,
                ),
              );
            } catch (e) {
              // Handle picture taking error
              print('Error taking picture: $e');
            }
          } else if (index == 1) {
            setState(() {
              _showVectors = !_showVectors;
            });
          }
        },
      ),
    );
  }
}

class DisplayPictureScreen extends StatelessWidget {
  const DisplayPictureScreen({super.key, required this.imagePath});

  final String imagePath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('撮れた写真')),
      body: Center(child: Image.file(File(imagePath))),
    );
  }
}

class VectorFieldPainter extends CustomPainter {
  final List<Offset> positions;
  final List<double> angles;

  VectorFieldPainter(this.positions, this.angles);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2;

    for (double x = 0; x < size.width; x += 50) {
      for (double y = 0; y < size.height; y += 50) {
        final position = Offset(x, y);
        if (x > size.width || y > size.height) continue;
        final vector = _calculateVector(position);
        _drawArrow(canvas, position, vector, paint);
      }
    }
  }

  Offset _calculateVector(Offset position) {
    if (positions.isEmpty) return Offset.zero;

    Offset combinedVector = Offset.zero;
    for (int i = 0; i < positions.length; i++) {
      final distance = (position - positions[i]).distance;
      if (distance < 1) continue;

      final angle = -angles[i];
      final vectorLength = 50.0 / distance;
      combinedVector += Offset(
        vectorLength * sin(angle),
        vectorLength * cos(angle),
      );
    }

    final scaleFactor = 30.0;
    return combinedVector * scaleFactor;
  }

  void _drawArrow(Canvas canvas, Offset position, Offset vector, Paint paint) {
    final arrowLength = vector.distance;
    final arrowAngle = atan2(vector.dy, vector.dx) + pi;

    canvas.drawLine(position, position + vector, paint);

    final arrowHeadSize = 10.0;
    final arrowHeadAngle = pi / 6;
    final arrowTip = position + vector;
    final arrowHead1 = arrowTip +
        Offset(
          arrowHeadSize * cos(arrowAngle - arrowHeadAngle),
          arrowHeadSize * sin(arrowAngle - arrowHeadAngle),
        );
    final arrowHead2 = arrowTip +
        Offset(
          arrowHeadSize * cos(arrowAngle + arrowHeadAngle),
          arrowHeadSize * sin(arrowAngle + arrowHeadAngle),
        );

    canvas.drawLine(arrowTip, arrowHead1, paint);
    canvas.drawLine(arrowTip, arrowHead2, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
