import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import 'home_page.dart';

// Este transformador personalizado replica el 'background-position' de CSS.
class _BackgroundGradientTransform extends GradientTransform {
  final Offset position;
  final double sizeFactor;

  const _BackgroundGradientTransform({required this.position, this.sizeFactor = 8.0});

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    final double x = -bounds.width * position.dx * (sizeFactor - 1);
    final double y = -bounds.height * position.dy * (sizeFactor - 1);
    return Matrix4.translationValues(x, y, 0.0);
  }
}

class LoginView extends StatefulWidget {
  final AuthService authService;
  const LoginView({super.key, required this.authService});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Permite que google_fonts cargue fuentes en tiempo de ejecución si no están empaquetadas.
    GoogleFonts.config.allowRuntimeFetching = true;
    widget.authService.initAppLinks(_handleTokenReceivedAndNavigate);
  }

  @override
  void dispose() {
    widget.authService.disposeAppLinks();
    super.dispose();
  }

  void _handleTokenReceivedAndNavigate(String token) {
    widget.authService.saveJwtToken(token).then((_) {
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => HomePage(authService: widget.authService)),
          (Route<dynamic> route) => false,
        );
      }
    });
  }

  void _showSnackbar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter()),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : Colors.green,
      ),
    );
  }

  Future<void> _nativeGoogleSignIn() async {
    setState(() => _isLoading = true);
    final response = await widget.authService.nativeGoogleSignIn();
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (response['Success'] == true && response['Token'] != null) {
      _showSnackbar('Login con Google (Nativo) exitoso!');
      _handleTokenReceivedAndNavigate(response['Token']);
    } else if (response['IsPendingApproval'] == true) {
      _showSnackbar('Pendiente de aprobación: ${response['Message']}.');
    } else {
      _showSnackbar(response['Message'] ?? 'Error con Google (Nativo).', isError: true);
    }
  }

  Future<void> _openWebLoginExternalBrowser() async {
    setState(() => _isLoading = true);
    final String urlString = widget.authService.getWebLoginUrl();
    final Uri url = Uri.parse(urlString);

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      _showSnackbar('No se pudo abrir el navegador para iniciar sesión.', isError: true);
    }
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: Column(
        children: [
          const Expanded(child: _AnimatedHeader()),
          _BottomSheet(
            isLoading: _isLoading,
            onGoogleSignIn: _nativeGoogleSignIn,
            onEmailSignIn: _openWebLoginExternalBrowser,
          ),
        ],
      ),
    );
  }
}

class _AnimatedHeader extends StatelessWidget {
  const _AnimatedHeader();
  @override
  Widget build(BuildContext context) {
    return const ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          _AnimatedGradientBackground(),
          Center(child: _MessageRotator()),
        ],
      ),
    );
  }
}

class _AnimatedGradientBackground extends StatefulWidget {
  const _AnimatedGradientBackground();
  @override
  State<_AnimatedGradientBackground> createState() => _AnimatedGradientBackgroundState();
}

class _AnimatedGradientBackgroundState extends State<_AnimatedGradientBackground> with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _positionAnim;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _brightnessAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 30))..repeat();
    final curve = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);

    // Replicando 'background-position' del CSS
    _positionAnim = TweenSequence<Offset>([
      TweenSequenceItem(tween: Tween(begin: const Offset(0.0, 0.5), end: const Offset(0.8, 0.3)), weight: 20),
      TweenSequenceItem(tween: Tween(begin: const Offset(0.8, 0.3), end: const Offset(0.6, 0.8)), weight: 20),
      TweenSequenceItem(tween: Tween(begin: const Offset(0.6, 0.8), end: const Offset(0.2, 0.7)), weight: 20),
      TweenSequenceItem(tween: Tween(begin: const Offset(0.2, 0.7), end: const Offset(0.9, 0.1)), weight: 20),
      TweenSequenceItem(tween: Tween(begin: const Offset(0.9, 0.1), end: const Offset(0.0, 0.5)), weight: 20),
    ]).animate(curve);

    // Replicando 'transform: scale' del CSS
    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.01), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.01, end: 1.005), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.005, end: 1.01), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.01, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 20),
    ]).animate(curve);

    // Replicando 'filter: brightness' del CSS
    _brightnessAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.95), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 0.95, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.9), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 0.9), weight: 20),
    ]).animate(curve);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnim.value,
          child: ColorFiltered(
            colorFilter: ColorFilter.mode(Colors.black.withOpacity(1.0 - _brightnessAnim.value), BlendMode.darken),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  transform: _BackgroundGradientTransform(position: _positionAnim.value),
                  colors: const [
                    Color(0xFF0f1419), Color(0xFF1e2a3a), Color(0xFF2d3748), Color(0xFF3182ce), Color(0xFF2b77cb),
                    Color(0xFF2c5aa0), Color(0xFF1a365d), Color(0xFF2a4365), Color(0xFF1e2a3a), Color(0xFF0f1419),
                    Color(0xFF1e2a3a), Color(0xFF3182ce), Color(0xFF2b77cb), Color(0xFF0f1419)
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MessageData {
  final IconData icon;
  final String title;
  final String subtitle;
  const _MessageData({required this.icon, required this.title, required this.subtitle});
}

class _MessageRotator extends StatelessWidget {
  const _MessageRotator();

  static const List<_MessageData> _messages = [
    _MessageData(icon: Icons.shield, title: 'Seguridad Comunitaria', subtitle: 'Monitoreo y alerta de delitos en tiempo real para proteger tu entorno.'),
    _MessageData(icon: Icons.visibility, title: 'Vigilancia Inteligente', subtitle: 'Sistema avanzado de detección y prevención de incidentes urbanos.'),
    _MessageData(icon: Icons.group, title: 'Red Colaborativa', subtitle: 'Conecta con tu comunidad para crear un entorno más seguro para todos.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: List.generate(_messages.length, (index) {
        return _AnimatedMessageItem(
          key: ValueKey(index),
          data: _messages[index],
          animationDelay: Duration(seconds: index * 5),
          totalDuration: const Duration(seconds: 15),
        );
      }),
    );
  }
}

