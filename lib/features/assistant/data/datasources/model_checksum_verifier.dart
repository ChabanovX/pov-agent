import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

/// Computes a digest for a candidate model file.
// Hashing is injectable so repository tests can control verification races.
// ignore: one_member_abstracts
abstract interface class ModelChecksumVerifier {
  /// Returns the lowercase SHA-256 digest for [filePath].
  Future<String> sha256ForFile(String filePath);
}

/// Streams model bytes through SHA-256 on a background isolate.
final class IsolateModelChecksumVerifier implements ModelChecksumVerifier {
  /// Creates the production checksum verifier.
  const IsolateModelChecksumVerifier();

  @override
  Future<String> sha256ForFile(String filePath) {
    return Isolate.run(() => _sha256ForFile(filePath));
  }
}

Future<String> _sha256ForFile(String filePath) async {
  final digest = await sha256.bind(File(filePath).openRead()).first;
  return digest.toString();
}
