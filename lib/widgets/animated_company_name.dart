// import 'dart:async';
// import 'package:flutter/material.dart';
//
// class AnimatedCompanyName extends StatefulWidget {
//   const AnimatedCompanyName({super.key});
//
//   @override
//   State<AnimatedCompanyName> createState() => _AnimatedCompanyNameState();
// }
//
// class _AnimatedCompanyNameState extends State<AnimatedCompanyName>
//     with SingleTickerProviderStateMixin {
//   late Timer _timer;
//   String _displayText = 'أمل naboo';
//   final String _originalText = 'أمل naboo';
//   int _cycle = 0;
//   final List<String> _charSet = [
//     ...'أبجديهوزحطيكلمنسعفصقرشتثخذضظغ'.split(''),
//     ...'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split(''),
//     ...'0123456789'.split(''),
//     ' '
//   ];
//
//   @override
//   void initState() {
//     super.initState();
//     // Start timer for animation every 400ms
//     _timer = Timer.periodic(const Duration(milliseconds: 400), (timer) {
//       setState(() {
//         _cycle++;
//         if (_cycle % 12 == 0) {
//           // Every 12 cycles, reset to original
//           _displayText = _originalText;
//         } else {
//           // Randomly change one character
//           _displayText = _mutateString(_originalText);
//         }
//       });
//     });
//   }
//
//   String _mutateString(String original) {
//     if (original.isEmpty) return original;
//     int index = DateTime.now().millisecond % original.length;
//     String randomChar = _charSet[DateTime.now().microsecond % _charSet.length];
//     return original.substring(0, index) +
//         randomChar +
//         original.substring(index + 1);
//   }
//
//   @override
//   void dispose() {
//     _timer.cancel();
//     super.dispose();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return AnimatedDefaultTextStyle(
//       duration: const Duration(milliseconds: 200),
//       style: const TextStyle(
//         fontSize: 28,
//         fontWeight: FontWeight.bold,
//         color: Colors.white,
//         shadows: [
//           Shadow(
//             blurRadius: 8,
//             color: Colors.black26,
//             offset: Offset(2, 2),
//           ),
//         ],
//       ),
//       child: Text(
//         _displayText,
//         textDirection: TextDirection.rtl,
//       ),
//     );
//   }
// }