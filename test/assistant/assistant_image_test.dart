import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:naboo/assistant/assistant_api_client.dart';
import 'package:naboo/assistant/assistant_tool_registry.dart';
import 'package:naboo/assistant/data/assistant_image.dart';
import 'package:naboo/assistant/ui/assistant_controller.dart';

import 'assistant_test_fakes.dart';

void main() {
  test('a big noisy photo is shrunk under 400 KB and stays a readable JPEG', () {
    final r = Random(1);
    final big = img.Image(width: 3000, height: 2200);
    for (final p in big) {
      p
        ..r = r.nextInt(256)
        ..g = r.nextInt(256)
        ..b = r.nextInt(256);
    }
    final raw = img.encodePng(big, level: 1);
    expect(raw.length, greaterThan(AssistantImage.maxBytes));
    final out = AssistantImage.compressSync(raw)!;
    expect(out.length, lessThanOrEqualTo(AssistantImage.maxBytes));
    final back = img.decodeJpg(out)!;
    expect(max(back.width, back.height), lessThanOrEqualTo(AssistantImage.maxSide));
    expect(AssistantImage.dataUrl(out), startsWith('data:image/jpeg;base64,'));
  });

  test('not an image gives null', () {
    expect(AssistantImage.compressSync(Uint8List.fromList([1, 2, 3])), isNull);
  });

  test('the photo goes with its question only, then history keeps a text marker', () async {
    final jpeg = AssistantImage.compressSync(img.encodePng(img.Image(width: 40, height: 40)))!;
    final seen = <Object?>[];
    final api = FakeApi((step, req) {
      final lastUser = req.messages.lastWhere((m) => m['role'] == 'user');
      seen.add(lastUser['content']);
      return const [AssistantTextEvent('هذا 5W-30'), AssistantDoneEvent(finish: 'stop')];
    });
    final c = AssistantController(
      registry: AssistantToolRegistry(tools: const []),
      toolContext: () => ctxFor(owner: true),
      api: api,
      isOnline: () async => true,
      v2Enabled: () => true,
    );
    // «هلا» يجيبه الموجّه المحلي عادةً؛ مع صورة يذهب للنموذج.
    await c.ask('', image: jpeg);
    expect(seen.single, isA<List<Object?>>());
    final parts = seen.single! as List;
    expect((parts.first as Map)['type'], 'image_url');
    expect((parts.last as Map)['text'], 'شنو هذا؟');
    expect(c.messages.first.image, isNotNull);
    final stored = c.historyForTest.firstWhere((m) => m['role'] == 'user')['content'];
    expect(stored, '[صورة] شنو هذا؟');
  });
}