class _AnimatedMessageItem extends StatefulWidget {
  final _MessageData data;
  final Duration animationDelay;
  final Duration totalDuration;
  const _AnimatedMessageItem({super.key, required this.data, required this.animationDelay, required this.totalDuration});
  @override
  State<_AnimatedMessageItem> createState() => _AnimatedMessageItemState();
}

class _AnimatedMessageItemState extends State<_AnimatedMessageItem> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _position;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.totalDuration);
    
    Timer(widget.animationDelay, () {
      if (mounted) _controller.repeat();
    });

    // Replicando los keyframes de la animación 'messageSequence'
    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 5), // 0-5% in
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 25),                                        // 5-30% stay
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)), weight: 5),  // 30-35% out
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 65),                                        // 35-100% gone
    ]).animate(_controller);

    _position = TweenSequence<Offset>([
      TweenSequenceItem(tween: Tween(begin: const Offset(0, -0.4), end: Offset.zero).chain(CurveTween(curve: Curves.easeOut)), weight: 5),
      TweenSequenceItem(tween: Tween(begin: Offset.zero, end: Offset.zero), weight: 25),
      TweenSequenceItem(tween: Tween(begin: Offset.zero, end: const Offset(0, -0.4)).chain(CurveTween(curve: Curves.easeIn)), weight: 5),
      TweenSequenceItem(tween: Tween(begin: const Offset(0, -0.4), end: const Offset(0, -0.4)), weight: 65),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      // El child se construye una sola vez para un rendimiento óptimo.
      child: _MessageContent(data: widget.data),
      builder: (context, child) => FadeTransition(
        opacity: _opacity,
        child: SlideTransition(
          position: _position,
          child: child,
        ),
      ),
    );
  }
}

class _MessageContent extends StatelessWidget {
  final _MessageData data;
  const _MessageContent({required this.data});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
              child: Container(
                width: 112, height: 112,
                decoration: BoxDecoration(color: Colors.white.withAlpha(26), borderRadius: BorderRadius.circular(32)),
                child: Icon(data.icon, color: const Color(0xFF90CDF4), size: 64, semanticLabel: data.title),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Text(data.title, textAlign: TextAlign.center, style: GoogleFonts.inter(textStyle: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.bold, letterSpacing: -0.5))),
          const SizedBox(height: 12),
          Text(data.subtitle, textAlign: TextAlign.center, style: GoogleFonts.inter(textStyle: const TextStyle(color: Color(0xFFcbd5e1), fontSize: 17, height: 1.5))),
        ],
      ),
    );
  }
}

class _BottomSheet extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onGoogleSignIn;
  final VoidCallback onEmailSignIn;
  const _BottomSheet({required this.isLoading, required this.onGoogleSignIn, required this.onEmailSignIn});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 40),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(89), blurRadius: 35, spreadRadius: -6, offset: const Offset(0, -12))]
      ),
      child: isLoading
          ? const SizedBox(height: 140, child: Center(child: CircularProgressIndicator(color: Colors.white)))
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LoginButton(onPressed: onGoogleSignIn, isPrimary: true, icon: SvgPicture.asset('assets/images/google_logo.svg', width: 24, height: 24), text: 'Continuar con Google'),
                const SizedBox(height: 24),
                _LoginButton(onPressed: onEmailSignIn, text: 'Iniciar sesión con correo'),
              ],
            ),
    );
  }
}

class _LoginButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String text;
  final Widget? icon;
  final bool isPrimary;
  const _LoginButton({required this.onPressed, required this.text, this.icon, this.isPrimary = false});

  @override
  Widget build(BuildContext context) {
    final style = TextButton.styleFrom(
      backgroundColor: isPrimary ? const Color(0xFF3182CE) : Colors.transparent,
      foregroundColor: isPrimary ? Colors.white : const Color(0xFF94a3b8),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 30),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: isPrimary ? BorderSide.none : const BorderSide(color: Color(0xFF334155), width: 2.5),
      ),
      shadowColor: isPrimary ? const Color(0xFF3182CE).withAlpha(115) : Colors.transparent,
      elevation: isPrimary ? 5 : 0,
      splashFactory: isPrimary ? InkRipple.splashFactory : NoSplash.splashFactory,
    );

    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: onPressed,
        style: style,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) icon!,
            if (icon != null) const SizedBox(width: 14),
            Text(text, style: GoogleFonts.inter(textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.5))),
          ],
        ),
      ),
    );
  }
}