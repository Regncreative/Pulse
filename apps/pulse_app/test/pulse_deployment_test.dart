import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/platform/pulse_deployment.dart';

void main() {
  test('FixedPulseDeployment reports packaged flag', () {
    expect(
      const FixedPulseDeployment(isPackagedMsix: true).isPackagedMsix,
      isTrue,
    );
    expect(
      const FixedPulseDeployment(isPackagedMsix: false).isPackagedMsix,
      isFalse,
    );
  });
}
