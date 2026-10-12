import 'package:flutter/material.dart';

Widget buildGoogleSignInButton({required VoidCallback onPressed}) =>
    OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.g_mobiledata_rounded, size: 26),
      label: const Text('Tiếp tục với Google'),
    );
