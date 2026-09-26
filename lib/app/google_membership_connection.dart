import 'dart:async';

import 'package:flutter/widgets.dart';

import 'connected_user_directory.dart';
import 'google_account_session.dart';
import 'membership_service.dart';

/// Opt-in composition for a provisioned business endpoint. Own alongside the
/// company workspace, never create from a profile's role or contact email.
class GoogleMembershipConnection extends ChangeNotifier
    with WidgetsBindingObserver {
  GoogleMembershipConnection({
    required this.origin,
    required this.businessId,
    GoogleAccountSession? google,
    this.transportFactory,
    this.refreshInterval = const Duration(minutes: 1),
  }) : google = google ?? GoogleAccountSession.shared {
    this.google.addListener(_sync);
    _sync();
    WidgetsBinding.instance.addObserver(this);
    if (refreshInterval > Duration.zero) {
      _poll = Timer.periodic(refreshInterval, (_) => _refreshIfActive());
    }
  }
  final Uri origin;
  final String businessId;
  final GoogleAccountSession google;
  final MembershipTransport Function()? transportFactory;
  String? _accountId;
  ConnectedUserDirectory? directory;
  bool _disposed = false;
  bool _active = true;
  final Duration refreshInterval;
  Timer? _poll;
  bool _submitting = false;
  MembershipRegistration? _pendingRegistration;
  String? get approvalStatus => directory?.membership?.status;
  bool get hasUnconfirmedRegistration => _pendingRegistration != null;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active) _refreshIfActive();
  }

  void _refreshIfActive() {
    if (!_disposed &&
        _active &&
        !google.busy &&
        !_submitting &&
        directory != null &&
        !directory!.loading) {
      unawaited(directory!.refresh());
    }
  }

  Future<void> submitProfile({
    required String googleSubject,
    required String name,
    required String email,
    required String requestedRole,
  }) async {
    final current = directory;
    if (_disposed ||
        current == null ||
        googleSubject != _accountId ||
        googleSubject != google.identityId) {
      throw const MembershipFailure('session_changed');
    }
    if (_submitting) throw StateError('Wait for the current submission.');
    final candidate = MembershipRegistration(
      businessId: businessId,
      name: name,
      email: email,
      requestedRole: requestedRole,
    );
    final prior = _pendingRegistration;
    if (prior != null && prior.profileBody != candidate.profileBody) {
      throw StateError(
        'The previous submission is unconfirmed. Retry its original details first.',
      );
    }
    final registration = prior ?? candidate;
    _submitting = true;
    try {
      await current.service.register(registration);
      if (_disposed || directory != current) {
        throw const MembershipFailure('session_changed');
      }
      _pendingRegistration = null;
      notifyListeners();
      await current.refresh();
    } on MembershipFailure catch (failure) {
      if (!_disposed && directory == current) {
        _pendingRegistration =
            const [
              'service_unavailable',
              'invalid_response',
            ].contains(failure.code)
            ? registration
            : null;
        notifyListeners();
      }
      rethrow;
    } finally {
      _submitting = false;
    }
  }

  void _sync() {
    if (_disposed) return;
    final id = google.error == null ? google.identityId : null;
    if (id != _accountId) {
      directory?.removeListener(_changed);
      directory?.dispose();
      directory = null;
      _pendingRegistration = null;
      _accountId = id;
      if (id != null) {
        directory = ConnectedUserDirectory(
          MembershipService(
            origin: origin,
            businessId: businessId,
            tokenProvider: () => google.idTokenForAccount(id),
            transport: transportFactory?.call(),
          ),
        );
        directory!.addListener(_changed);
      }
      notifyListeners();
    }
    _refreshIfActive();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _pendingRegistration = null;
    WidgetsBinding.instance.removeObserver(this);
    google.removeListener(_sync);
    directory?.removeListener(_changed);
    directory?.dispose();
    directory = null;
    super.dispose();
  }
}
