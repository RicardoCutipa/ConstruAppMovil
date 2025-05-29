import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

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
  String _currentTime = '';
  String _currentDate = '';
  Timer? _retryTimer;
  bool _isRetrying = false;
  Timer? _timeUpdateTimer;

  final String videoUrl = 'http://161.132.38.250:3333/app/stream/llhls.m3u8';
  final String ubicacion = "Entrada Principal";
  final int _peruTimeZoneOffset = -5;
  static const String _locale = 'es_PE';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting(_locale, null);
    if (widget.isActive) {
      _startPlayer();
      _startTimeUpdates();
    } else {
       _updateTimeDisplay();
    }
  }

  @override
  void didUpdateWidget(covariant CamaraEnVivoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      if (widget.isActive) {
        _startPlayer();
        _startTimeUpdates();
      } else {
        _stopPlayer();
        _stopTimeUpdates();
         if (_isFullScreen) {
            _exitFullScreenProgrammatically();
         }
      }
    }
  }

 void _startTimeUpdates() {
    _stopTimeUpdates();
    _updateTimeDisplay();
    if (!_isFullScreen) {
        _timeUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
            if(!_isFullScreen) {
                _updateTimeDisplay();
            } else {
                timer.cancel();
            }
        });
    }
 }

  void _stopTimeUpdates() {
    _timeUpdateTimer?.cancel();
    _timeUpdateTimer = null;
  }

 void _updateTimeDisplay() {
    if (!mounted) return;
    final peruTime = DateTime.now().toUtc().add(Duration(hours: _peruTimeZoneOffset));
    final newDate = DateFormat('dd/MM/yyyy', _locale).format(peruTime);
    final newTime = DateFormat('HH:mm:ss', _locale).format(peruTime);

    if (newDate != _currentDate || newTime != _currentTime) {
      setState(() {
        _currentDate = newDate;
        _currentTime = newTime;
      });
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

    _controller = VideoPlayerController.networkUrl(
      Uri.parse(videoUrl),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );

    _initializeVideoPlayerFuture = _controller!.initialize();

    try {
      await _initializeVideoPlayerFuture;
      if (!mounted || _controller == null) return;
      _controller!.addListener(_videoListener);
      _controller!.setLooping(true);
      _controller!.setVolume(_isMuted ? 0.0 : 1.0);
      await _controller!.play();
      if (mounted) {
        setState(() { _isLoading = false; _isPlaying = true; });
      }
      _scheduleControlsHide();
    } catch (error) {
      if (mounted) {
        setState(() { _isLoading = false; _hasError = true; });
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
             print("Error disposing previous controller: $e");
          }
          if (mounted) {
              setState(() { _isLoading = false; _hasError = false; _isPlaying = false; });
          }
      }
  }

  void _scheduleRetry() {
    if (!mounted || _isRetrying || !widget.isActive) return;
    if(mounted) setState(() { _isRetrying = true; });
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && widget.isActive) {
        _startPlayer();
      } else {
         if(mounted) setState(() => _isRetrying = false );
      }
    });
  }

  void _videoListener() {
    if (!mounted || _controller == null || !_controller!.value.isInitialized) return;

    final value = _controller!.value;
    final isCurrentlyPlaying = value.isPlaying;

    if (isCurrentlyPlaying != _isPlaying) {
      if(mounted) setState(() { _isPlaying = isCurrentlyPlaying; });
    }

    if (value.hasError && !_isLoading && !_isRetrying && !_hasError) {
      if (mounted) {
        setState(() { _hasError = true; });
        _scheduleRetry();
      }
    } else if (!value.hasError && (_hasError || _isRetrying)) {
        _retryTimer?.cancel();
        if(mounted) {
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
      await _controller!.play().catchError((e){
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
         _startTimeUpdates();
         if (mounted) setState(() {});
     }
 }

 void _toggleFullScreen() async {
    if (_isLoading && !_isFullScreen) return;

    final newFullScreenState = !_isFullScreen;
    widget.onFullScreenToggle(newFullScreenState);
    _isFullScreen = newFullScreenState;

    if (_isFullScreen) {
        _stopTimeUpdates();
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        await SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight,
        ]);
    } else {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
        _startTimeUpdates();
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
        if(mounted) setState(() { _showControls = false; });
      }
    });
  }

  @override
  void dispose() {
    _stopTimeUpdates();
    _stopPlayer();
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

  Widget _buildInfoCard(IconData icon, String title, String value) {
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
                Text(value, style: const TextStyle(color: Colors.black87, fontSize: 15, fontWeight: FontWeight.w500)),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildCounterCard(String title, String count, Color backgroundColor, Color textColor) {
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
            Text(count, style: textStyle, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildInformationCard() {
    const titleStyle = TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87);
    const contentStyle = TextStyle(color: Colors.black54, fontSize: 14, height: 1.4);
    const infoText = "Este módulo muestra la transmisión en vivo de la cámara principal. Los contadores muestran el número de personas y objetos peligrosos detectados en tiempo real.";

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
        onRefresh: () async { if(widget.isActive) { await _startPlayer(); } },
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
              _buildInfoCard(Icons.calendar_today_outlined, "Fecha", _currentDate),
              _buildInfoCard(Icons.access_time_outlined, "Hora", _currentTime),
              const SizedBox(height: 12.0),
              Row(
                children: [
                  Expanded(child: _buildCounterCard("Personas Detectadas", "--", Colors.green[100]!, Colors.green[800]!)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildCounterCard("Objetos Peligrosos", "--", Colors.orange[100]!, Colors.orange[800]!)),
                ],
              ),
              const SizedBox(height: 12.0),
              _buildInformationCard(),
              const SizedBox(height: 12.0),
            ],
          ),
        ),
      ),
    );
  }
}