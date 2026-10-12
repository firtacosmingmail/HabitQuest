import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as gsi;

/// Web: Google's own "Continue with Google" button (Google Identity
/// Services renders it, following Google's branding by construction). Its
/// sign-ins arrive on `GoogleSignIn.instance.authenticationEvents`.
Widget? buildGoogleWebButton({required double minimumWidth}) =>
    gsi.renderButton(
      configuration: gsi.GSIButtonConfiguration(
        type: gsi.GSIButtonType.standard,
        theme: gsi.GSIButtonTheme.outline,
        size: gsi.GSIButtonSize.large,
        text: gsi.GSIButtonText.continueWith,
        shape: gsi.GSIButtonShape.pill,
        logoAlignment: gsi.GSIButtonLogoAlignment.left,
        minimumWidth: minimumWidth,
      ),
    );
