import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:flutter/services.dart';

// --- Modelo de Datos ---
class VideoInfo {
  final String id;
  final String name;
  final String thumbnailLink;
  final DateTime createdTime;

  const VideoInfo({ // Added const constructor
    required this.id,
    required this.name,
    required this.thumbnailLink,
    required this.createdTime,
  });

  factory VideoInfo.fromJson(Map<String, dynamic> json) {
    return VideoInfo(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Nombre Desconocido',
      thumbnailLink: json['thumbnailLink'] ?? '',
      createdTime: DateTime.tryParse(json['createdTime'] ?? '') ?? DateTime(1970),
    );
  }
}

// --- Pantalla del Reproductor con VLC ---
class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String videoName;

  const VideoPlayerScreen({
    super.key,
    required this.videoUrl,
    required this.videoName,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VlcPlayerController _controller;
  bool _isPlaying = false;
  bool _showControls = true;
  bool _isFullScreen = false;
  bool _isBuffering = true;
  bool _isInitialized = false;
  double _aspectRatio = 16 / 9;
  Timer? _controlsTimer;

  @override
  void initState() {
    super.initState();
    _controller = VlcPlayerController.network(
      widget.videoUrl,
      hwAcc: HwAcc.full,
      autoPlay: false,
      options: VlcPlayerOptions(),
    );
    _controller.addListener(_vlcListener);
     Future.delayed(const Duration(milliseconds: 100), () {
       if (mounted && !_controller.value.isPlaying) {
         _controller.play();
       }
     });
    _scheduleControlsHide();
  }

  void _vlcListener() {
    if (!mounted) return;
    final value = _controller.value;

    final isPlayingNow = value.isPlaying;
    final isBufferingNow = value.isBuffering;
    final isInitializedNow = value.isInitialized;
    final aspectRatioNow = value.aspectRatio > 0 ? value.aspectRatio : 16 / 9;

    bool needsSetState = false;
    if (isPlayingNow != _isPlaying) { _isPlaying = isPlayingNow; needsSetState = true; }
    if (isBufferingNow != _isBuffering) { _isBuffering = isBufferingNow; needsSetState = true; }
    if (isInitializedNow != _isInitialized) { _isInitialized = isInitializedNow; needsSetState = true; }
    if ((aspectRatioNow - _aspectRatio).abs() > 0.01) { _aspectRatio = aspectRatioNow; needsSetState = true; }

    if (value.hasError) {
        if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
                 SnackBar(content: Text("Error: ${value.errorDescription}"))
             );
        }
    }
     if (needsSetState) setState(() {});
  }

  void _togglePlayPause() {
    if (!_isInitialized) return;
    if (_controller.value.isPlaying) { _controller.pause(); }
    else { _controller.play(); }
    // No need for setState here as the listener will handle it
    _showAndHideControls();
  }

  void _toggleFullScreenPlayer() async {
     final newFullScreenState = !_isFullScreen;
     setState(() { _isFullScreen = newFullScreenState; });

     if (_isFullScreen) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
     } else {
         await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
         await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
     }
     // No need for setState here as the orientation change rebuilds
      _showAndHideControls();
  }

  void _showAndHideControls() {
    if (!mounted) return;
    setState(() { _showControls = true; });
    _scheduleControlsHide();
  }

  void _scheduleControlsHide() {
     _controlsTimer?.cancel();
     _controlsTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _isPlaying && _showControls) {
           if(mounted) setState(() { _showControls = false; });
        }
     });
  }

  @override
  void dispose() {
     if (_isFullScreen) {
         SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
         SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
     }
    _controlsTimer?.cancel();
    _controller.removeListener(_vlcListener);
    _controller.stopRendererScanning();
    _controller.dispose();
    super.dispose();
  }

  Widget _buildPlayerControls() {
     if(!_isInitialized) return const SizedBox.shrink();
     const controlIconSize = 28.0;
     const controlIconColor = Colors.white;

     return IgnorePointer(
       ignoring: !_showControls,
       child: AnimatedOpacity(
          opacity: _showControls ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: Container(
            decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.bottomCenter, end: Alignment.topCenter,
                    colors: [Colors.black.withAlpha((255 * 0.6).round()), Colors.transparent],
                    stops: const [0.0, 0.8]
                ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder<VlcPlayerValue>(
                    valueListenable: _controller,
                    builder: (context, value, child) {
                      final durationMs = value.duration.inMilliseconds;
                      final positionMs = value.position.inMilliseconds;
                      double progress = 0.0;
                      if (durationMs > 0 && positionMs >= 0 && positionMs <= durationMs) {
                        progress = positionMs / durationMs;
                      } else if (positionMs > durationMs && durationMs > 0) {
                         progress = 1.0;
                      }
                      return LinearProgressIndicator(
                        value: progress,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
                        backgroundColor: Colors.white.withAlpha(100),
                        minHeight: 3,
                      );
                    },
                  ),
                  const SizedBox(height: 10.0),
                  Row(
                    children: [
                        IconButton(
                            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, size: controlIconSize, color: controlIconColor),
                            padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: _togglePlayPause,
                        ),
                        const SizedBox(width: 16),
                        ValueListenableBuilder<VlcPlayerValue>(
                            valueListenable: _controller,
                            builder: (context, value, child) {
                                return Text(
                                    '${_formatDuration(value.position)} / ${_formatDuration(value.duration)}',
                                    style: const TextStyle(color: Colors.white, fontSize: 12),
                                );
                            },
                        ),
                        const Spacer(),
                        IconButton(
                            icon: Icon(_isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen, size: controlIconSize, color: controlIconColor),
                            padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: _toggleFullScreenPlayer,
                        ),
                    ],
                  ),
                ],
            ),
          ),
       ),
     );
  }

  String _formatDuration(Duration duration) {
    if (duration.inMilliseconds < 0) return '00:00';
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return [ if (duration.inHours > 0) hours, minutes, seconds ].join(':');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _isFullScreen ? null : AppBar(
          title: Text(widget.videoName, style: const TextStyle(fontSize: 16)),
          backgroundColor: Colors.black.withAlpha((255 * 0.5).round()),
          elevation: 0,
          foregroundColor: Colors.white, // Ensure icons/text are white
      ),
      body: GestureDetector(
        onTap: _showAndHideControls,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VlcPlayer(
              controller: _controller,
              aspectRatio: _aspectRatio,
              placeholder: const Center(child: CircularProgressIndicator()),
            ),
             Positioned.fill(
               child: Align(
                  alignment: Alignment.bottomCenter,
                  child: _buildPlayerControls()
                )
             ),
             if (_isBuffering && !_controller.value.hasError)
               const Center(child: CircularProgressIndicator(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}

// --- Vista Principal de Clips ---
class ClipsView extends StatefulWidget {
  const ClipsView({super.key});

  @override
  State<ClipsView> createState() => _ClipsViewState();
}

class _ClipsViewState extends State<ClipsView> with AutomaticKeepAliveClientMixin {
  List<VideoInfo> _videos = [];
  bool _isLoading = true;
  String? _error;
  String _sortOrder = 'desc';
  final String _apiBaseUrl = 'https://tunelvps.sytes.net/api';
  final String _locale = 'es_PE';
  static const _gridMaxExtent = 200.0;
  static const _gridAspectRatio = 3 / 4;
  static const _gridSpacing = 10.0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting(_locale, null);
    _fetchVideos();
  }

  Future<void> _fetchVideos() async {
    if (!mounted) return;
    setState(() { _isLoading = true; _error = null; });
    final Uri url = Uri.parse('$_apiBaseUrl/videos?sort=$_sortOrder');

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        if(mounted) {
          setState(() {
            _videos = data.map((json) => VideoInfo.fromJson(json)).toList();
            _isLoading = false;
          });
        }
      } else {
        if(mounted) {
          setState(() {
            _error = 'Error ${response.statusCode}: No se pudieron cargar los videos.';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error de conexión o tiempo de espera agotado.';
          _isLoading = false;
        });
      }
    }
  }

  void _playVideo(VideoInfo videoInfo) {
    final videoUrl = '$_apiBaseUrl/video/${videoInfo.id}';
    Navigator.push( context,
      MaterialPageRoute( builder: (context) => VideoPlayerScreen(
          videoUrl: videoUrl, videoName: videoInfo.name,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) => DateFormat('dd/MM/yyyy HH:mm', _locale).format(date);

  Widget _buildVideoGrid() {
    if (_videos.isEmpty && !_isLoading) {
      return const Center(child: Text('No se encontraron videos.'));
    }
    return GridView.builder(
      key: ValueKey(_sortOrder), // Add key to force rebuild on sort change if needed
      padding: const EdgeInsets.all(_gridSpacing),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: _gridMaxExtent, childAspectRatio: _gridAspectRatio,
        crossAxisSpacing: _gridSpacing, mainAxisSpacing: _gridSpacing,
      ),
      itemCount: _videos.length,
      itemBuilder: (context, index) => _VideoGridItem( // Use extracted widget
        video: _videos[index],
        onTap: _playVideo,
        formatDate: _formatDate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
         title: const Text("Clips Grabados"), elevation: 0,
         backgroundColor: theme.scaffoldBackgroundColor, foregroundColor: theme.textTheme.bodyLarge?.color,
         actions: [
            Padding( padding: const EdgeInsets.symmetric(horizontal: 8.0),
               child: DropdownButtonHideUnderline(
                 child: DropdownButton<String>(
                     value: _sortOrder, icon: const Icon(Icons.sort),
                     items: const [
                         DropdownMenuItem(value: 'desc', child: Text('Más recientes')),
                         DropdownMenuItem(value: 'asc', child: Text('Más antiguos')),
                     ],
                     onChanged: (value) {
                         if (value != null && value != _sortOrder) {
                             setState(() { _sortOrder = value; });
                             _fetchVideos();
                         }
                     },
                 ),
               ),
            ),
         ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
     if (_isLoading) {
       return const Center(child: CircularProgressIndicator());
     } else if (_error != null) {
       return Center(
          child: Padding( padding: const EdgeInsets.all(20.0),
             child: Column( mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   const Icon(Icons.error_outline, color: Colors.red, size: 50),
                   const SizedBox(height: 16),
                   Text(_error!, textAlign: TextAlign.center),
                   const SizedBox(height: 20),
                   ElevatedButton.icon( icon: const Icon(Icons.refresh), label: const Text("Reintentar"), onPressed: _fetchVideos)
                ],
             ),
          ),
       );
     } else {
       return RefreshIndicator( onRefresh: _fetchVideos, child: _buildVideoGrid() );
     }
  }
}

// --- Widget Interno para el Item de la Cuadrícula --- (Optimización)
class _VideoGridItem extends StatelessWidget {
  final VideoInfo video;
  final Function(VideoInfo) onTap;
  final String Function(DateTime) formatDate;

  const _VideoGridItem({
    required this.video,
    required this.onTap,
    required this.formatDate,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias, elevation: 2.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        onTap: () => onTap(video),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded( flex: 3,
              child: Image.network( video.thumbnailLink, fit: BoxFit.cover,
                loadingBuilder: (ctx, child, progress) => progress == null
                    ? child
                    : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                errorBuilder: (ctx, err, stack) => const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column( crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text( video.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text( formatDate(video.createdTime), style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}