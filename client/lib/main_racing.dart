import 'package:flutter/material.dart';

import 'racing/racing_page.dart';

void main() {
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Apex RC · Web Racing',
      home: RacingPage(),
    ),
  );
}
