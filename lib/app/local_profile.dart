import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image/image.dart' as raster;

import 'accounting_components.dart';
import 'responsive.dart';
import 'field_row_trial.dart';
import 'google_account_session.dart';
import 'accounting_icons.dart';
import 'accounting_theme.dart';
import 'profile_photo_editor.dart';
import 'membership_service.dart';
import 'password_change_dialog.dart';
import 'authentication_page.dart';
import 'terms_and_conditions.dart';

// Profile menus are a padding branch of navigation; parent and chooser share it.
const accountingProfileMenuPanelInset = 4.0;
const accountingProfileMenuItemInset = 12.0;
const accountingProfileMenuIconGap = 12.0;

double _profileMenuWidth(BuildContext context, Iterable<String> labels) {
  var width = 0.0;
  for (final label in labels) {
    final measured = AccountingResponsive.measuredTextWidth(
      context,
      label,
      AccountingTypography.navigation(context),
    );
    if (measured > width) width = measured;
  }
  return width +
      20 +
      accountingProfileMenuIconGap +
      accountingProfileMenuItemInset * 2 +
      accountingProfileMenuPanelInset * 2;
}

ButtonStyle _profileMenuItemStyle(
  BuildContext context, {
  bool selected = false,
  bool submenu = false,
}) {
  final tokens = AccountingTheme.of(context);
  final base = selected
      ? accountingSelectorOptionStyle(context, selected: true)
      : accountingActionMenuItemStyle(context);
  return base.copyWith(
    foregroundColor: WidgetStatePropertyAll(tokens.mutedForeground),
    textStyle: WidgetStatePropertyAll(AccountingTypography.navigation(context)),
    // Flutter reserves 12px before a submenu decoration even if it is empty.
    // That spacer supplies the right inset when the chevron is suppressed.
    padding: WidgetStatePropertyAll(
      EdgeInsets.fromLTRB(
        accountingProfileMenuItemInset,
        5,
        submenu ? 0 : accountingProfileMenuItemInset,
        5,
      ),
    ),
  );
}

/// Contact and work details scoped to a Google identity when connected.
/// These editable fields never confer business permissions.
class LocalProfile {
  const LocalProfile({
    this.name = '',
    this.email = '',
    this.phone = '',
    this.jobTitle = '',
    this.role = '',
    this.photoBase64 = '',
    this.googleSubject = '',
    this.loginEmail = '',
    this.department = '',
    this.employeeReference = '',
    this.responsibility = '',
  });
  final String name;
  final String email;
  final String phone;
  final String jobTitle;

  /// An editable local label. It is not an authentication or approval grant.
  final String role;
  final String photoBase64;
  final String googleSubject;
  final String loginEmail;
  final String department;
  final String employeeReference;
  final String responsibility;
  bool get isComplete =>
      name.trim().isNotEmpty &&
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim()) &&
      desktopRoles.contains(role);
  static const responsibilities = [
    'Finance Oversight',
    'Bookkeeping',
    'Accounts Payable',
    'Accounts Receivable',
    'Payroll',
    'Financial Reporting',
    'Audit And Review',
  ];
  static const desktopRoles = ['Director', 'Accountant'];
  static const channel = MethodChannel('audyt/local-profile');

  Uint8List? get photoBytes {
    if (photoBase64.isEmpty) return null;
    try {
      return base64Decode(photoBase64);
    } on FormatException {
      return null;
    }
  }

  static Future<LocalProfile> load({String googleSubject = ''}) async {
    try {
      final value = await channel.invokeMapMethod<String, String>('load', {
        'googleSubject': googleSubject,
      });
      return LocalProfile(
        name: value?['name'] ?? '',
        email: value?['email'] ?? '',
        phone: value?['phone'] ?? '',
        jobTitle: value?['jobTitle'] ?? '',
        role: value?['role'] ?? '',
        photoBase64: value?['photo'] ?? '',
        googleSubject: value?['googleSubject'] ?? '',
        loginEmail: value?['loginEmail'] ?? '',
        department: value?['department'] ?? '',
        employeeReference: value?['employeeReference'] ?? '',
        responsibility: value?['responsibility'] ?? '',
      );
    } on MissingPluginException {
      return const LocalProfile();
    }
  }

  static Future<List<LocalProfile>> knownAccounts() async {
    try {
      final values = await channel.invokeListMethod<dynamic>('list') ?? [];
      return [
        for (final value in values)
          if (value is Map &&
              value['googleSubject'] is String &&
              value['email'] is String &&
              (value['googleSubject'] as String).isNotEmpty)
            LocalProfile(
              googleSubject: value['googleSubject'] as String,
              email: value['email'] as String,
              loginEmail:
                  value['loginEmail'] as String? ?? value['email'] as String,
              name: value['name'] as String? ?? '',
            ),
      ];
    } on MissingPluginException {
      return [];
    }
  }

  Future<void> save() => channel.invokeMethod<void>('save', {
    'name': name.trim(),
    'email': email.trim(),
    'phone': phone.trim(),
    'jobTitle': jobTitle.trim(),
    'role': role,
    'photo': photoBase64,
    'googleSubject': googleSubject,
    'loginEmail': loginEmail,
    'department': department.trim(),
    'employeeReference': employeeReference.trim(),
    'responsibility': responsibility,
  });
}

