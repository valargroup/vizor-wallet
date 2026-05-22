import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_address_scan_payload.dart';

void main() {
  group('normalizeSwapAddressScanPayload', () {
    test('keeps raw addresses', () {
      expect(normalizeSwapAddressScanPayload('  rowan.near  '), 'rowan.near');
    });

    test('extracts recipient from ethereum receive URI', () {
      expect(
        normalizeSwapAddressScanPayload(
          'ethereum:0x157D19957d4047Fb8601783805a54EF6ae80eaD7',
        ),
        '0x157D19957d4047Fb8601783805a54EF6ae80eaD7',
      );
    });

    test('drops ethereum chain id suffix', () {
      expect(
        normalizeSwapAddressScanPayload(
          'ethereum:0x157D19957d4047Fb8601783805a54EF6ae80eaD7@8453',
        ),
        '0x157D19957d4047Fb8601783805a54EF6ae80eaD7',
      );
    });

    test('extracts ERC-681 transfer recipient instead of token contract', () {
      expect(
        normalizeSwapAddressScanPayload(
          'ethereum:0x1111111111111111111111111111111111111111@1'
          '/transfer?address=0x157D19957d4047Fb8601783805a54EF6ae80eaD7'
          '&uint256=1000000',
        ),
        '0x157D19957d4047Fb8601783805a54EF6ae80eaD7',
      );
    });

    test('extracts address from zcash ZIP-321 URI', () {
      expect(
        normalizeSwapAddressScanPayload(
          'zcash:u1k8h8x9g7f6e5d4c3b2a1?amount=0.01&message=hello',
        ),
        'u1k8h8x9g7f6e5d4c3b2a1',
      );
    });

    test('leaves unsupported schemes unchanged', () {
      expect(
        normalizeSwapAddressScanPayload('wc:abc@2?relay-protocol=irn'),
        'wc:abc@2?relay-protocol=irn',
      );
    });
  });
}
