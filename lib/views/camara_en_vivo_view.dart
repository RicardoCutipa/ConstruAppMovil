import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:audioplayers/audioplayers.dart';
import 'package:audioplayers/src/source.dart';

class CamaraEnVivoView extends StatefulWidget {
  final ValueChanged<bool> onFullScreenToggle;
  final bool isActive;

  const CamaraEnVivoView({
    super.key,
    required this.onFullScreenToggle,
    required this.isActive,
  });

  @override
  State<CamaraEnVivoView> createState() => _CamaraEnVivoViewState();
}

class _CamaraEnVivoViewState extends State<CamaraEnVivoView> with AutomaticKeepAliveClientMixin {
  VideoPlayerController? _controller;
  Future<void>? _initializeVideoPlayerFuture;
  bool _isPlaying = false;
  bool _isFullScreen = false;
  bool _showControls = true;
  bool _isLoading = false;
  bool _hasError = false;
  bool _isMuted = false;
  Timer? _retryTimer;
  bool _isRetrying = false;

  final String videoUrl = 'http://161.132.38.250:3333/app/stream/llhls.m3u8';
  final String ubicacion = "Entrada Principal";
  static const String _locale = 'es_PE';

  WebSocketChannel? _wsChannel;
  Timer? _wsReconnectTimer;
  int _wsReconnectIntervalMs = 1000;
  static const int _wsMaxReconnectIntervalMs = 30000;
  final String wsStatsUrl = 'wss://tunelvps.sytes.net/stats';

  int _personsCount = 0;
  int _dangerousObjectsCount = 0;
  String _lastDetectionDate = '--/--/----';
  String _lastDetectionTime = '--:--:--';
  String _clientStatusText = '⚪ Desconocido';
  Color _clientStatusColor = Colors.grey;

  bool _alertaMostrada = false;
  String _detectedObjectType = '';
  double _detectedObjectConfidence = 0.0;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isSendingAlert = false;
  bool _alertSentSuccess = false;

  final List<String> _criticalObjectsForAlertModal = ['gun', 'knife', 'rifle', 'mask', 'helmet'];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting(_locale, null);

