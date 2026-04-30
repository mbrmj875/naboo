import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:naboo/services/license/jwt_rs256_verifier.dart';
import 'package:naboo/services/license/license_token.dart';

String _b64UrlEncode(Uint8List bytes) {
  return base64UrlEncode(bytes).replaceAll('=', '');
}

String _jwtSignRs256({
  required RSAPrivateKey privateKey,
  required Map<String, dynamic> header,
  required Map<String, dynamic> claims,
}) {
  final headerB64 = _b64UrlEncode(Uint8List.fromList(utf8.encode(jsonEncode(header))));
  final claimsB64 = _b64UrlEncode(Uint8List.fromList(utf8.encode(jsonEncode(claims))));
  final signingInput = '$headerB64.$claimsB64';

  final signer = Signer('SHA-256/RSA');
  signer.init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));
  final sig = signer.generateSignature(Uint8List.fromList(utf8.encode(signingInput)));
  final sigBytes = (sig as RSASignature).bytes;
  final sigB64 = _b64UrlEncode(Uint8List.fromList(sigBytes));
  return '$signingInput.$sigB64';
}

void main() {
  test('RS256 verifier validates signature and parses claims', () {
    final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    final publicKey = pair.publicKey as RSAPublicKey;
    final privateKey = pair.privateKey as RSAPrivateKey;

    const kid = 'naboo-test-001';
    final verifier = JwtRs256Verifier(
      trustedPublicKeysPemByKid: {
        kid: CryptoUtils.encodeRSAPublicKeyToPem(publicKey),
      },
    );

    final now = DateTime.now().toUtc();
    final header = {'alg': 'RS256', 'typ': 'JWT', 'kid': kid};
    final claims = {
      'tenant_id': 't1',
      'plan': 'basic',
      'max_devices': 2,
      'starts_at': now.toIso8601String(),
      'ends_at': now.add(const Duration(days: 30)).toIso8601String(),
      'license_id': 'lic-1',
      'is_trial': false,
      'issued_at': now.toIso8601String(),
    };

    final jwt = _jwtSignRs256(
      privateKey: privateKey,
      header: header,
      claims: claims,
    );

    final verified = verifier.verify(jwt);
    final token = LicenseToken.fromJwt(
      header: verified.header,
      claims: verified.claims,
    );

    expect(token.kid, kid);
    expect(token.tenantId, 't1');
    expect(token.plan, 'basic');
    expect(token.maxDevices, 2);
    expect(token.licenseId, 'lic-1');
    expect(token.isTrial, false);
    expect(token.isExpired, false);
  });

  test('RS256 verifier rejects wrong kid', () {
    final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    final publicKey = pair.publicKey as RSAPublicKey;
    final privateKey = pair.privateKey as RSAPrivateKey;

    final verifier = JwtRs256Verifier(
      trustedPublicKeysPemByKid: {
        'naboo-test-001': CryptoUtils.encodeRSAPublicKeyToPem(publicKey),
      },
    );

    final now = DateTime.now().toUtc();
    final jwt = _jwtSignRs256(
      privateKey: privateKey,
      header: {'alg': 'RS256', 'typ': 'JWT', 'kid': 'unknown-kid'},
      claims: {
        'tenant_id': 't1',
        'plan': 'basic',
        'max_devices': 2,
        'starts_at': now.toIso8601String(),
        'ends_at': now.add(const Duration(days: 30)).toIso8601String(),
        'license_id': 'lic-1',
        'is_trial': false,
        'issued_at': now.toIso8601String(),
      },
    );

    expect(() => verifier.verify(jwt), throwsFormatException);
  });
}

