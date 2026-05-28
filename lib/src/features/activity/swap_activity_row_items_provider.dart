import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../swap/providers/swap_activity_store.dart';
import 'swap_activity_row_mapper.dart';

final swapActivityRowItemsProvider =
    FutureProvider.family<List<SwapActivityRowItem>, String>((
      ref,
      accountUuid,
    ) async {
      final records = await ref.watch(
        swapActivityRecordsProvider(accountUuid).future,
      );
      return swapActivityRowItemsFromRecords(records);
    });
