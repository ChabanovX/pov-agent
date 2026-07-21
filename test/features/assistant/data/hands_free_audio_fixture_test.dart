import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixturePath = 'assets/audio/hands_free_question_en_us.pcm';
const _fixtureByteCount = 188954;
const _fixtureSha256 = '022256446f20bcd100316d1b892d7cb4bd9ce785ab6eac6ee74836ea60c69c52';

void main() {
  test('hands-free PCM fixture remains byte-for-byte reproducible', () async {
    final bytes = await File(_fixturePath).readAsBytes();

    expect(bytes, hasLength(_fixtureByteCount));
    expect(bytes.length.isEven, isTrue);
    expect(sha256.convert(bytes).toString(), _fixtureSha256);
  });
}
