// يشغّل rpc_push_snapshot الحقيقية على Postgres محلي معزول عبر psql.
// العنوان ثابت على 127.0.0.1 حتى لا يصل هذا الكود إلى خادم حقيقي أبداً.

import 'dart:convert';
import 'dart:io';

import 'multi_device_fleet.dart';

class LocalPgCloud implements SnapshotCloud {
  LocalPgCloud(this.port, this.psql, this.dir);

  final int port;
  final String psql;
  final Directory dir;
  static const userId = '11111111-1111-1111-1111-111111111111';
  var _fileSeq = 0;

  /// استجابة تُسقط مرة واحدة بعد نجاح الحفظ، كأن الشبكة انقطعت قبل الرد.
  bool dropNextResponse = false;
  int conflicts = 0;
  int committedPushes = 0;

  /// يُستدعى قبل كل رفع، ليكتب جهاز آخر في اللحظة نفسها.
  Future<void> Function()? beforePush;

  Future<String> sql(String statement) async {
    final file = File('${dir.path}/q${_fileSeq++}.sql');
    await file.writeAsString(
      "\\set ON_ERROR_STOP on\n\\o /dev/null\n"
      "SELECT set_config('request.jwt.claim.sub', '$userId', false);\n"
      "\\o\n$statement\n",
    );
    final r = await Process.run(psql, [
      '-h', '127.0.0.1', '-p', '$port', '-U', 'postgres', '-At', '-q',
      '-f', file.path,
    ]);
    await file.delete();
    if (r.exitCode != 0) throw StateError(r.stderr.toString());
    return r.stdout.toString().trim();
  }

  Future<void> resetSchema(String schemaFile) async {
    final r = await Process.run(psql, [
      '-h', '127.0.0.1', '-p', '$port', '-U', 'postgres', '-q',
      '-v', 'ON_ERROR_STOP=1', '-f', schemaFile,
    ]);
    if (r.exitCode != 0) throw StateError(r.stderr.toString());
    await sql("INSERT INTO auth.users VALUES ('$userId');");
  }

  /// استدعاء مباشر للدالة كما يفعل PostgREST: يعيد الرد أو الخطأ نصاً.
  Future<Map<String, dynamic>> rawPush({
    required int expected,
    required String payloadJson,
    required String key,
  }) async {
    try {
      final out = await sql(
        "SELECT public.rpc_push_snapshot($expected, \$pl\$$payloadJson\$pl\$::jsonb, "
        "1, 'test', '$key');",
      );
      return jsonDecode(out) as Map<String, dynamic>;
    } on StateError catch (e) {
      return {'ok': false, 'error': e.message};
    }
  }

  @override
  Future<Map<String, dynamic>> pushSnapshot({
    required int expectedVersion,
    required Map<String, dynamic> incoming,
    required String idempotencyKey,
  }) async {
    final hook = beforePush;
    if (hook != null) await hook();
    final res = await rawPush(
      expected: expectedVersion,
      payloadJson: jsonEncode(incoming),
      key: idempotencyKey,
    );
    if (res['reason'] == 'version_conflict') conflicts++;
    if (res['ok'] == true && res['idempotent'] != true) committedPushes++;
    if (res.containsKey('error')) throw StateError(res['error'].toString());
    if (dropNextResponse) {
      dropNextResponse = false;
      throw const SocketException('response lost after commit');
    }
    return res;
  }

  @override
  Future<int> currentVersion() async {
    final out = await sql(
      'SELECT coalesce(max(content_version), 0) FROM public.app_snapshots;',
    );
    return int.parse(out);
  }

  @override
  Future<Map<String, dynamic>?> currentPayload() async {
    final out = await sql('SELECT payload FROM public.app_snapshots;');
    if (out.isEmpty) return null;
    return jsonDecode(out) as Map<String, dynamic>;
  }
}
