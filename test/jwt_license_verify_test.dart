import 'package:naboo/services/license/jwt_rs256_verifier.dart';
import 'package:naboo/services/license/license_engine_v2.dart';
import 'package:naboo/services/license/license_token.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sample admin JWT verifies with naboo-dev-001 public key', () {
    const jwt =
        'eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6Im5hYm9vLWRldi0wMDEifQ.eyJ0ZW5hbnRfaWQiOiI5NzdhOTU1My0wNjllLTRmYTEtYWVmOS1lNDVmYmMzMTNlYjQiLCJwbGFuIjoicHJvIiwibWF4X2RldmljZXMiOjMsInN0YXJ0c19hdCI6IjIwMjYtMDUtMDFUMDM6NTE6NDAuMzQ3WiIsImVuZHNfYXQiOiIyMDI2LTA1LTMxVDAzOjUxOjQwLjM0N1oiLCJsaWNlbnNlX2lkIjoiMTEiLCJpc190cmlhbCI6ZmFsc2UsImlzc3VlZF9hdCI6IjIwMjYtMDUtMDFUMDM6NTE6NDAuNjMwWiJ9.cqNawTpX4EEvzqryDztNlYYkUYh5d2kU2UdLK4ukxiwKau5e8Zwv-NbdC_V1u6N7xwronM6IRH9QeQ1gaogVLSgohLPtSQFHRSUSs8R1tGD5JKssES4u9F-BY_3G8AiKzV8a5kK6ru0u29UeW8Kc2zSNU9Za_hHJJIU5yAQAGF-ZM43mUAAfcthpVLZexqInAhfPOvCu5tuSbSCg8jmObK8_iae-1yZEQvsvDHz_3wOk6JJcIgBFu5Kn4bNy7PzcY3ovDc8KD8PTC4NOn6EhLqHymo5KCvUgppc5HLXnn7stq40auk0ZLWiCPfU7iO1dtxPRCCDnsdDh8MdIDZ-pWA';

    final v = JwtRs256Verifier(
      trustedPublicKeysPemByKid: LicenseEngineV2.trustedPublicKeysPemByKid,
    );
    final result = v.verify(jwt);
    final tok = LicenseToken.fromJwt(
      header: result.header,
      claims: result.claims,
    );
    expect(tok.tenantId, isNotEmpty);
    expect(tok.isExpired, isFalse);
  });
}