/// Optional identity photo: failure never blocks profile setup.
Future<String> loadGoogleProfilePhoto(String? url) async {
  final uri = Uri.tryParse(url ?? '');
  if (uri == null ||
      uri.scheme != 'https' ||
      !(uri.host == 'googleusercontent.com' ||
          uri.host.endsWith('.googleusercontent.com'))) {
    return '';
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final request = await client.getUrl(uri);
    request.followRedirects = false;
    final response = await request.close().timeout(const Duration(seconds: 5));
    if (response.statusCode != 200 || response.contentLength > 2000000) {
      return '';
    }
    final bytes = BytesBuilder();
    await for (final chunk in response.timeout(const Duration(seconds: 5))) {
      bytes.add(chunk);
      if (bytes.length > 2000000) return '';
    }
    final decoded = raster.decodeImage(bytes.takeBytes());
    if (decoded == null) return '';
    return base64Encode(
      raster.encodeJpg(
        raster.copyResizeCropSquare(decoded, size: 256),
        quality: 85,
      ),
    );
  } catch (_) {
    return '';
  } finally {
    client.close(force: true);
  }
}

class LocalProfileMenu extends StatefulWidget {
  const LocalProfileMenu({
    super.key,
    this.submitRegistration,
    this.approvalStatus,
  });
  final Future<void> Function(LocalProfile)? submitRegistration;
  final String? approvalStatus;

  @override
  State<LocalProfileMenu> createState() => _LocalProfileMenuState();
}

class _LocalProfileMenuState extends State<LocalProfileMenu> {
  LocalProfile profile = const LocalProfile();
  // The main window and company routes can each own a header. Coordinate their
  // dialogs and saved values so one Google event never opens setup twice.
  static bool _profileDialogOpen = false;
  static bool _accountDialogOpen = false;
  static final _savedProfile = ValueNotifier<LocalProfile?>(null);
  final google = GoogleAccountSession.shared;

  List<LocalProfile> knownAccounts = [];
  bool _loaded = false;
  bool _dialogOpen = false;
  bool _syncing = false;
  String? _syncedSubject;

  void _googleChanged() {
    if (!mounted) return;
    setState(() {});
    _syncGoogleProfile();
  }

