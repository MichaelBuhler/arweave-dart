import 'dart:convert';
import 'dart:core';
import 'dart:typed_data';

import 'package:arweave/src/crypto/hmac_drbg_secure_random.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:cryptography/cryptography.dart' hide SecureRandom;
import 'package:jwk/jwk.dart';
import 'package:pointycastle/export.dart';
import 'package:pointycastle/src/platform_check/platform_check.dart';

import '../crypto/crypto.dart';
import '../utils.dart';

class Wallet {
  RsaKeyPair? _keyPair;
  Wallet({KeyPair? keyPair}) : _keyPair = keyPair as RsaKeyPair?;

  static Wallet generateWallet(SecureRandom secureRandom) {
    final keyGen = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(
            publicExponent,
            keyLength,
            64,
          ),
          secureRandom,
        ),
      );

    final pair = keyGen.generateKeyPair();

    final privK = pair.privateKey as RSAPrivateKey;

    return Wallet(
      keyPair: RsaKeyPairData(
        e: encodeBigIntToBytes(privK.publicExponent!),
        n: encodeBigIntToBytes(privK.modulus!),
        d: encodeBigIntToBytes(privK.privateExponent!),
        p: encodeBigIntToBytes(privK.p!),
        q: encodeBigIntToBytes(privK.q!),
        dp: encodeBigIntToBytes(
            privK.privateExponent! % (privK.p! - BigInt.one)),
        dq: encodeBigIntToBytes(
            privK.privateExponent! % (privK.q! - BigInt.one)),
        qi: encodeBigIntToBytes(privK.q!.modInverse(privK.p!)),
      ),
    );
  }

  static Future<Wallet> generate() async {
    final FortunaRandom secureRandom = FortunaRandom()
      ..seed(
          KeyParameter(Platform.instance.platformEntropySource().getBytes(32)));

    return generateWallet(secureRandom);
  }

  static Future<Wallet> createWalletFromMnemonic(String mnemonic) async {
    final seed = bip39.mnemonicToSeed(mnemonic);
    final secureRandom = HmacDrbgSecureRandom();
    secureRandom.seed(KeyParameter(seed));

    return generateWallet(secureRandom);
  }

  Future<String> getOwner() async => encodeBytesToBase64(
      await _keyPair!.extractPublicKey().then((res) => res.n));

  Future<RsaPublicKey> getPublicKey() async =>
      await _keyPair!.extractPublicKey();

  Future<String> getAddress() async => ownerToAddress(await getOwner());

  Future<Uint8List> sign(Uint8List message) async =>
      rsaPssSign(message: message, keyPair: _keyPair!);

  factory Wallet.fromJwk(Map<String, dynamic> jwk) {
    // Normalize the JWK so that it can be decoded by 'cryptography'.
    jwk = jwk.map((key, value) {
      if (key == 'kty' || value is! String) {
        return MapEntry(key, value);
      } else {
        return MapEntry(key, base64Url.normalize(value));
      }
    });

    var privK = Jwk.fromJson(jwk).toKeyPair() as RsaKeyPairData;

    if (privK.dp == null ||
        privK.dp!.isEmpty ||
        privK.dq == null ||
        privK.dq!.isEmpty ||
        privK.qi == null ||
        privK.qi!.isEmpty) {
      final d = decodeBytesToBigInt(privK.d);
      final p = decodeBytesToBigInt(privK.p);
      final q = decodeBytesToBigInt(privK.q);

      jwk.addAll({
        'dp': base64.normalize(encodeBigIntToBase64(d % (p - BigInt.one))),
        'dq': base64.normalize(encodeBigIntToBase64(d % (q - BigInt.one))),
        'qi': base64.normalize(encodeBigIntToBase64(q.modInverse(p))),
      });

      privK = Jwk.fromJson(jwk).toKeyPair() as RsaKeyPairData;
    }

    return Wallet(keyPair: privK);
  }

  Map<String, dynamic> toJwk() => Jwk.fromKeyPair(_keyPair!).toJson().map(
      // Denormalize the JWK into the expected form.
      (key, value) => MapEntry(key, (value as String).replaceAll('=', '')));
}
