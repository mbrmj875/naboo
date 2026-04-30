import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';

class JwtVerificationResult {
  const JwtVerificationResult({
    required this.header,
    required this.claims,
  });

  final Map<String, dynamic> header;
  final Map<String, dynamic> claims;
}

class JwtRs256Verifier {
  JwtRs256Verifier({required Map<String, String> trustedPublicKeysPemByKid})
    : _trustedPublicKeysPemByKid = trustedPublicKeysPemByKid;

  final Map<String, String> _trustedPublicKeysPemByKid;

  JwtVerificationResult verify(String jwt) {
    final parts = jwt.split('.');
    if (parts.length != 3) {
      throw const FormatException('invalid jwt format');
    }
    final headerJson = _b64UrlJson(parts[0]);
    final claimsJson = _b64UrlJson(parts[1]);
    final signature = _b64UrlDecode(parts[2]);

    final header = _asMap(headerJson);
    final claims = _asMap(claimsJson);

    final alg = (header['alg'] ?? '').toString();
    if (alg != 'RS256') {
      throw FormatException('unsupported alg: $alg');
    }

    final kid = (header['kid'] ?? '').toString().trim();
    if (kid.isEmpty) {
      throw const FormatException('missing kid');
    }
    final pem = _trustedPublicKeysPemByKid[kid];
    if (pem == null || pem.trim().isEmpty) {
      throw FormatException('unknown kid: $kid');
    }
    final publicKey = CryptoUtils.rsaPublicKeyFromPem(pem);

    final signingInput = utf8.encode('${parts[0]}.${parts[1]}');
    final signer = Signer('SHA-256/RSA');
    signer.init(false, PublicKeyParameter<RSAPublicKey>(publicKey));
    final ok = signer.verifySignature(
      Uint8List.fromList(signingInput),
      RSASignature(signature),
    );
    if (!ok) {
      throw const FormatException('invalid signature');
    }

    return JwtVerificationResult(header: header, claims: claims);
  }

  Map<String, dynamic> _asMap(Object? o) {
    if (o is Map<String, dynamic>) return o;
    if (o is Map) return Map<String, dynamic>.from(o);
    throw const FormatException('invalid json object');
  }

  Object _b64UrlJson(String s) => jsonDecode(utf8.decode(_b64UrlDecode(s)));

  Uint8List _b64UrlDecode(String input) {
    var s = input.replaceAll('-', '+').replaceAll('_', '/');
    while (s.length % 4 != 0) {
      s += '=';
    }
    return base64Decode(s);
  }
}

