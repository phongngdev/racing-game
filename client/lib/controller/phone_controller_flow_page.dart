import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pairing_payload.dart';
import 'phone_controller_page.dart';
import 'room_pairing_payload.dart';

class PhoneControllerFlowPage extends StatefulWidget {
  const PhoneControllerFlowPage({
    super.key,
    this.initialPairingPayload,
    this.initialRoomPairingPayload,
    this.onExit,
  });

  final PairingPayload? initialPairingPayload;
  final RoomPairingPayload? initialRoomPairingPayload;
  final VoidCallback? onExit;

  @override
  State<PhoneControllerFlowPage> createState() =>
      _PhoneControllerFlowPageState();
}

class _PhoneControllerFlowPageState extends State<PhoneControllerFlowPage> {
  @override
  void initState() {
    super.initState();
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
      ]),
    );
  }

  @override
  void dispose() {
    unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PhoneControllerPage(
    enableQrPairing: true,
    initialPairingPayload: widget.initialPairingPayload,
    initialRoomPairingPayload: widget.initialRoomPairingPayload,
    onExit: widget.onExit,
  );
}