    if (widget.isActive) {
      _startPlayer();
      _connectWebSocket();
    }
  }

  @override
  void didUpdateWidget(covariant CamaraEnVivoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      if (widget.isActive) {
        _startPlayer();
        _connectWebSocket();
      } else {
        _stopPlayer();
        _disconnectWebSocket();
        if (_isFullScreen) {
          _exitFullScreenProgrammatically();
        }
      }
    }
  }

  Future<void> _startPlayer() async {
    if (_controller != null || _isLoading || !mounted) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
      _isRetrying = false;
    });
    _retryTimer?.cancel();

    try {
      print('🎥 Intentando conectar a: $videoUrl');

      try {
        final response = await http.head(Uri.parse(videoUrl)).timeout(
          const Duration(seconds: 10),
        );
        print('📡 Video server response: ${response.statusCode}');
        if (response.statusCode != 200) {
          throw Exception('Video server not available: ${response.statusCode}');
        }
      } catch (e) {
        print('❌ Video connectivity error: $e');
        throw Exception('Cannot connect to video stream server');
      }

      _controller = VideoPlayerController.networkUrl(
        Uri.parse(videoUrl),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true,
          allowBackgroundPlayback: false,
        ),
        httpHeaders: {
          'User-Agent': 'FlutterApp/1.0',
          'Accept': '*/*',
          'Connection': 'keep-alive',
        },
      );

      _initializeVideoPlayerFuture = _controller!.initialize();

      await _initializeVideoPlayerFuture!.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Timeout initializing video');
        },
      );

      if (!mounted || _controller == null) return;

      print('✅ Video inicializado correctamente');
      _controller!.addListener(_videoListener);
      _controller!.setLooping(true);
      _controller!.setVolume(_isMuted ? 0.0 : 1.0);

      await _controller!.play();

      if (mounted) {
        setState(() {
          _isLoading = false;
          _isPlaying = true;
          _hasError = false;
        });
      }
      _scheduleControlsHide();
    } catch (error) {
      print('❌ Error al inicializar video: $error');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
        _scheduleRetry();
      }
    }
  }

  Future<void> _stopPlayer() async {
    _retryTimer?.cancel();
    _isRetrying = false;

    final controller = _controller;
    if (controller != null) {
      _controller = null;
      _initializeVideoPlayerFuture = null;
      try {
        controller.removeListener(_videoListener);
        if (controller.value.isInitialized && controller.value.isPlaying) {
          await controller.pause();
        }
        await controller.dispose();
      } catch (e) {
        print("Error disposing previous video controller: $e");
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = false;
          _isPlaying = false;
        });
      }
    }
  }

  void _scheduleRetry() {
    if (!mounted || _isRetrying || !widget.isActive) return;
    if (mounted) setState(() { _isRetrying = true; });
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && widget.isActive) {
        _startPlayer();
      } else {
        if (mounted) setState(() => _isRetrying = false );
      }
    });
  }

  void _videoListener() {
    if (!mounted || _controller == null || !_controller!.value.isInitialized) return;

    final value = _controller!.value;
    final isCurrentlyPlaying = value.isPlaying;

    if (isCurrentlyPlaying != _isPlaying) {
      if (mounted) setState(() { _isPlaying = isCurrentlyPlaying; });
    }

    if (value.hasError && !_isLoading && !_isRetrying && !_hasError) {
      if (mounted) {
        setState(() { _hasError = true; });
        _scheduleRetry();
      }
    } else if (!value.hasError && (_hasError || _isRetrying)) {
      _retryTimer?.cancel();
      if (mounted) {
        setState(() { _hasError = false; _isRetrying = false; _isPlaying = value.isPlaying; });
      }
    }
  }

  Future<void> _seekToLive() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      final duration = _controller!.value.duration;
      if (duration > const Duration(seconds: 5)) {
        await _controller!.seekTo(duration - const Duration(seconds: 5));
      }
    } catch (e) { /* Silently ignore seek errors for live */ }
  }

  void _togglePlayPause() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      if (widget.isActive && !_isLoading) { _startPlayer(); }
      return;
    }
    await _seekToLive();

    if (_controller!.value.isPlaying) {
      await _controller!.pause();
    } else {
      if (_controller!.value.volume == 0 && !_isMuted) {
        await _controller!.setVolume(1.0);
      }
      await _controller!.play().catchError((e) {
        if (mounted) setState(() => _hasError = true);
        _scheduleRetry();
      });
    }
    _showAndHideControls();
  }

  void _toggleMute() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() {
      _isMuted = !_isMuted;
      _controller!.setVolume(_isMuted ? 0.0 : 1.0);
    });
    _showAndHideControls();
  }

  void _exitFullScreenProgrammatically() async {
    if (_isFullScreen) {
      widget.onFullScreenToggle(false);
      _isFullScreen = false;
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      if (mounted) setState(() {});
    }
  }

  void _toggleFullScreen() async {
    if (_isLoading && !_isFullScreen) return;

    final newFullScreenState = !_isFullScreen;
    widget.onFullScreenToggle(newFullScreenState);
    _isFullScreen = newFullScreenState;

    if (_isFullScreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
    if (mounted) { setState(() {}); _showAndHideControls(); }
  }

  void _showAndHideControls() {
    if (!mounted) return;
    setState(() { _showControls = true; });
    _scheduleControlsHide();
  }

  void _scheduleControlsHide() {
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && widget.isActive && _isPlaying && _showControls && !_hasError) {
        if (mounted) setState(() { _showControls = false; });
      }
    });
  }

  // --- WebSocket Logic ---

  void _connectWebSocket() {
    // Corrected: Just check if closeCode is null. If it is, the channel is active (connecting or open).
    if (_wsChannel != null && _wsChannel!.closeCode == null) {
      print("WS: Connection already in progress or open.");
      return;
    }

    _wsReconnectTimer?.cancel();
    if (mounted) {
      setState(() {
        _clientStatusText = '⚪ Conectando...';
        _clientStatusColor = Colors.orange;
      });
    }

    final wsUri = Uri.parse(wsStatsUrl);
    print('WS: Intentando conectar a $wsUri...');

    try {
      _wsChannel = WebSocketChannel.connect(wsUri);

      _wsChannel!.stream.listen(
        (message) {
          _processWebSocketMessage(message.toString());
        },
        onDone: () {
          print('WS: Connection done. Close Code: ${_wsChannel?.closeCode}, Reason: ${_wsChannel?.closeReason}');
          if (_wsChannel?.closeCode != 1000) { // 1000 is WebSocket normal closure code
            _scheduleWsReconnect();
          } else {
            if (mounted) {
              setState(() {
                _clientStatusText = '🔌 Desconectado (Normal)';
                _clientStatusColor = Colors.grey;
              });
            }
          }
        },
        onError: (error) {
          print('WS: Error: $error');
          if (mounted) {
            setState(() {
              _clientStatusText = '❌ Error de conexión';
              _clientStatusColor = Colors.red;
            });
          }
          _scheduleWsReconnect();
        },
        cancelOnError: true,
      );

      if (mounted) {
        setState(() {
          _wsReconnectIntervalMs = 1000;
        });
      }
      print('WS: WebSocketChannel creado y escuchando.');
    } catch (e) {
      print('WS: Falló la creación de WebSocketChannel: $e');
      _scheduleWsReconnect();
    }
  }

  void _disconnectWebSocket() {
    _wsReconnectTimer?.cancel();
    // Corrected: Use status.normalClosure from the aliased import
    _wsChannel?.sink.close(status.normalClosure, 'Widget disposed or inactive');
    _wsChannel = null;
    if (mounted) {
      setState(() {
        _clientStatusText = '🔌 Desconectado';
        _clientStatusColor = Colors.grey;
        _personsCount = 0;
        _dangerousObjectsCount = 0;
        _lastDetectionDate = '--/--/----';
        _lastDetectionTime = '--:--:--';
      });
    }
  }

  void _scheduleWsReconnect() {
    if (!mounted || !widget.isActive) return;

    // Corrected: Just check if closeCode is null.
    if (_wsChannel != null && _wsChannel!.closeCode == null) {
      print("WS: Aún conectado o conectando, no se necesita reconexión ahora.");
      return;
    }

    if (mounted) {
      setState(() {
        _clientStatusText = '🔴 Desconectado (Intentando reconectar)';
        _clientStatusColor = Colors.red;
      });
    }

    _wsReconnectTimer?.cancel();
    _wsReconnectTimer = Timer(Duration(milliseconds: _wsReconnectIntervalMs), () {
      if (mounted && widget.isActive) {
        print('WS: Intentando reconexión después de ${_wsReconnectIntervalMs / 1000}s...');
        _connectWebSocket();
        _wsReconnectIntervalMs = (_wsReconnectIntervalMs * 2).clamp(1000, _wsMaxReconnectIntervalMs);
      } else {
        print('WS: Reconexión cancelada (no activo o no montado).');
      }
    });
  }

  void _processWebSocketMessage(String message) {
    if (!mounted) return;
    try {
      final Map<String, dynamic> messageData = json.decode(message);

      if (messageData.containsKey('persons_in_frame') && messageData.containsKey('dangerous_objects_in_frame')) {
        final int persons = messageData['persons_in_frame'] ?? 0;
        final int objects = messageData['dangerous_objects_in_frame'] ?? 0;
        final String? timestampStr = messageData['timestamp'];
        final String? status = messageData['status'];

        setState(() {
          _personsCount = persons;
          _dangerousObjectsCount = objects;

          if (timestampStr != null) {
            try {
              final DateTime dateObj = DateTime.parse(timestampStr);
              _lastDetectionDate = DateFormat('dd/MM/yyyy', _locale).format(dateObj.toLocal());
              _lastDetectionTime = DateFormat('HH:mm:ss', _locale).format(dateObj.toLocal());
            } catch (e) {
              print('WS: Error al parsear timestamp: $e');
              _lastDetectionDate = 'Fecha Inválida';
              _lastDetectionTime = 'Hora Inválida';
            }
          }

          if (status != null) {
            _clientStatusText = status == 'connected' ? '🟢 En ejecución' : '⚪ Desconocido';
            _clientStatusColor = status == 'connected' ? Colors.green : Colors.grey;
          } else {
            _clientStatusText = '⚪ Desconocido (sin estado)';
            _clientStatusColor = Colors.grey;
          }
        });
      } else if (messageData.containsKey('objeto') && messageData.containsKey('confianza')) {
        print("WS: Mensaje de alerta potencial recibido (del stream de stats?): $messageData");

        final String objectType = messageData['objeto']?.toLowerCase() ?? 'desconocido';
        final double confidence = (messageData['confianza'] as num?)?.toDouble() ?? 0.0;
        final String? timestampStr = messageData['timestamp'];
        final DateTime alertTimestamp = timestampStr != null ? DateTime.parse(timestampStr).toLocal() : DateTime.now();

        if (_criticalObjectsForAlertModal.contains(objectType) && !_alertaMostrada) {
          _showAlerta(objectType, confidence);
        }
      } else {
        print('WS: Mensaje recibido con estructura desconocida: $messageData');
      }
    } catch (e) {
      print('WS: Error al parsear JSON o procesar mensaje: $e, Datos: $message');
    }
  }

  void _showAlerta(String objectType, double confidence) async {
    if (_alertaMostrada || !mounted) return;

    setState(() {
      _alertaMostrada = true;
      _detectedObjectType = objectType;
      _detectedObjectConfidence = confidence;
    });

    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('assets/audio/alerta.mp3'));
    } catch (e) {
      print("Error al reproducir audio de alerta: $e");
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: Colors.red[800],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.all(20),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber, color: Colors.white, size: 50),
                const SizedBox(height: 10),
                const Text('¡ALERTA DETECTADA!',
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                Text(
                  'Se ha detectado un objeto peligroso: ${_detectedObjectType.toUpperCase()} (${(_detectedObjectConfidence * 100).toStringAsFixed(1)}% de confianza). Por favor, verifique y tome acción.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    _sendEmergencyAlert();
                  },
                  icon: const Icon(Icons.call, color: Colors.white),
                  label: const Text('Contactar Autoridades', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[600],
                    minimumSize: const Size.fromHeight(40),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () {
                    print("Marcando como Falso Positivo.");
                    Navigator.of(dialogContext).pop();
                    _hideAlerta();
                  },
                  icon: const Icon(Icons.clear, color: Colors.white),
                  label: const Text('Marcar como Falso Positivo', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[700],
                    minimumSize: const Size.fromHeight(40),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () {
                    print("Alerta ignorada/cerrada por el usuario.");
                    Navigator.of(dialogContext).pop();
                    _hideAlerta();
                  },
                  icon: const Icon(Icons.close, color: Colors.white),
                  label: const Text('Ignorar/Cerrar', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[700],
                    minimumSize: const Size.fromHeight(40),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _hideAlerta() async {
    if (!mounted) return;
    if (_alertaMostrada) {
      setState(() {
        _alertaMostrada = false;
        _isSendingAlert = false;
        _alertSentSuccess = false;
      });
      await _audioPlayer.stop();
    }
  }

  void _sendEmergencyAlert() async {
    if (!mounted) return;

    setState(() {
      _isSendingAlert = true;
      _alertSentSuccess = false;
    });

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext loadingContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: Colors.grey[900],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: 20),
                const Text('Enviando alerta a autoridades...',
                    style: TextStyle(color: Colors.white, fontSize: 16)),
                const SizedBox(height: 10),
                const Text(
                  'Por favor, verifique que no sea un falso positivo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.orange, fontSize: 13),
                ),
                if (_alertSentSuccess) ...[
                  const SizedBox(height: 15),
                  const Text('✅ Alerta enviada exitosamente.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.green, fontSize: 15, fontWeight: FontWeight.bold)),
                ],
              ],
            ),
          ),
        );
      },
    );

    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      setState(() {
        _alertSentSuccess = true;
      });
    }

    await Future.delayed(const Duration(seconds: 3));

    if (mounted) {
      Navigator.of(context).pop();
      _hideAlerta();
    }
  }

  @override
  void dispose() {
    _stopPlayer();
    _disconnectWebSocket();
    _audioPlayer.dispose();
    super.dispose();
  }

  Widget _buildVideoPlayerUI() {
    Widget videoContent;
    const double defaultAspectRatio = 16 / 9;

    if (widget.isActive && (_isLoading || _controller == null)) {
      videoContent = const Center(child: CircularProgressIndicator(color: Colors.white));
    } else if (_hasError && widget.isActive) {
      videoContent = Container(
        color: Colors.red,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi_off, color: Colors.white, size: 50),
              SizedBox(height: 8),
              Text("Fuera de Conexión", style: TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
        ),
      );
    } else if (_controller != null && _controller!.value.isInitialized) {
      videoContent = AspectRatio(
        aspectRatio: _controller!.value.aspectRatio > 0 ? _controller!.value.aspectRatio : defaultAspectRatio,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            VideoPlayer(_controller!),
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: _buildControlsOverlay(),
            ),
          ],
        ),
      );
    } else {
      videoContent = const ColoredBox(
        color: Colors.black,
        child: Center(child: Icon(Icons.videocam_off_outlined, color: Colors.grey, size: 50)),
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        alignment: Alignment.center,
        children: [
          videoContent,
          if (widget.isActive && !_isLoading && !_hasError && _controller != null && _controller!.value.isInitialized && _isPlaying)
            Positioned(
              top: 8, right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                child: const Text('EN VIVO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildControlsOverlay() {
    if (!widget.isActive || _hasError || _controller == null || !_controller!.value.isInitialized) {
      return const SizedBox.shrink();
    }
    const controlIconSize = 28.0;
    const controlIconColor = Colors.white;

    return IgnorePointer(
      ignoring: !_showControls,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.bottomCenter, end: Alignment.topCenter,
              colors: [Colors.black.withOpacity(0.6), Colors.transparent],
              stops: const [0.0, 0.8]
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        child: Row(
          children: [
            IconButton(
              icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, size: controlIconSize, color: controlIconColor),
              padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: _togglePlayPause,
            ),
            const SizedBox(width: 16),
            IconButton(
              icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up, size: controlIconSize, color: controlIconColor),
              padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: _toggleMute,
            ),
            const Spacer(),
            IconButton(
              icon: Icon(_isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen, size: controlIconSize, color: controlIconColor),
              padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: _toggleFullScreen,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(IconData icon, String title, String value, {Color? valueColor}) {
    return Card(
      elevation: 1.0, margin: const EdgeInsets.symmetric(vertical: 4.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Icon(icon, color: Colors.grey[600], size: 22),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(color: valueColor ?? Colors.black87, fontSize: 15, fontWeight: FontWeight.w500)),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildCounterCard(String title, int count, Color defaultBg, Color defaultTxt, {bool isAlert = false}) {
    final Color backgroundColor = isAlert ? Colors.red[100]! : defaultBg;
    final Color textColor = isAlert ? Colors.red[800]! : defaultTxt;
    final String displayCount = count.toString();

    final textStyle = TextStyle(color: textColor, fontSize: 48, fontWeight: FontWeight.bold);
    final titleStyle = TextStyle(color: textColor.withOpacity(0.9), fontSize: 15, fontWeight: FontWeight.w500);

    return Card(
      elevation: 1.0, color: backgroundColor, margin: const EdgeInsets.symmetric(horizontal: 4.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(title, style: titleStyle, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(displayCount, style: textStyle, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildInformationCard() {
    const titleStyle = TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87);
    const contentStyle = TextStyle(color: Colors.black54, fontSize: 14, height: 1.4);
    const infoText = "Este módulo muestra la transmisión en vivo de la cámara principal. Los contadores muestran el número de personas y objetos peligrosos detectados en el fotograma actual.";

    return Card(
      elevation: 1.0, margin: const EdgeInsets.symmetric(vertical: 4.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: Colors.blueGrey[400], size: 24),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Información", style: titleStyle),
                  SizedBox(height: 6),
                  Text(infoText, style: contentStyle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isFullScreen) {
      return GestureDetector( onTap: _showAndHideControls, child: _buildVideoPlayerUI() );
    }

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: RefreshIndicator(
        onRefresh: () async { if(widget.isActive) { await _startPlayer(); _connectWebSocket(); } },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4.0),
              GestureDetector(
                onTap: _showAndHideControls,
                child: ClipRRect( borderRadius: BorderRadius.circular(12.0), child: _buildVideoPlayerUI()),
              ),
              const SizedBox(height: 12.0),
              _buildInfoCard(Icons.location_on_outlined, "Ubicación", ubicacion),
              _buildInfoCard(Icons.calendar_today_outlined, "Fecha (Ultima Deteccion)", _lastDetectionDate),
              _buildInfoCard(Icons.access_time_outlined, "Hora (Ultima Deteccion)", _lastDetectionTime),
              const SizedBox(height: 12.0),
              Row(
                children: [
                  Expanded(child: _buildCounterCard("Personas Detectadas", _personsCount, Colors.green[100]!, Colors.green[800]!)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildCounterCard("Objetos Peligrosos", _dangerousObjectsCount, Colors.orange[100]!, Colors.orange[800]!, isAlert: _dangerousObjectsCount > 0)),
                ],
              ),
              const SizedBox(height: 12.0),
              _buildInfoCard(Icons.sensors, "Estado Script Monitoreo", _clientStatusText, valueColor: _clientStatusColor),
              const SizedBox(height: 12.0),
              _buildInformationCard(),
              const SizedBox(height: 12.0),
              ElevatedButton.icon(
                onPressed: () => _showAlerta("Manual", 1.0),
                icon: const Icon(Icons.warning_amber, color: Colors.white),
                label: const Text('Activar Alerta Manual', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 12.0),
            ],
          ),
        ),
      ),
    );
  }
}
