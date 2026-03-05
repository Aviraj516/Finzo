import 'dart:async';
import 'package:flutter/material.dart';
import '../screens/home_screen.dart';

class SplashScreen extends StatefulWidget {
const SplashScreen({super.key});

@override
State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
with SingleTickerProviderStateMixin {

late AnimationController _controller;
late Animation<double> _scaleAnim;
late Animation<double> _fadeAnim;

@override
void initState() {
super.initState();


_controller = AnimationController(
  vsync: this,
  duration: const Duration(milliseconds: 900),
);

_scaleAnim = Tween<double>(begin: 0.7, end: 1.0).animate(
  CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
);

_fadeAnim = CurvedAnimation(
  parent: _controller,
  curve: Curves.easeIn,
);

_controller.forward();

// Navigate after 3 seconds
Timer(const Duration(seconds: 3), () {
  Navigator.pushReplacement(
    context,
    PageRouteBuilder(
      pageBuilder: (_, __, ___) => const HomeScreen(),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
      transitionDuration: const Duration(milliseconds: 500),
    ),
  );
});


}

@override
void dispose() {
_controller.dispose();
super.dispose();
}

@override
Widget build(BuildContext context) {
return Scaffold(
backgroundColor: const Color(0xFFF6F7F5),
body: Center(
child: FadeTransition(
opacity: _fadeAnim,
child: ScaleTransition(
scale: _scaleAnim,
child: Column(
mainAxisSize: MainAxisSize.min,
children: [
Container(
width: 80,
height: 80,
decoration: const BoxDecoration(
color: Color(0xFF4CAF50),
shape: BoxShape.circle,
),
child: const Center(
child: Text(
'🌱',
style: TextStyle(fontSize: 38),
),
),
),


            const SizedBox(height: 20),

            const Text(
              'Finzo',
              style: TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1B2B1A),
                letterSpacing: -0.5,
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'Grow your money habits 🌿',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF888888),
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);


}
}
