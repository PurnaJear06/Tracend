import 'package:flutter/material.dart';

class TracendLoadingIndicator extends StatelessWidget {
  final double size;

  const TracendLoadingIndicator({super.key, this.size = 18.0});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: const CircularProgressIndicator(strokeWidth: 2),
    );
  }
}
