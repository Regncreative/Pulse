import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_protocol/pulse_wire.dart';

/// Documents the reserved handshake request id contract used by PulseIpcClient.
void main() {
  test('ClientHello / ServerHello roundtrip preserves request id 1', () {
    const handshakeId = 1;
    final hello = Envelope(
      requestId: handshakeId,
      body: ClientHello(
        protocolVersion: 1,
        clientName: 'Pulse',
        clientVersion: '1.0.0',
      ),
    );
    final encoded = encodeEnvelope(hello);
    final decoded = decodeEnvelope(encoded);
    expect(decoded.requestId, handshakeId);
    expect(decoded.body, isA<ClientHello>());

    final server = Envelope(
      requestId: handshakeId,
      body: ServerHello(protocolVersion: 1, serviceVersion: '1.0.0'),
    );
    final serverDecoded = decodeEnvelope(encodeEnvelope(server));
    expect(serverDecoded.requestId, handshakeId);
    expect(serverDecoded.body, isA<ServerHello>());
  });

  test('GetTimelineSnapshot uses a separate request id from handshake', () {
    // Must match PulseIpcClient: handshake id=1, UI RPCs start at 1000.
    const handshakeId = 1;
    const snapshotId = 1000;
    expect(snapshotId, isNot(handshakeId));

    final snapReq = Envelope(
      requestId: snapshotId,
      body: GetTimelineSnapshot(limit: 100, channel: 'System'),
    );
    final snapReply = Envelope(
      requestId: snapshotId,
      body: TimelineSnapshot(
        channel: 'System',
        requestedLimit: 100,
        collectedUnixMs: 1,
        events: [],
      ),
    );
    expect(decodeEnvelope(encodeEnvelope(snapReq)).requestId, snapshotId);
    expect(
      decodeEnvelope(encodeEnvelope(snapReply)).body,
      isA<TimelineSnapshot>(),
    );
  });
}
