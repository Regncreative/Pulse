import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_protocol/pulse_wire.dart';

void main() {
  test('Ping envelope roundtrip', () {
    final env = Envelope(
      requestId: 7,
      body: Ping(nonce: 3, unixMs: 100),
    );
    final bytes = encodeEnvelope(env);
    final decoded = decodeEnvelope(bytes);
    expect(decoded.requestId, 7);
    expect(decoded.body, isA<Ping>());
    expect((decoded.body! as Ping).nonce, 3);
  });

  test('frame roundtrip', () {
    final payload = encodeEnvelope(Envelope(requestId: 1, body: Ping(nonce: 1)));
    final frame = encodeFrame(payload);
    final decoded = tryDecodeFrame(frame)!;
    expect(decoded.payload, payload);
  });
}
