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

class _CamaraEnVivoViewState extends State<CamaraEnVivoView>
    with AutomaticKeepAliveClientMixin {
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
  final String wsStatsUrl = 'wss://tunelvps.duckdns.org/stats';

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

  final List<String> _criticalObjectsForAlertModal = [
    'gun',
    'knife',
    'rifle',
    'mask',
    'helmet'
  ];

  @override
  bool get wantKeepAlive => true;
  
  // --- INICIO: Lógica funcional (sin cambios) ---
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
      final response = await http.head(Uri.parse(videoUrl)).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) throw Exception('Video server not available: ${response.statusCode}');
      
      _controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true, allowBackgroundPlayback: false,),
          httpHeaders: {'User-Agent': 'FlutterApp/1.0', 'Accept': '*/*', 'Connection': 'keep-alive',},);
      _initializeVideoPlayerFuture = _controller!.initialize();
      await _initializeVideoPlayerFuture!.timeout(const Duration(seconds: 30), onTimeout: () => throw Exception('Timeout initializing video'));
      
      if (!mounted || _controller == null) return;
      _controller!.addListener(_videoListener);
      _controller!.setLooping(true);
      _controller!.setVolume(_isMuted ? 0.0 : 1.0);
      await _controller!.play();
      
      if (mounted) setState(() { _isLoading = false; _isPlaying = true; _hasError = false; });
      _scheduleControlsHide();
    } catch (error) {
      if (mounted) { setState(() { _isLoading = false; _hasError = true; }); _scheduleRetry(); }
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
        if (controller.value.isInitialized && controller.value.isPlaying) { await controller.pause(); }
        await controller.dispose();
      } catch (e) { print("Error disposing previous video controller: $e"); }
      if (mounted) setState(() { _isLoading = false; _hasError = false; _isPlaying = false; });
    }
  }

  void _scheduleRetry() {
    if (!mounted || _isRetrying || !widget.isActive) return;
    if (mounted) setState(() { _isRetrying = true; });
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && widget.isActive) { _startPlayer(); } 
      else { if (mounted) setState(() => _isRetrying = false); }
    });
  }

  void _videoListener() {
    if (!mounted || _controller == null || !_controller!.value.isInitialized) return;
    final value = _controller!.value;
    if (value.isPlaying != _isPlaying) { if (mounted) setState(() { _isPlaying = value.isPlaying; }); }
    if (value.hasError && !_isLoading && !_isRetrying && !_hasError) { if (mounted) { setState(() { _hasError = true; }); _scheduleRetry(); }
    } else if (!value.hasError && (_hasError || _isRetrying)) {
      _retryTimer?.cancel();
      if (mounted) { setState(() { _hasError = false; _isRetrying = false; _isPlaying = value.isPlaying; }); }
    }
  }

  Future<void> _seekToLive() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      final duration = _controller!.value.duration;
      if (duration > const Duration(seconds: 5)) { await _controller!.seekTo(duration - const Duration(seconds: 5)); }
    } catch (e) { /* Silently ignore */ }
  }

  void _togglePlayPause() async {
    if (_controller == null || !_controller!.value.isInitialized) { if (widget.isActive && !_isLoading) { _startPlayer(); } return; }
    await _seekToLive();
    if (_controller!.value.isPlaying) { await _controller!.pause(); } 
    else { await _controller!.play().catchError((e) { if (mounted) setState(() => _hasError = true); _scheduleRetry(); }); }
    _showAndHideControls();
  }

  void _toggleMute() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() { _isMuted = !_isMuted; _controller!.setVolume(_isMuted ? 0.0 : 1.0); });
    _showAndHideControls();
  }

  void _exitFullScreenProgrammatically() async {
    if (_isFullScreen) {
      widget.onFullScreenToggle(false); _isFullScreen = false;
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      if (mounted) setState(() {});
    }
  }

  void _toggleFullScreen() async {
    if (_isLoading && !_isFullScreen) return;
    final newFullScreenState = !_isFullScreen;
    widget.onFullScreenToggle(newFullScreenState); _isFullScreen = newFullScreenState;
    if (_isFullScreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight,]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
    if (mounted) { setState(() {}); _showAndHideControls(); }
  }

  void _showAndHideControls() {
    if (!mounted) return;
    setState(() { _showControls = true; }); _scheduleControlsHide();
  }

  void _scheduleControlsHide() {
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && widget.isActive && _isPlaying && _showControls && !_hasError) { if (mounted) setState(() { _showControls = false; }); }
    });
  }

  void _connectWebSocket() {
    if (_wsChannel != null && _wsChannel!.closeCode == null) return;
    _wsReconnectTimer?.cancel();
    if (mounted) { setState(() { _clientStatusText = '⚪ Conectando...'; _clientStatusColor = Colors.orange; }); }
    try {
      _wsChannel = WebSocketChannel.connect(Uri.parse(wsStatsUrl));
      _wsChannel!.stream.listen(
        (message) => _processWebSocketMessage(message.toString()),
        onDone: () { if (_wsChannel?.closeCode != 1000) { _scheduleWsReconnect(); } else { if (mounted) setState(() { _clientStatusText = '🔌 Desconectado'; _clientStatusColor = Colors.grey; }); }},
        onError: (error) { if (mounted) setState(() { _clientStatusText = '❌ Error'; _clientStatusColor = Colors.red; }); _scheduleWsReconnect(); },
        cancelOnError: true,
      );
      if (mounted) setState(() { _wsReconnectIntervalMs = 1000; });
    } catch (e) { _scheduleWsReconnect(); }
  }

  void _disconnectWebSocket() {
    _wsReconnectTimer?.cancel();
    _wsChannel?.sink.close(status.normalClosure, 'Widget disposed'); _wsChannel = null;
    if (mounted) {
      setState(() {
        _clientStatusText = '🔌 Desconectado'; _clientStatusColor = Colors.grey;
        _personsCount = 0; _dangerousObjectsCount = 0;
        _lastDetectionDate = '--/--/----'; _lastDetectionTime = '--:--:--';
      });
    }
  }

  void _scheduleWsReconnect() {
    if (!mounted || !widget.isActive) return;
    if (_wsChannel != null && _wsChannel!.closeCode == null) return;
    if (mounted) setState(() { _clientStatusText = '🔴 Reconectando...'; _clientStatusColor = Colors.red; });
    _wsReconnectTimer?.cancel();
    _wsReconnectTimer = Timer(Duration(milliseconds: _wsReconnectIntervalMs), () {
      if (mounted && widget.isActive) { _connectWebSocket(); _wsReconnectIntervalMs = (_wsReconnectIntervalMs * 2).clamp(1000, _wsMaxReconnectIntervalMs); }
    });
  }

  void _processWebSocketMessage(String message) {
    if (!mounted) return;
    try {
      final Map<String, dynamic> data = json.decode(message);
      if (data.containsKey('persons_in_frame')) {
        setState(() {
          _personsCount = data['persons_in_frame'] ?? 0; _dangerousObjectsCount = data['dangerous_objects_in_frame'] ?? 0;
          if (data['timestamp'] != null) {
            try {
              final date = DateTime.parse(data['timestamp']).toLocal();
              _lastDetectionDate = DateFormat('dd/MM/yyyy', _locale).format(date);
              _lastDetectionTime = DateFormat('HH:mm:ss', _locale).format(date);
            } catch (e) { /* silent */ }
          }
          if (data['status'] != null) {
            final isConnected = data['status'] == 'connected';
            _clientStatusText = isConnected ? '🟢 En ejecución' : '⚪ Desconocido'; _clientStatusColor = isConnected ? Colors.green.shade700 : Colors.grey;
          }
        });
      } else if (data.containsKey('objeto')) {
        final objectType = data['objeto']?.toLowerCase() ?? 'desconocido';
        final confidence = (data['confianza'] as num?)?.toDouble() ?? 0.0;
        if (_criticalObjectsForAlertModal.contains(objectType) && !_alertaMostrada) { _showAlerta(objectType, confidence); }
      }
    } catch (e) { /* silent */ }
  }

  void _showAlerta(String objectType, double confidence) async {
    if (_alertaMostrada || !mounted) return;
    setState(() { _alertaMostrada = true; _detectedObjectType = objectType; _detectedObjectConfidence = confidence; });
    try { await _audioPlayer.stop(); await _audioPlayer.play(AssetSource('assets/audio/alerta.mp3'));
    } catch (e) { /* silent */ }

    await showDialog( context: context, barrierDismissible: false,
      builder: (ctx) => PopScope( canPop: false,
        child: AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          contentPadding: const EdgeInsets.all(24),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error, size: 60),
              const SizedBox(height: 16),
              Text('¡Alerta de Seguridad!', style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer, fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Text('Detectado: ${_detectedObjectType.toUpperCase()}\nConfianza: ${(_detectedObjectConfidence * 100).toStringAsFixed(1)}%', textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer.withOpacity(0.8), fontSize: 16)),
              const SizedBox(height: 24),
              SizedBox( width: double.infinity, child: ElevatedButton.icon(
                  onPressed: () { Navigator.of(ctx).pop(); _sendEmergencyAlert(); },
                  icon: const Icon(Icons.call), label: const Text('Contactar Autoridades'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error, foregroundColor: Theme.of(context).colorScheme.onError,
                    padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),),),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextButton(onPressed: () { Navigator.of(ctx).pop(); _hideAlerta(); }, child: const Text('Falso Positivo'))),
                const SizedBox(width: 8),
                Expanded(child: TextButton(onPressed: () { Navigator.of(ctx).pop(); _hideAlerta(); }, child: const Text('Ignorar'))),
              ]),],),),),);
  }

  void _hideAlerta() async {
    if (!mounted) return;
    if (_alertaMostrada) { setState(() { _alertaMostrada = false; _isSendingAlert = false; _alertSentSuccess = false; }); await _audioPlayer.stop(); }
  }

  void _sendEmergencyAlert() async {
    if (!mounted) return;
    setState(() => _isSendingAlert = true);
    // Simulación de envío
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _alertSentSuccess = true);
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) _hideAlerta();
  }

  @override
  void dispose() {
    _stopPlayer();
    _disconnectWebSocket();
    _audioPlayer.dispose();
    super.dispose();
  }
  // --- FIN: Lógica funcional ---

  // --- INICIO: Widgets de UI rediseñados ---
  
  Widget _buildVideoPlayerUI() {
    Widget videoContent;

    if (widget.isActive && (_isLoading || _controller == null)) {
      videoContent = const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0,));
    } else if (_hasError && widget.isActive) {
      videoContent = Container(
        color: Colors.black,
        child: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.error_outline, color: Colors.red.shade300, size: 48),
            const SizedBox(height: 16),
            const Text("Error de Conexión", style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 8),
            if (_isRetrying) const Text("Reintentando...", style: TextStyle(color: Colors.white54, fontSize: 12)),
          ],),),);
    } else if (_controller != null && _controller!.value.isInitialized) {
      videoContent = AspectRatio(
        aspectRatio: _controller!.value.aspectRatio,
        child: Stack(alignment: Alignment.bottomCenter, children: [
            VideoPlayer(_controller!),
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: _buildControlsOverlay(),
            ),
          ],),);
    } else {
      videoContent = const ColoredBox(
        color: Colors.black,
        child: Center(child: Icon(Icons.videocam_off_outlined, color: Colors.grey, size: 50)),);
    }

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16.0),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4),),],),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16.0),
          child: Stack(
            alignment: Alignment.center,
            children: [
              videoContent,
              if (widget.isActive && !_isLoading && !_hasError && _controller != null && _controller!.value.isInitialized && _isPlaying)
                Positioned(top: 12, right: 12, child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)),
                    child: const Text('EN VIVO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),),),
            ],),),),);
  }

  Widget _buildControlsOverlay() {
    if (!widget.isActive || _hasError || _controller == null || !_controller!.value.isInitialized) return const SizedBox.shrink();
    return IgnorePointer(
      ignoring: !_showControls,
      child: Container(
        decoration: BoxDecoration(gradient: LinearGradient(
          begin: Alignment.bottomCenter, end: Alignment.center,
          colors: [Colors.black.withOpacity(0.7), Colors.transparent],),),
        padding: const EdgeInsets.all(8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildControlButton(_isMuted ? Icons.volume_off : Icons.volume_up, _toggleMute),
            _buildControlButton(_isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded, _togglePlayPause, size: 56),
            _buildControlButton(_isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen, _toggleFullScreen),
          ],),),);
  }

  Widget _buildControlButton(IconData icon, VoidCallback onPressed, {double size = 40}) {
    return Container(
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), shape: BoxShape.circle,),
      child: IconButton(
        icon: Icon(icon, size: size / 1.8, color: Colors.white),
        iconSize: size,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildInfoCard(IconData icon, String title, String value, {Color? iconBgColor, Color? valueColor}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),),
        child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: (iconBgColor ?? Colors.grey).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8.0),),
              child: Icon(icon, color: iconBgColor ?? Colors.grey.shade600, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  const SizedBox(height: 2),
                  Text(value, style: TextStyle(color: valueColor ?? Colors.black87, fontSize: 15, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,),
                ],),)],),),);
  }

  Widget _buildCounterCard(String title, int count, IconData icon, Color defaultBg, Color defaultTxt, {bool isAlert = false}) {
    final Color backgroundColor = isAlert ? Colors.red.shade100 : defaultBg;
    final Color textColor = isAlert ? Colors.red.shade800 : defaultTxt;
    final IconData displayIcon = isAlert ? Icons.warning_amber_rounded : icon;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(color: backgroundColor, borderRadius: BorderRadius.circular(16),),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(right: -20, bottom: -20,
              child: Icon(displayIcon, size: 100, color: textColor.withOpacity(0.1),),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(count.toString(), style: TextStyle(color: textColor, fontSize: 48, fontWeight: FontWeight.bold),),
                const SizedBox(height: 4),
                Text(title, style: TextStyle(color: textColor.withOpacity(0.9), fontSize: 15, fontWeight: FontWeight.w500),),
              ],),
          ],),),);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isFullScreen) {
      return Scaffold(backgroundColor: Colors.black,
          body: Center(child: GestureDetector(onTap: _showAndHideControls, child: _buildVideoPlayerUI())));
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade200,
      body: RefreshIndicator(
        onRefresh: () async { if (widget.isActive) { await _startPlayer(); _connectWebSocket(); } },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // --- Video Player ---
              GestureDetector(onTap: _showAndHideControls, child: _buildVideoPlayerUI()),
              const SizedBox(height: 16.0),

              // --- Info Cards Row ---
              Row(
                children: [
                  _buildInfoCard(Icons.location_on_outlined, "Ubicación", ubicacion, iconBgColor: Colors.blue),
                  const SizedBox(width: 12),
                  _buildInfoCard(Icons.sensors, "Estado Script", _clientStatusText, iconBgColor: _clientStatusColor, valueColor: _clientStatusColor),
                ],
              ),
              const SizedBox(height: 12.0),
              Row(
                children: [
                  _buildInfoCard(Icons.calendar_today_outlined, "Fecha", _lastDetectionDate, iconBgColor: Colors.purple),
                  const SizedBox(width: 12),
                  _buildInfoCard(Icons.access_time_outlined, "Hora", _lastDetectionTime, iconBgColor: Colors.teal),
                ],
              ),
              const SizedBox(height: 16.0),
              
              // --- Counter Cards Row ---
              Row(children: [
                  _buildCounterCard("Personas", _personsCount, Icons.people_alt_outlined, Colors.green.shade100, Colors.green.shade800),
                  const SizedBox(width: 12),
                  _buildCounterCard("Objetos", _dangerousObjectsCount, Icons.shield_outlined, Colors.orange.shade100, Colors.orange.shade800, isAlert: _dangerousObjectsCount > 0),
                ],
              ),
              const SizedBox(height: 24.0),
              
              // --- Manual Alert Button ---
              ElevatedButton.icon(
                onPressed: () => _showAlerta("Manual", 1.0),
                icon: const Icon(Icons.campaign_outlined),
                label: const Text('Activar Alerta Manual'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}