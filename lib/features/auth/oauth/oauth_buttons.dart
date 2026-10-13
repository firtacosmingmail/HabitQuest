import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/theme/app_theme.dart';

/// Both brand buttons share this height and the pill shape of the playful
/// theme (allowed by both guidelines: Google permits pill / rounded, Apple
/// lets apps set the corner radius).
const oauthButtonHeight = 50.0;
const _pill = BorderRadius.all(Radius.circular(oauthButtonHeight / 2));

/// "Continue with Google", per Google's branding guidelines
/// (developers.google.com/identity/branding-guidelines): the official
/// full-colour "G" on white, light theme colours #FFFFFF fill, #747775 1 px
/// stroke and #1F1F1F Roboto Medium text (dark theme: #131314 fill,
/// #8E918F stroke, #E3E3E3 text; the G stays on its white circle).
class GoogleSignInButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool busy;

  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fill = dark ? const Color(0xFF131314) : Colors.white;
    final stroke = dark ? const Color(0xFF8E918F) : const Color(0xFF747775);
    final text = dark ? const Color(0xFFE3E3E3) : const Color(0xFF1F1F1F);
    const base = TextStyle(fontSize: 16, fontWeight: FontWeight.w500);
    final style =
        (AppTheme.useGoogleFonts ? GoogleFonts.roboto(textStyle: base) : base)
            .copyWith(color: text);
    return Semantics(
      button: true,
      label: 'Continue with Google',
      excludeSemantics: true,
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: _pill,
          side: BorderSide(color: stroke),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            height: oauthButtonHeight,
            child: Opacity(
              opacity: onPressed == null && !busy ? 0.6 : 1,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    padding: const EdgeInsets.all(4),
                    decoration: dark
                        ? const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          )
                        : null,
                    child: Image.asset(
                      'assets/brand/google_g.png',
                      key: const ValueKey('google-g-logo'),
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (busy)
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: text,
                      ),
                    )
                  else
                    Flexible(
                      child: Text(
                        'Continue with Google',
                        style: style,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Sign in with Apple", per Apple's HIG: the system-provided button from
/// sign_in_with_apple (Apple logo + title), black on light backgrounds and
/// white on dark ones.
class AppleSignInButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool busy;

  const AppleSignInButton({
    super.key,
    required this.onPressed,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final button = SignInWithAppleButton(
      onPressed: onPressed ?? () {},
      height: oauthButtonHeight,
      borderRadius: _pill,
      style: dark
          ? SignInWithAppleButtonStyle.white
          : SignInWithAppleButtonStyle.black,
    );
    return Stack(
      alignment: Alignment.center,
      children: [
        IgnorePointer(
          ignoring: onPressed == null,
          child: Opacity(
            opacity: onPressed == null && !busy ? 0.6 : 1,
            child: button,
          ),
        ),
        if (busy)
          Positioned(
            right: 20,
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: dark ? Colors.black : Colors.white,
              ),
            ),
          ),
      ],
    );
  }
}

/// "──── or ────" between the provider buttons and the email form.
class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.outlineVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: color, thickness: 1.5)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'or',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(child: Divider(color: color, thickness: 1.5)),
        ],
      ),
    );
  }
}
