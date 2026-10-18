import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'admin_api.dart';
import 'api_exception.dart';
import 'models.dart';

/// [AdminApi] over the Supabase Edge Functions (see supabase/API.md).
///
/// Sends `apikey: <anon key>` on every request and
/// `Authorization: Bearer <accessToken>` on the authenticated ones. The
/// session lives in memory only: reloading the page signs out. An expired
/// access token is refreshed once through `auth-refresh`.
class HttpAdminApi implements AdminApi {
  final AdminConfig config;
  final http.Client client;
  AdminSession? _session;

  HttpAdminApi(this.config, {http.Client? client})
    : client = client ?? http.Client();

  AdminSession? get session => _session;

  Future<Map<String, dynamic>?> _send(
    String method,
    String function, {
    List<String> path = const [],
    Map<String, String>? query,
    Object? body,
    bool auth = true,
    bool retried = false,
  }) async {
    final s = _session;
    if (auth && s == null) {
      throw const ApiException(
        status: 401,
        code: ApiException.unauthorized,
        message: 'Not signed in',
      );
    }
    final req = http.Request(
      method,
      config.function(function, path: path, query: query),
    );
    req.headers['apikey'] = config.anonKey;
    if (auth) req.headers['authorization'] = 'Bearer ${s!.accessToken}';
    if (body != null) {
      req.headers['content-type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    http.Response res;
    try {
      res = await http.Response.fromStream(await client.send(req));
    } catch (e) {
      throw ApiException(
        code: ApiException.networkError,
        message: 'Could not reach the server ($e)',
      );
    }
    if (res.statusCode == 401 && auth && !retried && await _refresh()) {
      return _send(
        method,
        function,
        path: path,
        query: query,
        body: body,
        auth: auth,
        retried: true,
      );
    }
    Object? json;
    if (res.body.trim().isNotEmpty) {
      try {
        json = jsonDecode(res.body);
      } catch (_) {
        json = null;
      }
    }
    if (res.statusCode >= 400) {
      final err = json is Map ? json['error'] : null;
      throw ApiException(
        status: res.statusCode,
        code: err is Map ? '${err['code']}' : ApiException.badResponse,
        message: err is Map ? '${err['message']}' : 'HTTP ${res.statusCode}',
      );
    }
    if (json == null) return null;
    if (json is! Map) {
      throw ApiException(
        status: res.statusCode,
        code: ApiException.badResponse,
        message: 'Unexpected response',
      );
    }
    return json.cast<String, dynamic>();
  }

  Future<bool> _refresh() async {
    final s = _session;
    if (s == null) return false;
    try {
      final j = await _send(
        'POST',
        'auth-refresh',
        body: {'refreshToken': s.refreshToken},
        auth: false,
      );
      _session = AdminSession.fromJson(
        (j!['session'] as Map).cast<String, dynamic>(),
      );
      return true;
    } on ApiException {
      _session = null;
      return false;
    }
  }

  @override
  Future<AdminSession> signIn(String email, String password) async {
    final j = await _send(
      'POST',
      'auth-login',
      body: {'email': email.trim(), 'password': password},
      auth: false,
    );
    final session = j?['session'];
    if (session is! Map) {
      throw const ApiException(
        code: ApiException.badResponse,
        message: 'No session returned',
      );
    }
    return _session = AdminSession.fromJson(session.cast<String, dynamic>());
  }

  @override
  Future<void> checkAdmin() async {
    await _send('GET', 'admin-stats', path: ['me']);
  }

  @override
  Future<void> signOut() async {
    if (_session != null) {
      try {
        await _send('POST', 'auth-logout', retried: true);
      } on ApiException {
        // Best effort: the session is dropped locally anyway.
      }
    }
    _session = null;
  }

  @override
  Future<QuotePage> listQuotes(QuoteQuery query) async => QuotePage.fromJson(
    (await _send('GET', 'admin-quotes', query: query.toParams()))!,
  );

  @override
  Future<AdminQuote> createQuote(QuoteDraft draft) async {
    final j = await _send('POST', 'quotes', body: draft.toJson());
    return AdminQuote.fromJson((j!['quote'] as Map).cast<String, dynamic>());
  }

  @override
  Future<AdminQuote> updateQuote(String id, QuoteDraft draft) async {
    final j = await _send(
      'PUT',
      'quotes',
      query: {'id': id},
      body: draft.toJson(),
    );
    return AdminQuote.fromJson((j!['quote'] as Map).cast<String, dynamic>());
  }

  @override
  Future<void> deleteQuote(String id) async {
    await _send('DELETE', 'admin-quotes', query: {'id': id});
  }

  @override
  Future<AdminStats> stats({required String from, required String to}) async =>
      AdminStats.fromJson(
        (await _send('GET', 'admin-stats', query: {'from': from, 'to': to}))!,
      );
}
