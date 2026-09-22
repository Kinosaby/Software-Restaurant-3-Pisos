import 'package:flutter_test/flutter_test.dart';
import 'package:tres_pisos_app/local/local_app.dart';
import 'package:tres_pisos_app/local/pos_engine.dart';

void main() {
  test(
    'Pairing accepts only private addresses, expected port and complete keys',
    () {
      final key = randomKey(), id = randomKey();
      expect(
        parsePairing('trespisos://192.168.1.5:8787?key=$key&id=$id')
            .address
            .host,
        '192.168.1.5',
      );
      for (final host in [
        'example.com',
        '8.8.8.8',
        '127.0.0.1',
        '169.254.169.254',
        '172.32.1.1',
      ]) {
        expect(
          () => parsePairing('trespisos://$host:8787?key=$key&id=$id'),
          throwsA(isA<PosError>()),
        );
      }
      expect(
        () => parsePairing('trespisos://10.0.0.2:80?key=$key&id=$id'),
        throwsA(isA<PosError>()),
      );
      expect(
        () => parsePairing('trespisos://10.0.0.2:8787?key=short&id=$id'),
        throwsA(isA<PosError>()),
      );
    },
  );
}
