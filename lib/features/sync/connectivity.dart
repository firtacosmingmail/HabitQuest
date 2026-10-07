import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// "Can we reach the backend right now?", behind an interface so tests use
/// [FakeConnectivityMonitor].
abstract interface class ConnectivityMonitor {
  /// A fresh check (network interface up *and* backend reachable).
  Future<bool> isOnline();

  /// Emits the new state whenever the network interface changes.
  Stream<bool> get changes;

  void dispose();
}

/// [ConnectivityMonitor] on connectivity_plus, plus a cheap reachability
/// probe: any HTTP response from [probeUri] (even an error status) counts as
/// reachable; a socket error or a timeout does not.
///
/// On web the probe is skipped (a cross-origin probe can fail on CORS while
/// the API itself works); a sync that hits a network error then simply
/// reports "offline" and backs off.
class PlusConnectivityMonitor implements ConnectivityMonitor {
  final Connectivity _connectivity;
  final http.Client _client;
  final Uri? probeUri;
  final Map<String, String> probeHeaders;
  final Duration probeTimeout;

  PlusConnectivityMonitor({
    required http.Client client,
    this.probeUri,
    this.probeHeaders = const {},
    this.probeTimeout = const Duration(seconds: 5),
    Connectivity? connectivity,
  }) : _client = client,
       _connectivity = connectivity ?? Connectivity();

  static bool _hasNetwork(List<ConnectivityResult> r) =>
      r.any((c) => c != ConnectivityResult.none);

  @override
  Future<bool> isOnline() async {
    try {
      if (!_hasNetwork(await _connectivity.checkConnectivity())) return false;
    } on Object {
      // Plugin unavailable: fall through to the probe.
    }
    return _probe();
  }

  Future<bool> _probe() async {
    final uri = probeUri;
    if (uri == null || kIsWeb) return true;
    try {
      await _client.get(uri, headers: probeHeaders).timeout(probeTimeout);
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Stream<bool> get changes => _connectivity.onConnectivityChanged.asyncMap(
    (r) async => _hasNetwork(r) && await _probe(),
  );

  @override
  void dispose() {}
}

/// Test double: flip [online] to simulate losing / regaining the network.
class FakeConnectivityMonitor implements ConnectivityMonitor {
  FakeConnectivityMonitor({bool online = true}) : _online = online;

  bool _online;
  final _changes = StreamController<bool>.broadcast(sync: true);

  bool get online => _online;

  set online(bool value) {
    if (value == _online) return;
    _online = value;
    _changes.add(value);
  }

  @override
  Future<bool> isOnline() async => _online;

  @override
  Stream<bool> get changes => _changes.stream;

  @override
  void dispose() => _changes.close();
}
