import 'package:flutter/material.dart';

import 'src/api/fake_admin_api.dart';
import 'src/api/http_admin_api.dart';
import 'src/app.dart';
import 'src/config.dart';

/// HabitQuest admin console (web). See admin/README.md.
void main() {
  final config = AdminConfig.fromEnvironment();
  runApp(
    config.demo
        ? AdminApp(
            api: FakeAdminApi.demo(),
            banner:
                'Demo mode: fake data. Sign in as admin@example.com '
                '(password "demo"); any other email shows "Not authorised".',
          )
        : AdminApp(api: HttpAdminApi(config)),
  );
}
