import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controller/phone_controller_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
  ]);
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Apex RC Controller',
      home: PhoneControllerPage(),
    ),
  );
}
