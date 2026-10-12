import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart';

Widget buildGoogleSignInButton({required VoidCallback onPressed}) =>
    renderButton(
      configuration: GSIButtonConfiguration(
        locale: 'vi',
        size: GSIButtonSize.large,
        text: GSIButtonText.continueWith,
        shape: GSIButtonShape.rectangular,
        minimumWidth: 350,
      ),
    );
