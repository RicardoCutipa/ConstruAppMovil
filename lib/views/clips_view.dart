import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/services.dart';

// --- Modelo de Datos ---
class VideoInfo {
  final String id;
  final String name;
  final String thumbnailLink;
  final DateTime createdTime;

  const VideoInfo({
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

// --- Pantalla del Reproductor con BetterPlayer ---
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
  late BetterPlayerController _controller;
  final bool _isFullScreen = false;

  @override
  void initState() {
    super.initState();

    BetterPlayerDataSource dataSource = BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      widget.videoUrl,
      videoFormat: BetterPlayerVideoFormat.other,
    );

    _controller = BetterPlayerController(
      BetterPlayerConfiguration(
        autoPlay: true,
        aspectRatio: 16 / 9,
        fit: BoxFit.contain,
        allowedScreenSleep: false,
        controlsConfiguration: BetterPlayerControlsConfiguration(
          enableFullscreen: true,
          enablePlayPause: true,
          enableProgressText: true,
          enableProgressBar: true,
        ),
        fullScreenByDefault: false,
        autoDetectFullscreenDeviceOrientation: true,
        autoDetectFullscreenAspectRatio: true,
      ),
      betterPlayerDataSource: dataSource,
    );
  }

  @override
  void dispose() {
    if (_isFullScreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _isFullScreen
          ? null
          : AppBar(
              title: Text(widget.videoName, style: const TextStyle(fontSize: 16)),
              backgroundColor: Colors.black.withAlpha((255 * 0.5).round()),
              elevation: 0,
              foregroundColor: Colors.white,
            ),
      body: GestureDetector(
        onTap: () {},
        child: Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: BetterPlayer(controller: _controller),
          ),
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
      key: ValueKey(_sortOrder),
      padding: const EdgeInsets.all(_gridSpacing),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: _gridMaxExtent, childAspectRatio: _gridAspectRatio,
        crossAxisSpacing: _gridSpacing, mainAxisSpacing: _gridSpacing,
      ),
      itemCount: _videos.length,
      itemBuilder: (context, index) => _VideoGridItem(
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

// --- Widget Interno para el Item de la Cuadrícula ---
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
