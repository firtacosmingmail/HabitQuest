// End-to-end Projects sync against a running Supabase stack (the real Edge
// Functions, not the fakes). Skipped unless configured, so `flutter test`
// stays offline. Run against the LOCAL stack (README "Sync"):
//
//   supabase start && supabase functions serve   # from the repo root
//   HQ_E2E_URL=http://127.0.0.1:54321 \
//   HQ_E2E_ANON_KEY=<local anon key from `supabase status`> \
//   HQ_E2E_SERVICE_KEY=<local service_role key from `supabase status`> \
//     flutter test test/e2e/projects_sync_e2e_test.dart
//
// The service key only creates two throwaway, pre-confirmed users through
// the local Auth admin API (email confirmation is on). Never point this at
// the live project with its service key.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/core/config/backend_config.dart';
import 'package:habit_quest/data/remote/api_transport.dart';
import 'package:habit_quest/data/remote/authenticated_transport.dart';
import 'package:habit_quest/data/remote/http_auth_api.dart';
import 'package:habit_quest/data/remote/http_habit_quest_api.dart';
import 'package:habit_quest/data/remote/remote_models.dart';
import 'package:habit_quest/features/game/game_rules.dart';
import 'package:habit_quest/features/projects/models/clock_time.dart';
import 'package:habit_quest/features/projects/models/consistent_action.dart';
import 'package:habit_quest/features/projects/models/session_mark.dart';
import 'package:habit_quest/features/sync/sync_engine.dart';
import 'package:http/http.dart' as http;

import '../features/sync/sync_harness.dart';

final _env = Platform.environment;
final _url = _env['HQ_E2E_URL'];
final _anon = _env['HQ_E2E_ANON_KEY'];
final _service = _env['HQ_E2E_SERVICE_KEY'];
final _skip = (_url == null || _anon == null || _service == null)
    ? 'set HQ_E2E_URL, HQ_E2E_ANON_KEY and HQ_E2E_SERVICE_KEY'
    : null;

class _Token implements AccessTokenProvider {
  final String token;
  _Token(this.token);
  @override
  Future<String?> accessToken() async => token;
  @override
  Future<String?> refreshAfterUnauthorized(String rejectedToken) async => null;
}

void main() {
  final client = http.Client();
  late BackendConfig config;

  Future<String> newUserToken(String tag) async {
    final email =
        'e2e-$tag-${DateTime.now().microsecondsSinceEpoch}@example.com';
    const password = 'e2e-password-123';
    final res = await client.post(
      Uri.parse('$_url/auth/v1/admin/users'),
      headers: {
        'apikey': _service!,
        'authorization': 'Bearer $_service',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'email': email,
        'password': password,
        'email_confirm': true,
      }),
    );
    expect(res.statusCode, 200, reason: res.body);
    final auth = HttpAuthApi(ApiTransport(config: config, client: client));
    final session = await auth.login(email: email, password: password);
    return session.accessToken;
  }

  HttpHabitQuestApi apiFor(String token) => HttpHabitQuestApi(
    AuthenticatedTransport(
      transport: ApiTransport(config: config, client: client),
      tokens: _Token(token),
    ),
  );

  setUpAll(() {
    if (_skip != null) return;
    config = BackendConfig(supabaseUrl: _url!, anonKey: _anon!);
  });
  tearDownAll(client.close);

  test('two devices, two accounts: push order, pull, LWW, soft delete, '
      'XP once, account switch', () async {
    final clock = TestClock()..now = DateTime.now();
    final day = DateTime(clock.now.year, clock.now.month, clock.now.day);
    final u1 = await newUserToken('u1');
    final u2 = await newUserToken('u2');
    final api1 = apiFor(u1);

    // Device A: a full tree, with a session attended today.
    final a = Device('A', clock: clock, api: api1);
    final p = await a.projects.createProject(name: 'E2E project');
    final t = await a.projects.createTarget(
      projectId: p.id,
      title: 'E2E target',
      deadline: day.add(const Duration(days: 30)),
    );
    final task = await a.projects.addPlanTask(targetId: t.id, title: 'Task');
    final action = await a.projects.createAction(
      targetId: t.id,
      startTime: const ClockTime(6, 0),
      endTime: const ClockTime(6, 30),
      recurrence: WeeklyRecurrence({1, 2, 3, 4, 5, 6, 7}),
      startDate: day,
    );
    await a.projects.setSessionAttended(action.id, day, true);
    await a.projects.setPlanTaskDone(task.id, true);
    await pumpEventQueue();
    final xp = a.xp;
    expect(xp, GameRules.planTaskXp + GameRules.sessionXp);

    var report = await a.sync(user: 'u1');
    expect(report.issues, isEmpty, reason: 'parents went out first');
    expect(a.queue.isEmpty, isTrue);
    final marks = await api1.listProjectRecords(ProjectResource.sessionMarks);
    expect(marks.items.single.id, SessionMark.keyFor(action.id, day));

    // Device B, same account: gets everything, XP once and silently.
    final b = Device('B', clock: clock, api: api1);
    report = await b.sync(user: 'u1');
    expect(report.pulledProjectRecords, 5);
    expect(b.projects.data.project(p.id)!.name, 'E2E project');
    expect(b.projects.data.isAttended(action.id, day), isTrue);
    expect(b.xp, xp);
    expect(b.gameEvents, isEmpty);
    expect(b.remoteProjectEvents, isNotEmpty);

    // LWW: A renames, then B renames later; both converge on B's name.
    clock.advance();
    await a.projects.renameProject(p.id, 'Older');
    clock.advance();
    await b.projects.renameProject(p.id, 'Newer');
    await b.sync(user: 'u1');
    await a.sync(user: 'u1');
    expect(a.projects.data.project(p.id)!.name, 'Newer');

    // Re-sync pulls nothing new (cursor), XP unchanged.
    expect((await b.sync(user: 'u1')).pulledProjectRecords, 0);
    expect(b.xp, xp);

    // Soft delete: A deletes the project; B sees it gone, tombstones stay.
    clock.advance();
    await a.projects.deleteProject(p.id);
    await a.sync(user: 'u1');
    await b.sync(user: 'u1');
    expect(b.projects.data.projects, isEmpty);
    final serverProjects = await api1.listProjectRecords(
      ProjectResource.projects,
    );
    expect(serverProjects.items.single.isDeleted, isTrue);
    final serverTargets = await api1.listProjectRecords(
      ProjectResource.targets,
    );
    expect(serverTargets.items.single.isDeleted, isTrue);

    // Account switch: user 2 on device B never sees user 1's projects.
    b.api = apiFor(u2);
    expect(await b.engine.prepareForUser('u2'), AccountChange.switched);
    await b.engine.sync('u2');
    expect(b.projectRepo.getAllProjectRecords(), isEmpty);
    final u2Projects = await apiFor(
      u2,
    ).listProjectRecords(ProjectResource.projects);
    expect(u2Projects.items, isEmpty);
  }, skip: _skip);
}