  Future<void> _syncGoogleProfile() async {
    if (!_loaded ||
        _dialogOpen ||
        _accountDialogOpen ||
        _syncing ||
        google.busy ||
        !mounted) {
      return;
    }
    final accountId = google.identityId;
    if (accountId == null) {
      if (_syncedSubject != null) {
        _syncedSubject = null;
        setState(() => profile = const LocalProfile());
      }
      return;
    }
    if (_syncedSubject == accountId) return;
    _syncing = true;
    try {
      var stored = await LocalProfile.load(googleSubject: accountId);
      if (!stored.isComplete &&
          google.googleSubject.isNotEmpty &&
          google.googleSubject != accountId) {
        final legacy = await LocalProfile.load(
          googleSubject: google.googleSubject,
        );
        if (legacy.isComplete) stored = legacy;
      }
      final photo = stored.photoBase64.isNotEmpty
          ? stored.photoBase64
          : await loadGoogleProfilePhoto(google.photoUrl);
      if (!mounted || google.identityId != accountId) return;
      final recentlySaved = _savedProfile.value;
      if (recentlySaved?.googleSubject == accountId) stored = recentlySaved!;
      final value = LocalProfile(
        googleSubject: accountId,
        loginEmail: google.loginEmail ?? '',
        name: stored.name.isEmpty ? google.displayName ?? '' : stored.name,
        email: stored.email.isEmpty ? google.loginEmail ?? '' : stored.email,
        phone: stored.phone,
        jobTitle: stored.jobTitle,
        role: stored.role,
        department: stored.department,
        employeeReference: stored.employeeReference,
        responsibility: stored.responsibility,
        photoBase64: stored.photoBase64.isEmpty ? photo : stored.photoBase64,
      );
      _syncedSubject = accountId;
      setState(() => profile = value);
      if (!stored.isComplete) await _edit(setup: true);
    } on PlatformException {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AccountingDialog.alert(
            context,
            widthFamily: AccountingPopoutWidthFamily.dialog,
            title: 'Profile Could Not Be Loaded',
            content: AccountingAlert.build(
              context,
              title: 'Please Try Again',
              description: 'Your saved profile could not be loaded.',
              destructive: true,
            ),
            actions: [],
          ),
        );
      }
    } finally {
      _syncing = false;
    }
  }

  void _profileSaved() {
    final saved = _savedProfile.value;
    if (!mounted || saved == null || saved.googleSubject != google.identityId) {
      return;
    }
    _syncedSubject = saved.googleSubject;
    setState(() => profile = saved);
  }

  @override
  void dispose() {
    _savedProfile.removeListener(_profileSaved);
    google.removeListener(_googleChanged);
    super.dispose();
  }

  Future<void> _googleAccount() async {
    if (_accountDialogOpen) return;
    _accountDialogOpen = true;
    _dialogOpen = true;
    await showDialog<void>(
      context: context,
      builder: (context) => ListenableBuilder(
        listenable: google,
        builder: (context, _) => AccountingDialog.alert(
          context,
          widthFamily: AccountingPopoutWidthFamily.dialog,
          title: !google.signedIn ? 'Sign In With Google' : 'Google Account',
          description: 'Connect your Google identity to Audyt.',
          maxContentWidth: AccountingPopoutTokens.dialogContentWidth,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (google.loginEmail case final loginEmail?) ...[
                Text(
                  google.displayName ?? loginEmail,
                  style: AccountingTypography.value(context),
                ),
                const SizedBox(height: 8),
                Text(loginEmail, style: AccountingTypography.helper(context)),
                const SizedBox(height: 20),
              ],
              Text(
                'Google sign-in confirms your identity. Business access and role approval will be connected separately.',
                style: AccountingTypography.helper(context),
              ),
              if (google.error case final error?) ...[
                const SizedBox(height: 20),
                Text(
                  error,
                  style: TextStyle(
                    color: AccountingTheme.of(context).destructive,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            AccountingButton.ghost(
              context,
              key: const ValueKey('google-account-close'),
              onPressed: google.busy ? null : () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            AccountingButton.primary(
              context,
              key: const ValueKey('google-account-action'),
              onPressed: google.busy
                  ? null
                  : !google.signedIn
                  ? () async {
                      await google.signIn();
                      if (google.signedIn && context.mounted) {
                        Navigator.pop(context);
                      }
                    }
                  : google.signOut,
              child: Text(
                google.busy
                    ? 'Please Wait…'
                    : !google.signedIn
                    ? 'Sign In With Google'
                    : 'Sign Out',
              ),
            ),
          ],
        ),
      ),
    );
    _dialogOpen = false;
    _accountDialogOpen = false;
    await _syncGoogleProfile();
  }

  Future<void> _loadAccounts() async {
    try {
      final values = await LocalProfile.knownAccounts();
      if (mounted) setState(() => knownAccounts = values);
    } on PlatformException {
      /* A chooser read failure must not replace saved profiles. */
    }
  }

  Future<void> _signOut() async {
    if (_dialogOpen || _accountDialogOpen) return;
    _dialogOpen = true;
    _accountDialogOpen = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => ListenableBuilder(
          listenable: google,
          builder: (context, _) => AccountingDialog.alert(
            context,
            widthFamily: AccountingPopoutWidthFamily.dialog,
            title: 'Sign Out?',
            description: 'You will need to sign in again to use Audyt. Your saved business records remain on this device.',
            contentInset: 20,
            maxContentWidth: AccountingPopoutTokens.dialogContentWidth,
            content: AccountingAlert.build(
              context,
              title: google.error == null
                  ? 'Confirm Sign Out'
                  : 'Could Not Sign Out',
              description:
                  google.error ?? 'Finish saving your work before signing out.',
              tone: google.error == null
                  ? AccountingAlertTone.warning
                  : AccountingAlertTone.critical,
            ),
            actions: [
              AccountingButton.outline(
                context,
                key: const ValueKey('sign-out-cancel'),
                onPressed: google.busy ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              AccountingButton.destructive(
                context,
                key: const ValueKey('sign-out-confirm'),
                onPressed: google.busy
                    ? null
                    : () async {
                        await google.signOut();
                        if (!google.signedIn && context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                leadingIcon: Icons.logout,
                child: Text(google.busy ? 'Please Wait…' : 'Sign Out'),
              ),
            ],
          ),
        ),
      );
    } finally {
      _dialogOpen = false;
      _accountDialogOpen = false;
    }
    await _syncGoogleProfile();
  }

  Future<void> _switchUser({String? expectedEmail}) async {
    if (_dialogOpen || _accountDialogOpen) return;
    _dialogOpen = true;
    _accountDialogOpen = true;
    google.cancelPendingAuthentication();
    final priorId = google.identityId;
    final verificationCode = TextEditingController();
    bool acceptedTerms = false, resending = false;
    String? localError;
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, updateDialog) => ListenableBuilder(
            listenable: google,
            builder: (context, _) {
              final challenge =
                  google.linkChallenge ?? google.googleVerificationChallenge;
              final busy = google.busy || resending;
              return AccountingDialog.alert(
                context,
                widthFamily: AccountingPopoutWidthFamily.normal,
                title: challenge == null
                    ? 'Switch User'
                    : google.linkChallenge != null
                    ? 'Link Your Account'
                    : 'Verify Email',
                description: challenge != null
                    ? 'Enter the six-digit code sent to the selected account email.'
                    : expectedEmail == null
                    ? 'Sign in with a different Google account.'
                    : 'Sign in with $expectedEmail.',
                maxContentWidth: AccountingPopoutTokens.normalContentWidth,
                contentInset: 20,
                content: SizedBox(
                  width: AccountingPopoutTokens.normalContentWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (google.switchError != null ||
                          google.error != null ||
                          localError != null)
                        AccountingAlert.build(
                          context,
                          title: 'Account Not Changed',
                          description:
                              localError ?? google.switchError ?? google.error!,
                          destructive: true,
                          bottomGap: 20,
                        ),
                      if (challenge != null) ...[
                        Text(
                          'Verification Code',
                          style: AccountingTypography.fieldLabel(context),
                        ),
                        const SizedBox(height: 8),
                        AuthTextField(
                          fieldKey: const ValueKey('switch-user-code'),
                          controller: verificationCode,
                          hint: 'Six-Digit Code',
                          numeric: true,
                          limit: 6,
                          enabled: !busy,
                        ),
                        const SizedBox(height: 10),
                        AccountingButton.ghost(
                          context,
                          key: const ValueKey('switch-user-resend'),
                          onPressed: busy
                              ? null
                              : () async {
                                  updateDialog(() {
                                    resending = true;
                                    localError = null;
                                  });
                                  try {
                                    await google.authenticationService!.resend(
                                      challenge,
                                    );
                                  } catch (_) {
                                    if (context.mounted) {
                                      updateDialog(
                                        () => localError = 'Code resend could not be confirmed. Wait before trying again.',
                                      );
                                    }
                                  } finally {
                                    if (context.mounted) {
                                      updateDialog(() => resending = false);
                                    }
                                  }
                                },
                          child: const Text('Resend Code'),
                        ),
                      ] else ...[
                        Text(
                          'Google will verify the selected account again. Business permissions remain unchanged until the new user signs in.',
                          style: AccountingTypography.helper(context),
                        ),
                        if (google.emailAvailable &&
                            google.termsVersion.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Checkbox(
                                value: acceptedTerms,
                                onChanged: busy
                                    ? null
                                    : (v) => updateDialog(
                                        () => acceptedTerms = v ?? false,
                                      ),
                              ),
                              Expanded(
                                child: Text(
                                  'For a new account, I accept the Terms & Conditions.',
                                  style: AccountingTypography.helper(context),
                                ),
                              ),
                            ],
                          ),
                          AccountingButton.ghost(
                            context,
                            key: const ValueKey('switch-user-terms'),
                            onPressed: () => showTermsAndConditions(context),
                            child: const Text('Terms & Conditions'),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
                actions: [
                  AccountingButton.outline(
                    context,
                    key: const ValueKey('switch-user-cancel'),
                    onPressed: busy ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  AccountingButton.primary(
                    context,
                    key: const ValueKey('switch-user-google'),
                    onPressed: busy
                        ? null
                        : () async {
                            updateDialog(() => localError = null);
                            if (challenge != null) {
                              if (!RegExp(r'^\d{6}$')
                                  .hasMatch(verificationCode.text)) {
                                updateDialog(
                                  () => localError = 'Enter all six digits.',
                                );
                                return;
                              }
                              await google.verifyAccount(
                                challenge,
                                verificationCode.text,
                              );
                              if (google.error == null &&
                                  google.identityId != priorId &&
                                  google.signedIn &&
                                  context.mounted) {
                                Navigator.pop(context);
                              }
                            } else {
                              final changed = await google.switchAccount(
                                expectedEmail: expectedEmail,
                                acceptTerms: acceptedTerms,
                              );
                              if (changed && context.mounted) {
                                Navigator.pop(context);
                              }
                            }
                          },
                    child: Text(
                      busy
                          ? 'Please Wait…'
                          : challenge == null
                          ? 'Sign In With Google'
                          : 'Verify',
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    } finally {
      verificationCode.dispose();
      _dialogOpen = false;
      _accountDialogOpen = false;
      google.cancelPendingAuthentication();
    }
    await _loadAccounts();
    await _syncGoogleProfile();
  }

  @override
  void initState() {
    super.initState();
    google.addListener(_googleChanged);
    _savedProfile.addListener(_profileSaved);
    google.initialize();
    _loadAccounts();
    LocalProfile.load().then((value) {
      if (!mounted) return;
      setState(() {
        profile = value;
        _loaded = true;
      });
      _syncGoogleProfile();
    });
  }

  Future<void> _edit({bool setup = false}) async {
    if (_dialogOpen || _profileDialogOpen || !mounted) return;
    _dialogOpen = true;
    _profileDialogOpen = true;
    try {
      final saved = await showDialog<LocalProfile>(
        context: context,
        builder: (context) => _LocalProfileDialog(
          profile: profile,
          setup: setup,
          submitRegistration: widget.submitRegistration,
          approvalStatus: widget.approvalStatus,
        ),
      );
      if (saved != null) {
        _savedProfile.value = saved;
        if (mounted) setState(() => profile = saved);
      }
    } finally {
      _dialogOpen = false;
      _profileDialogOpen = false;
    }
    if (!_syncing) await _syncGoogleProfile();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    final photo = profile.photoBytes;
    final chooserAccounts = [
      for (final stored in knownAccounts)
        if (stored.googleSubject != google.identityId &&
            stored.googleSubject != google.googleSubject)
          stored,
      if (google.identityId != null && google.loginEmail != null)
        LocalProfile(
          googleSubject: google.identityId!,
          loginEmail: google.loginEmail!,
          email: google.loginEmail!,
          name: google.displayName ?? '',
        ),
    ];
    final chooserWidth = _profileMenuWidth(context, [
      for (final account in chooserAccounts) account.loginEmail,
      'Sign In Another User',
    ]);
    final menuWidth = _profileMenuWidth(context, [
      'Edit Profile',
      'Switch User',
      !google.signedIn ? 'Sign In With Google' : 'Sign Out',
    ]);
    return AccountingMenuAnchor(
      menuWidth: menuWidth,
      maxHeight: 280,
      gap: 8,
      style: accountingSelectorMenuStyle(context, menuWidth, 280).copyWith(
        alignment: AlignmentDirectional.bottomEnd,
        padding: const WidgetStatePropertyAll(
          EdgeInsets.all(accountingProfileMenuPanelInset),
        ),
        side: const WidgetStatePropertyAll(BorderSide.none),
      ),
      menuChildren: [
        MenuItemButton(
          key: const ValueKey('profile-menu-profile'),
          onPressed: _edit,
          leadingIcon: AccountingProfileMenuIcon(
            Icons.person_outline,
            color: tokens.mutedForeground,
          ),
          style: _profileMenuItemStyle(context),
          child: Text(
            'Edit Profile',
            style: AccountingTypography.navigation(context),
          ),
        ),
        if (google.signedIn)
          SubmenuButton(
            key: const ValueKey('profile-menu-switch-user'),
            submenuIcon: const WidgetStatePropertyAll(SizedBox.shrink()),
            leadingIcon: AccountingProfileMenuIcon(
              Icons.swap_horiz,
              color: tokens.mutedForeground,
            ),
            style: _profileMenuItemStyle(context, submenu: true),
            menuStyle: accountingSelectorMenuStyle(context, chooserWidth, 360)
                .copyWith(
                  // The profile menu is at the page's right edge. Flutter places
                  // this submenu on the left when its natural width cannot fit on
                  // the right; the offset then becomes the actual panel gap.
                  alignment: Alignment.topRight,
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.all(accountingProfileMenuPanelInset),
                  ),
                ),
            alignmentOffset: const Offset(
              accountingProfileMenuPanelInset + 3,
              accountingProfileMenuPanelInset,
            ),
            onOpen: _loadAccounts,
            menuChildren: [
              for (final account in chooserAccounts)
                MenuItemButton(
                  key: ValueKey('switch-account-${account.googleSubject}'),
                  onPressed:
                      account.loginEmail.toLowerCase() ==
                          google.loginEmail?.toLowerCase()
                      ? null
                      : () => _switchUser(expectedEmail: account.loginEmail),
                  style:
                      _profileMenuItemStyle(
                        context,
                        selected: account.googleSubject == google.identityId,
                      ).copyWith(
                        minimumSize: WidgetStatePropertyAll(
                          Size(
                            chooserWidth - accountingProfileMenuPanelInset * 2,
                            44,
                          ),
                        ),
                        maximumSize: WidgetStatePropertyAll(
                          Size(
                            chooserWidth - accountingProfileMenuPanelInset * 2,
                            double.infinity,
                          ),
                        ),
                      ),
                  leadingIcon: AccountingProfileMenuIcon(
                    Icons.email_outlined,
                    color: tokens.mutedForeground,
                  ),
                  child: Text(
                    account.loginEmail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AccountingTypography.navigation(context),
                  ),
                ),
              MenuItemButton(
                key: const ValueKey('switch-account-add'),
                onPressed: _switchUser,
                leadingIcon: AccountingProfileMenuIcon(
                  Icons.add,
                  color: tokens.mutedForeground,
                ),
                style: _profileMenuItemStyle(context).copyWith(
                  minimumSize: WidgetStatePropertyAll(
                    Size(
                      chooserWidth - accountingProfileMenuPanelInset * 2,
                      44,
                    ),
                  ),
                  maximumSize: WidgetStatePropertyAll(
                    Size(
                      chooserWidth - accountingProfileMenuPanelInset * 2,
                      double.infinity,
                    ),
                  ),
                ),
                child: Text(
                  'Sign In Another User',
                  style: AccountingTypography.navigation(context),
                ),
              ),
            ],
            child: Text(
              'Switch User',
              style: AccountingTypography.navigation(context),
            ),
          ),
        if (!google.signedIn)
          MenuItemButton(
            key: const ValueKey('profile-menu-switch-user'),
            onPressed: google.supported ? _switchUser : null,
            leadingIcon: AccountingProfileMenuIcon(
              Icons.swap_horiz,
              color: tokens.mutedForeground,
            ),
            style: _profileMenuItemStyle(context),
            child: Text(
              'Switch User',
              style: AccountingTypography.navigation(context),
            ),
          ),
        MenuItemButton(
          key: const ValueKey('profile-menu-google'),
          onPressed: google.supported
              ? (google.signedIn ? _signOut : _googleAccount)
              : null,
          leadingIcon: google.signedIn
              ? AccountingProfileMenuIcon(
                  Icons.logout,
                  color: tokens.mutedForeground,
                )
              : SvgPicture.asset(
                  'assets/icons/063-google.svg',
                  width: 20,
                  height: 20,
                  colorFilter: ColorFilter.mode(
                    tokens.mutedForeground,
                    BlendMode.srcIn,
                  ),
                ),
          style: _profileMenuItemStyle(context),
          child: Text(
            !google.signedIn ? 'Sign In With Google' : 'Sign Out',
            style: AccountingTypography.navigation(context),
          ),
        ),
      ],
      builder: (context, controller, child) => IconButton(
        key: const ValueKey('global-profile'),
        tooltip: 'Profile',
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        style: const ButtonStyle(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize: WidgetStatePropertyAll(Size.square(36)),
          maximumSize: WidgetStatePropertyAll(Size.square(36)),
        ),
        icon: CircleAvatar(
          radius: 18,
          backgroundColor: tokens.primary,
          foregroundColor: tokens.primaryForeground,
          backgroundImage: photo == null ? null : MemoryImage(photo),
          child: photo == null
              ? SvgPicture.asset(
                  'assets/icons/profile-top-bar-avatar.svg',
                  width: 20,
                  height: 20,
                  fit: BoxFit.contain,
                  colorFilter: ColorFilter.mode(
                    tokens.primaryForeground,
                    BlendMode.srcIn,
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

class _LocalProfileDialog extends StatefulWidget {
  const _LocalProfileDialog({
    required this.profile,
    this.setup = false,
    this.submitRegistration,
    this.approvalStatus,
  });
  final Future<void> Function(LocalProfile)? submitRegistration;
  final String? approvalStatus;
  final bool setup;
  final LocalProfile profile;

  @override
  State<_LocalProfileDialog> createState() => _LocalProfileDialogState();
}

class _LocalProfileDialogState extends State<_LocalProfileDialog> {
  late final TextEditingController name = TextEditingController(
    text: widget.profile.name,
  );
  late final TextEditingController email = TextEditingController(
    text: widget.profile.email,
  );
  late final TextEditingController phone = TextEditingController(
    text: widget.profile.phone,
  );
  late final TextEditingController jobTitle = TextEditingController(
    text: widget.profile.jobTitle,
  );
  late final department = TextEditingController(
    text: widget.profile.department,
  );
  late final employeeReference = TextEditingController(
    text: widget.profile.employeeReference,
  );
  late String responsibility = widget.profile.responsibility;
  late String role = widget.profile.role;
  late String photoBase64 = widget.profile.photoBase64;
  String? error;
  bool saving = false;

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    phone.dispose();
    jobTitle.dispose();
    department.dispose();
    employeeReference.dispose();
    super.dispose();
  }

  Future<void> _choosePhoto() async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.image);
      if (files.isEmpty) return;
      final bytes = await files.first.readAsBytes();
      if (!mounted) return;
      final encoded = await showProfilePhotoEditor(context, bytes);
      if (encoded != null && mounted) {
        setState(() {
          photoBase64 = encoded;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = 'The photo could not be opened.');
    }
  }

  Future<void> _editPhoto() async {
    if (saving || photoBase64.isEmpty) return;
    try {
      final edited = await showProfilePhotoEditor(
        context,
        base64Decode(photoBase64),
      );
      if (edited != null && mounted) setState(() => photoBase64 = edited);
    } catch (_) {
      if (mounted) setState(() => error = 'The photo could not be opened.');
    }
  }

  Future<void> _save() async {
    final value = LocalProfile(
      googleSubject: widget.profile.googleSubject,
      loginEmail: widget.profile.loginEmail,
      department: department.text.trim(),
      employeeReference: employeeReference.text.trim(),
      responsibility: responsibility,
      name: name.text.trim(),
      email: email.text.trim(),
      phone: phone.text.trim(),
      jobTitle: jobTitle.text.trim(),
      role: role,
      photoBase64: photoBase64,
    );
    if (value.name.isEmpty) {
      setState(() => error = 'Enter your name.');
      return;
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.email)) {
      setState(() => error = 'Enter a valid contact email.');
      return;
    }
    if (!LocalProfile.desktopRoles.contains(value.role)) {
      setState(() => error = 'Choose Director or Accountant.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await value.save();
      _LocalProfileMenuState._savedProfile.value = value;
      await widget.submitRegistration?.call(value);
      if (mounted) Navigator.of(context).pop(value);
    } on MembershipFailure catch (failure) {
      if (mounted) {
        setState(
          () => error =
              'Your profile is saved on this device. ${failure.toString()}',
        );
      }
    } on StateError catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } on ArgumentError {
      if (mounted) {
        setState(
          () => error = 'Check your name, contact email and requested role.',
        );
      }
    } on PlatformException catch (failure) {
      if (mounted) {
        setState(() => error = failure.message ?? 'Could not save profile.');
      }
    } on MissingPluginException {
      if (mounted) {
        setState(() => error = 'Local profile storage is unavailable.');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contentWidth = (MediaQuery.sizeOf(context).width - 128).clamp(
      0.0,
      AccountingPopoutTokens.normalContentWidth,
    );
    Widget field(String label, Widget control) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        accountingFieldLabel(
          context,
          label,
          alignToField: true,
          guidance: switch (label) {
            'Contact Email' => 'Contact email can be changed without changing your sign-in email.',
            'Requested Role' =>
              widget.submitRegistration == null
                  ? 'Role requests do not grant approval rights.'
                  : 'Role requests do not grant approval rights. Submit your name, contact email and requested role for business approval.',
            _ => null,
          },
        ),
        const SizedBox(height: 8),
        control,
      ],
    );
    Widget input(
      String label,
      String key,
      TextEditingController controller, {
      TextInputType? type,
      String? hint,
    }) => field(
      label,
      TextField(
        key: ValueKey(key),
        controller: controller,
        keyboardType: type,
        decoration: accountingSingleLineInputDecoration(
          context,
          hintText: hint,
        ),
      ),
    );
    return AccountingDialog.alert(
      context,
      widthFamily: AccountingPopoutWidthFamily.normal,
      title: widget.setup ? 'Profile Setup' : 'Profile',
      formFooter: true,
      description: widget.setup
          ? 'Check your details and complete your accounting profile.'
          : 'Your contact details and accounting responsibilities.',
      maxContentWidth: AccountingPopoutTokens.normalContentWidth,
      content: SizedBox(
        width: contentWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _EditableProfileAvatar(
                  photoBase64: photoBase64,
                  onEdit: saving || photoBase64.isEmpty ? null : _editPhoto,
                ),
                AccountingButton.outline(
                  context,
                  key: const ValueKey('profile-choose-photo'),
                  onPressed: saving ? null : _choosePhoto,
                  child: Text(
                    photoBase64.isEmpty ? 'Choose Photo' : 'Change Photo',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            AccountingOrdinaryFields(
              fields: [
                AccountingOrdinaryFieldSlot(
                  label: 'Name',
                  contentSample: 'Fictional Customer',
                  hasGuidance: true,
                  minimumRowFraction: .5,
                  builder: (_) => input('Name', 'profile-name', name),
                ),
                AccountingOrdinaryFieldSlot(
                  label: 'Contact Email',
                  contentSample: 'demo@example.test',
                  hasGuidance: true,
                  minimumRowFraction: .5,
                  builder: (_) => input(
                    'Contact Email',
                    'profile-email',
                    email,
                    type: TextInputType.emailAddress,
                  ),
                ),
                AccountingOrdinaryFieldSlot(
                  label: 'Work Phone',
                  contentSample: '+60 12 345 6789',
                  builder: (_) => input(
                    'Work Phone',
                    'profile-phone',
                    phone,
                    type: TextInputType.phone,
                  ),
                ),
                AccountingOrdinaryFieldSlot(
                  label: 'Job Title',
                  contentSample: 'Finance Manager',
                  builder: (_) => input(
                    'Job Title',
                    'profile-job-title',
                    jobTitle,
                    hint: 'For example, Finance Manager',
                  ),
                ),
                AccountingOrdinaryFieldSlot(
                  label: 'Department',
                  contentSample: '0000000000',
                  builder: (_) => input(
                    'Department',
                    'profile-department',
                    department,
                    hint: 'For example, Finance',
                  ),
                ),
                AccountingOrdinaryFieldSlot(
                  label: 'Employee Reference',
                  contentSample: '0000000000',
                  builder: (_) => input(
                    'Employee Reference',
                    'profile-employee-reference',
                    employeeReference,
                    hint: 'Optional staff reference',
                  ),
                ),
                AccountingOrdinaryFieldSlot(
                  label: 'Accounting Responsibility',
                  choices: [
                    if (responsibility.isEmpty) 'Select Responsibility',
                    ...LocalProfile.responsibilities,
                  ],
                  builder: (width) => field(
                    'Accounting Responsibility',
                    AccountingSelector<String>(
                      triggerKey: const ValueKey('profile-responsibility'),
                      assignedWidth: width,
                      value:
                          LocalProfile.responsibilities.contains(responsibility)
                          ? responsibility
                          : null,
                      hintText: 'Select Responsibility',
                      options: [
                        for (final option in LocalProfile.responsibilities)
                          AccountingSelectorOption(
                            value: option,
                            label: option,
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => responsibility = value ?? ''),
                    ),
                  ),
                ),
                AccountingOrdinaryFieldSlot(
                  label: 'Requested Role',
                  hasGuidance: true,
                  choices: [
                    if (role.isEmpty) 'Select Role',
                    ...LocalProfile.desktopRoles,
                  ],
                  builder: (width) => field(
                    'Requested Role',
                    AccountingSelector<String>(
                      triggerKey: const ValueKey('profile-role'),
                      assignedWidth: width,
                      value: LocalProfile.desktopRoles.contains(role)
                          ? role
                          : null,
                      hintText: 'Select Role',
                      options: [
                        for (final option in LocalProfile.desktopRoles)
                          AccountingSelectorOption(
                            value: option,
                            label: option,
                          ),
                      ],
                      onChanged: (value) => setState(() => role = value ?? ''),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (GoogleAccountSession.shared.hasPassword)
              AccountingButton.outline(
                context,
                key: const ValueKey('profile-change-password'),
                onPressed: saving
                    ? null
                    : () => showPasswordChange(
                        context,
                        GoogleAccountSession.shared,
                      ),
                child: const Text('Change Password'),
              )
            else if (GoogleAccountSession.shared.signedIn)
              AccountingButton.outline(
                context,
                key: const ValueKey('profile-google-password'),
                onPressed: saving
                    ? null
                    : () => GoogleAccountSession.credentials.invokeMethod<void>(
                        'manageGooglePassword',
                      ),
                child: const Text('Manage Google Password'),
              ),
            const SizedBox(height: 12),
            if (widget.approvalStatus != null)
              accountingHelperText(context, switch (widget.approvalStatus) {
                'approved' => 'Business access: Approved.',
                'pending' => 'Business access: Awaiting Director approval.',
                'rejected' => 'Business access: Registration rejected.',
                'revoked' => 'Business access: Access removed.',
                _ => 'Business access could not be confirmed.',
              }),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                style: TextStyle(
                  color: AccountingTheme.of(context).destructive,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        AccountingButton.ghost(
          context,
          key: const ValueKey('profile-cancel'),
          onPressed: saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        AccountingButton.primary(
          context,
          key: const ValueKey('profile-save'),
          onPressed: saving ? null : _save,
          child: Text(
            saving
                ? (widget.submitRegistration == null
                      ? 'Saving…'
                      : 'Submitting…')
                : widget.submitRegistration == null
                ? 'Save Profile'
                : 'Submit',
          ),
        ),
      ],
    );
  }
}

class _EditableProfileAvatar extends StatefulWidget {
  const _EditableProfileAvatar({
    required this.photoBase64,
    required this.onEdit,
  });
  final String photoBase64;
  final VoidCallback? onEdit;
  @override
  State<_EditableProfileAvatar> createState() => _EditableProfileAvatarState();
}

class _EditableProfileAvatarState extends State<_EditableProfileAvatar> {
  bool hover = false;
  bool focused = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => hover = true),
    onExit: (_) => setState(() => hover = false),
    child: Tooltip(
      message: 'Edit Image',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onEdit,
          customBorder: const CircleBorder(),
          onFocusChange: (value) => setState(() => focused = value),
          child: Semantics(
            button: true,
            label: 'Edit Image',
            child: SizedBox.square(
              dimension: 64,
              child: Stack(
                children: [
                  CircleAvatar(
                    key: const ValueKey('profile-photo-preview'),
                    radius: 32,
                    backgroundColor: AccountingTheme.of(context).primary,
                    backgroundImage: widget.photoBase64.isEmpty
                        ? null
                        : MemoryImage(base64Decode(widget.photoBase64)),
                    child: widget.photoBase64.isEmpty
                        ? const AccountingIcon(Icons.person_outline, size: 28)
                        : null,
                  ),
                  if (widget.onEdit != null && (hover || focused))
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Color(0x66000000),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: AccountingIcon(
                            Icons.edit_outlined,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
