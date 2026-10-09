import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'accounting_components.dart';
import 'accounting_icons.dart';
import 'accounting_theme.dart';
import 'email_authentication_service.dart';
import 'google_account_session.dart';
import 'responsive.dart';
import 'terms_and_conditions.dart';

enum _AuthStep {
  signIn,
  register,
  verify,
  recover,
  resetCode,
  reset,
  resetDone,
}

class AudytSignInPage extends StatefulWidget {
  const AudytSignInPage({super.key, required this.session});
  final GoogleAccountSession session;
  @override
  State<AudytSignInPage> createState() => _AudytSignInPageState();
}

class _AudytSignInPageState extends State<AudytSignInPage> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController(),
      password = TextEditingController(),
      name = TextEditingController(),
      phone = TextEditingController(),
      code = TextEditingController(),
      confirmation = TextEditingController();
  _AuthStep step = _AuthStep.signIn;
  String? challenge, error, notice;
  bool saving = false, accepted = false;
  int cooldown = 0;
  Timer? timer;
  GoogleAccountSession get session => widget.session;
  String get title => switch (step) {
    _AuthStep.signIn => 'Sign In',
    _AuthStep.register => 'Create Account',
    _AuthStep.verify =>
      session.linkChallenge == null ? 'Verify Email' : 'Link Your Account',
    _AuthStep.recover => 'Forgot Password',
    _AuthStep.resetCode => 'Check Your Email',
    _AuthStep.reset => 'Set A New Password',
    _AuthStep.resetDone => 'Password Changed',
  };
  String get subtitle => switch (step) {
    _AuthStep.signIn => 'Welcome back to Audyt.',
    _AuthStep.register => 'Create your Audyt account.',
    _AuthStep.verify =>
      session.linkChallenge == null
          ? 'Enter the six-digit code sent to your email.'
          : 'Verify your existing email account to link Google.',
    _AuthStep.recover => 'Request a code to reset your Audyt password.',
    _AuthStep.resetCode => 'If eligible, a reset code will arrive shortly.',
    _AuthStep.reset => 'Choose a new password and confirm it below.',
    _AuthStep.resetDone => 'Sign in with your new password.',
  };
  @override
  void dispose() {
    timer?.cancel();
    for (final c in [email, password, name, phone, code, confirmation]) {
      c.dispose();
    }
    super.dispose();
  }

  void _go(_AuthStep value) {
    session.cancelPendingAuthentication();
    setState(() {
      step = value;
      error = null;
      notice = null;
      password.clear();
      confirmation.clear();
      code.clear();
    });
    form.currentState?.reset();
  }

  void _back() {
    if (step == _AuthStep.reset) {
      setState(() {
        step = _AuthStep.resetCode;
        error = null;
        notice = null;
        password.clear();
        confirmation.clear();
      });
      form.currentState?.reset();
    } else {
      _go(step == _AuthStep.resetCode ? _AuthStep.recover : _AuthStep.signIn);
    }
  }

  void _cooldown() {
    timer?.cancel();
    cooldown = 60;
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => cooldown--);
      if (cooldown == 0) t.cancel();
    });
  }

  Future<void> _google() async {
    if (step == _AuthStep.register &&
        session.emailAvailable &&
        (!accepted || session.termsVersion.isEmpty)) {
      setState(
        () => error =
            'Review and accept the Terms & Conditions before registering.',
      );
      return;
    }
    await session.signIn(acceptTerms: step == _AuthStep.register && accepted);
    if (!mounted) return;
    if ((session.linkChallenge ?? session.googleVerificationChallenge)
        case final id?) {
      setState(() {
        challenge = id;
        step = _AuthStep.verify;
        error = null;
      });
      _cooldown();
    } else {
      setState(() => error = session.error);
    }
  }

  Future<void> _submit() async {
    if (saving || session.busy || !(form.currentState?.validate() ?? false)) {
      return;
    }
    if (step == _AuthStep.resetCode) {
      setState(() {
        step = _AuthStep.reset;
        error = null;
        notice = null;
      });
      return;
    }
    if (step == _AuthStep.resetDone) {
      _go(_AuthStep.signIn);
      return;
    }
    final service = session.authenticationService;
    if (service == null) return;
    setState(() {
      saving = true;
      error = null;
      notice = null;
    });
    try {
      switch (step) {
        case _AuthStep.signIn:
          await session.signInWithPassword(email.text, password.text);
          if (session.error != null) throw StateError(session.error!);
        case _AuthStep.register:
          if (!accepted || session.termsVersion.isEmpty) {
            throw const AuthenticationFailure('terms_required');
          }
          challenge = await service.register(
            name: name.text,
            email: email.text,
            phone: phone.text,
            password: password.text,
            termsVersion: session.termsVersion,
          );
          password.clear();
          if (mounted) {
            setState(() {
              step = _AuthStep.verify;
              notice =
                  'If registration can proceed, a code will arrive shortly.';
            });
          }
          _cooldown();
        case _AuthStep.verify:
          await session.verifyAccount(challenge!, code.text);
          if (session.error != null) throw StateError(session.error!);
        case _AuthStep.recover:
          challenge = await service.forgotPassword(email.text);
          if (mounted) {
            setState(() {
              step = _AuthStep.resetCode;
              notice = 'If this email has an Audyt password account, a reset code will arrive shortly.';
            });
          }
          _cooldown();
        case _AuthStep.reset:
          await service.resetPassword(challenge!, code.text, password.text);
          if (mounted) {
            setState(() {
              step = _AuthStep.resetDone;
              password.clear();
              confirmation.clear();
              code.clear();
              notice = null;
            });
          }
        case _AuthStep.resetCode:
        case _AuthStep.resetDone:
          break;
      }
    } catch (failure) {
      if (mounted) {
        if (step == _AuthStep.reset &&
            failure is AuthenticationFailure &&
            failure.code == 'invalid_code') {
          setState(() {
            step = _AuthStep.resetCode;
            password.clear();
            confirmation.clear();
          });
        }
        setState(
          () => error = failure is AuthenticationFailure
              ? failure.toString()
              : session.error ??
                    'Account services are unavailable. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _resend() async {
    if (cooldown > 0 || saving || challenge == null) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await session.authenticationService!.resend(challenge!);
      _cooldown();
      if (mounted) setState(() => notice = 'A new code was requested.');
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is AuthenticationFailure
              ? failure.toString()
              : 'Account services are unavailable. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final disabled = saving || session.busy;
      Widget field(
        String label,
        String key,
        TextEditingController controller, {
        bool secret = false,
        bool numeric = false,
        bool required = true,
        int limit = 320,
        String? guidance,
      }) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          accountingFieldLabel(context, label, guidance: guidance),
          const SizedBox(height: accountingFieldLabelGap),
          AuthTextField(
            fieldKey: ValueKey(key),
            controller: controller,
            secret: secret,
            enabled: !disabled,
            numeric: numeric,
            limit: limit,
            hint: secret
                ? 'Enter Password'
                : numeric
                ? 'Six-Digit Code'
                : 'Enter $label',
            validator: (v) {
              final value = v ?? '';
              if (required && value.trim().isEmpty) return 'Enter $label.';
              if (key == 'auth-confirm-password' && value != password.text) {
                return 'The passwords do not match.';
              }
              if (label == 'Email' &&
                  !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                      .hasMatch(value.trim())) {
                return 'Enter a valid email.';
              }
              if (numeric && !RegExp(r'^\d{6}$').hasMatch(value)) {
                return 'Enter all six digits.';
              }
              if (secret &&
                  step != _AuthStep.signIn &&
                  (value.runes.length < 15 || value.runes.length > 128)) {
                return 'Use 15 to 128 characters.';
              }
              return null;
            },
            onSubmitted: (_) => _submit(),
          ),
        ],
      );
      Widget fullButton(Widget button) =>
          SizedBox(width: double.infinity, child: button);
      final primaryLabel = switch (step) {
        _AuthStep.signIn => 'Sign In',
        _AuthStep.register => 'Register',
        _AuthStep.verify => 'Verify',
        _AuthStep.recover => 'Send Code',
        _AuthStep.resetCode => 'Continue',
        _AuthStep.reset => 'Update Password',
        _AuthStep.resetDone => 'Sign In',
      };
      final entry = step == _AuthStep.signIn || step == _AuthStep.register;
      final children = <Widget>[
        _AuthHeader(
          title: title,
          subtitle: subtitle,
          onBack: !entry && step != _AuthStep.resetDone
              ? (disabled ? null : _back)
              : null,
          showBack: !entry && step != _AuthStep.resetDone,
        ),
        const SizedBox(height: AccountingResponsive.pageTitleOuterGap),
        if (!session.emailAvailable)
          AccountingAlert.build(
            context,
            title: 'Email Sign-In Is Not Available Yet',
            description: 'Use Google to sign in. Email registration and password recovery need the account service to be connected.',
            tone: AccountingAlertTone.warning,
            bottomGap: 20,
          ),
        if (error != null || session.error != null)
          AccountingAlert.build(
            context,
            title: 'Could Not Continue',
            description: error ?? session.error!,
            destructive: true,
            bottomGap: 20,
          ),
        if (notice != null && step != _AuthStep.resetCode)
          AccountingAlert.build(
            context,
            title: 'Account Update',
            description: notice!,
            bottomGap: 20,
          ),
        if (step == _AuthStep.register) ...[
          field('Name', 'auth-name', name, limit: 200),
          const SizedBox(height: 20),
          field(
            'Phone Number',
            'auth-phone',
            phone,
            required: false,
            limit: 40,
          ),
          const SizedBox(height: 20),
        ],
        if (step == _AuthStep.signIn ||
            step == _AuthStep.register ||
            step == _AuthStep.recover) ...[
          field('Email', 'auth-email', email),
          const SizedBox(height: 20),
        ],
        if (step == _AuthStep.verify || step == _AuthStep.resetCode) ...[
          field(
            'Verification Code',
            'auth-code',
            code,
            numeric: true,
            limit: 6,
            guidance: step == _AuthStep.resetCode
                ? 'Enter the six-digit email code. It is checked when saving your new password.'
                : null,
          ),
          const SizedBox(height: 20),
        ],
        if (step == _AuthStep.signIn ||
            step == _AuthStep.register ||
            step == _AuthStep.reset) ...[
          field(
            step == _AuthStep.reset ? 'New Password' : 'Password',
            'auth-password',
            password,
            secret: true,
            limit: 128,
            guidance: step == _AuthStep.register || step == _AuthStep.reset
                ? 'Use at least 15 characters. Spaces are allowed.'
                : null,
          ),
          const SizedBox(height: 20),
        ],
        if (step == _AuthStep.reset) ...[
          field(
            'Confirm Password',
            'auth-confirm-password',
            confirmation,
            secret: true,
            limit: 128,
          ),
          const SizedBox(height: AccountingResponsive.groupGap),
        ],
        if (step == _AuthStep.signIn) ...[
          Align(
            alignment: Alignment.centerRight,
            child: _AuthTextLink(
              key: const ValueKey('auth-forgot-password'),
              onPressed: disabled ? null : () => _go(_AuthStep.recover),
              label: 'Forgot Password?',
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (step == _AuthStep.register) ...[
          Row(
            children: [
              if (session.termsVersion.isNotEmpty)
                Checkbox(
                  value: accepted,
                  onChanged: disabled
                      ? null
                      : (v) => setState(() => accepted = v ?? false),
                ),
              Expanded(
                child: Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (session.termsVersion.isNotEmpty)
                      Text(
                        'I accept the',
                        style: AccountingTypography.helper(context),
                      ),
                    _AuthTextLink(
                      key: const ValueKey('auth-terms'),
                      onPressed: () => showTermsAndConditions(context),
                      label: 'Terms & Conditions',
                      small: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        fullButton(
          AccountingButton.primary(
            context,
            key: const ValueKey('auth-submit'),
            fullWidth: true,
            onPressed:
                disabled ||
                    !session.emailAvailable ||
                    (step == _AuthStep.register &&
                        (session.termsVersion.isEmpty || !accepted))
                ? null
                : _submit,
            child: Text(disabled ? 'Please Wait…' : primaryLabel),
          ),
        ),
        if (step == _AuthStep.signIn || step == _AuthStep.register) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Divider(color: AccountingTheme.of(context).border),
              ),
              const SizedBox(width: 8),
              Text('Or', style: AccountingTypography.helper(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Divider(color: AccountingTheme.of(context).border),
              ),
            ],
          ),
          const SizedBox(height: 20),
          fullButton(
            AccountingButton.outline(
              context,
              key: const ValueKey('auth-google'),
              fullWidth: true,
              onPressed: disabled || !session.supported ? null : _google,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Builder(
                    builder: (context) => SvgPicture.asset(
                      'assets/icons/063-google.svg',
                      width: 20,
                      height: 20,
                      colorFilter: ColorFilter.mode(
                        IconTheme.of(context).color ??
                            AccountingTheme.of(context).foreground,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    step == _AuthStep.register
                        ? 'Sign Up With Google'
                        : 'Sign In With Google',
                  ),
                ],
              ),
            ),
          ),
        ],
        if (step == _AuthStep.verify || step == _AuthStep.resetCode) ...[
          const SizedBox(height: AccountingResponsive.groupGap),
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(
                  'Haven’t received a code?',
                  style: AccountingTypography.helper(context),
                ),
                _AuthTextLink(
                  key: const ValueKey('auth-resend'),
                  onPressed: disabled || cooldown > 0 ? null : _resend,
                  label: cooldown > 0
                      ? 'Resend Code In ${cooldown}s'
                      : 'Resend Code',
                ),
              ],
            ),
          ),
        ],
        if (entry) ...[
          const SizedBox(height: AccountingResponsive.groupGap),
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(
                  step == _AuthStep.signIn
                      ? 'Don’t have an account?'
                      : 'Already have an account?',
                  style: AccountingTypography.helper(context),
                ),
                _AuthTextLink(
                  key: const ValueKey('auth-change-mode'),
                  onPressed: disabled
                      ? null
                      : () => _go(
                          step == _AuthStep.signIn
                              ? _AuthStep.register
                              : _AuthStep.signIn,
                        ),
                  label: step == _AuthStep.signIn ? 'Sign Up' : 'Sign In',
                ),
              ],
            ),
          ),
        ],
        if (step != _AuthStep.register) ...[
          const SizedBox(height: 10),
          Center(
            child: _AuthTextLink(
              key: const ValueKey('auth-terms'),
              onPressed: () => showTermsAndConditions(context),
              label: 'Terms & Conditions',
              small: true,
            ),
          ),
        ],
      ];
      return Scaffold(
        backgroundColor: AccountingTheme.of(context).background,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, bounds) => SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (bounds.maxHeight - 40).clamp(0, double.infinity),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: AccountingCard.surface(
                      context,
                      key: const ValueKey('authentication-card'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: accountingContentInset,
                          vertical: AccountingResponsive.pageTitleOuterGap,
                        ),
                        child: AutofillGroup(
                          child: Form(
                            key: form,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: children,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// The established field decoration and existing eye artwork, shared by sign-in
/// and profile password change. Values stay dark; hints retain muted styling.
class AuthTextField extends StatefulWidget {
  const AuthTextField({
    super.key,
    required this.fieldKey,
    required this.controller,
    required this.hint,
    this.secret = false,
    this.numeric = false,
    this.enabled = true,
    this.limit = 320,
    this.validator,
    this.onSubmitted,
  });
  final Key fieldKey;
  final TextEditingController controller;
  final String hint;
  final bool secret, numeric, enabled;
  final int limit;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;
  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  bool visible = false;
  @override
  Widget build(BuildContext context) {
    final decoration = accountingSingleLineInputDecoration(
      context,
      hintText: widget.hint,
    );
    return FormField<String>(
      key: widget.fieldKey,
      initialValue: widget.controller.text,
      enabled: widget.enabled,
      validator: (_) => widget.validator?.call(widget.controller.text),
      builder: (field) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: widget.controller,
            enabled: widget.enabled,
            obscureText: widget.secret && !visible,
            enableSuggestions: !widget.secret,
            autocorrect: !widget.secret,
            keyboardType: widget.numeric
                ? TextInputType.number
                : widget.secret
                ? TextInputType.visiblePassword
                : widget.hint.contains('Email')
                ? TextInputType.emailAddress
                : TextInputType.text,
            style: AccountingTypography.controlValue(context),
            inputFormatters: [
              if (widget.numeric) FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(widget.limit),
            ],
            autofillHints: widget.secret
                ? [AutofillHints.password]
                : widget.hint.contains('Email')
                ? [AutofillHints.email]
                : null,
            decoration: decoration.copyWith(
              enabledBorder: field.hasError
                  ? decoration.errorBorder
                  : decoration.enabledBorder,
              focusedBorder: field.hasError
                  ? decoration.focusedErrorBorder
                  : decoration.focusedBorder,
              suffixIcon: widget.secret
                  ? IconButton(
                      tooltip: visible ? 'Hide Password' : 'Show Password',
                      onPressed: widget.enabled
                          ? () => setState(() => visible = !visible)
                          : null,
                      icon: AccountingIcon(
                        visible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: accountingRecordVisibleIconExtent,
                        color: AccountingTheme.of(context).mutedForeground,
                      ),
                    )
                  : null,
            ),
            onChanged: field.didChange,
            onSubmitted: widget.onSubmitted,
          ),
          if (field.errorText case final error?)
            Padding(
              padding: const EdgeInsets.only(
                top: accountingFieldLabelGap,
                left: accountingContentInset,
                right: accountingContentInset,
              ),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  style: AccountingTypography.helper(context)
                      .copyWith(color: AccountingTheme.of(context).destructive),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Back navigation shares the title line without enlarging its text spacing.
class _AuthHeader extends StatelessWidget {
  const _AuthHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.showBack,
  });
  final String title, subtitle;
  final VoidCallback? onBack;
  final bool showBack;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(
        builder: (context, bounds) {
          final style = AccountingTypography.pageTitle(context);
          final reserve = showBack ? accountingControlHeight : 0.0;
          final painter =
              TextPainter(
                text: TextSpan(text: title, style: style),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
                textAlign: TextAlign.center,
              )..layout(
                maxWidth: (bounds.maxWidth - reserve * 2).clamp(
                  0,
                  double.infinity,
                ),
              );
          final titleHeight = painter.height;
          painter.dispose();
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: reserve),
                child: Center(
                  child: Text(title, textAlign: TextAlign.center, style: style),
                ),
              ),
              if (showBack)
                Positioned(
                  left: 0,
                  top: (titleHeight - accountingControlHeight) / 2,
                  child: AccountingButton.iconOnly(
                    context,
                    key: const ValueKey('auth-change-mode'),
                    onPressed: onBack,
                    icon: Icons.chevron_left_rounded,
                    tooltip: 'Back',
                  ),
                ),
            ],
          );
        },
      ),
      const SizedBox(height: AccountingResponsive.titleSubtitleGap),
      Text(
        subtitle,
        textAlign: TextAlign.center,
        style: AccountingTypography.helper(context),
      ),
    ],
  );
}

/// Authentication links keep typography and hover separate from action buttons.
class _AuthTextLink extends StatelessWidget {
  const _AuthTextLink({
    super.key,
    required this.label,
    required this.onPressed,
    this.small = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    return TextButton(
      onPressed: onPressed,
      style: ButtonStyle(
        textStyle: WidgetStatePropertyAll(
          small
              ? AccountingTypography.helper(context)
              : AccountingTypography.controlValue(context),
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              !states.contains(WidgetState.disabled) &&
                  (states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.focused) ||
                      states.contains(WidgetState.pressed))
              ? tokens.foreground
              : tokens.mutedForeground,
        ),
        minimumSize: const WidgetStatePropertyAll(Size.zero),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      child: Text(label),
    );
  }
}
