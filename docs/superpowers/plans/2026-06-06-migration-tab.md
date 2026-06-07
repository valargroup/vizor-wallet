# Migration tab (Orchard → Ironwood showcase) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an always-visible "Migration" sidebar tab that showcases an Orchard→Ironwood pool migration by building three tiny Keystone-signed self-sends (PR 72's batch pipeline), broadcasting all three at once, then presenting a persistent simulated "transferring over 24 hours" state.

**Architecture:** A new `lib/src/features/migration/` feature. Pure, testable units (persisted demo-state model, schedule builder, batch-result verification, formatters, store) are TDD'd first. UI mirrors existing Keystone patterns: a self-contained signing overlay (modeled on `KeystoneShieldSigningOverlay`), a batch-result scan screen (modeled on `KeystoneSendScanScreen`), and a tab screen with idle / software-only / in-progress / complete states. The branch is based on PR 72's commit so the FRB batch bindings exist (cannot be regenerated locally); PR 72's throwaway debug screen is removed.

**Tech Stack:** Flutter, Riverpod, go_router, flutter_rust_bridge (consumed only), Vizor design system (`context.colors`, `AppTypography`, `AppButton`, `AppDesktopShell`).

**Reference spec:** `docs/superpowers/specs/2026-06-06-migration-tab-design.md`

---

## File structure

New files (all under `lib/src/features/migration/`):
- `models/migration_demo_state.dart` — persisted demo-state model + JSON + time-derived getters.
- `models/migration_schedule.dart` — `buildMigrationDemoState(...)` pure builder (injectable clock + RNG).
- `models/migration_batch.dart` — `MigrationBatchError`, `verifyDistinctNotes`, `verifySignResult` pure helpers.
- `migration_formatters.dart` — pure string formatters for remaining/started/eta.
- `migration_copy.dart` — centralized user-facing strings.
- `services/migration_demo_store.dart` — persistence via `AppSecureStore`.
- `providers/migration_demo_provider.dart` — `AsyncNotifier` exposing the active account's demo state + `startDemo`/`reset`.
- `widgets/migration_completion_dialog.dart` — the completion popup.
- `widgets/migration_signing_overlay.dart` — batch prepare → sign modal → scan → broadcast → persist.
- `screens/migration_scan_screen.dart` — scans `zcash-sign-result`, returns raw CBOR.
- `screens/migration_screen.dart` — the tab; renders the four states + hosts the overlay.

New tests (under `test/features/migration/`):
- `migration_demo_state_test.dart`, `migration_schedule_test.dart`, `migration_batch_test.dart`, `migration_formatters_test.dart`, `migration_demo_store_test.dart`, `migration_demo_provider_test.dart`, `migration_screen_test.dart`.

Modified files:
- `lib/app.dart` — add `/migration` + `/migration/scan` routes; remove PR 72 debug route.
- `lib/src/core/layout/app_main_sidebar.dart` — add the "Migration" item; remove PR 72 debug item.
- Delete `lib/src/features/debug/keystone_batch_debug_screen.dart`.

---

## Task 0: Branch setup + apply PR base strategy

**Files:** (git only)

- [ ] **Step 1: Create the feature branch off PR 72's commit and carry the spec over**

`adam/keystone-batch-sim` is checked out in another worktree, so branch from its commit hash (`87b8f4e1`). The spec (`849b5188`) and plan (`3f47327e`) commits currently sit on this worktree's branch; cherry-pick both onto the new branch.

```bash
cd /Users/czar/Documents/chainapsis/vizor-wallet/.claude/worktrees/inspiring-raman-bc078b
# Capture the doc commits (spec + plan + .gitignore) before switching base.
git checkout -b adam/migration-tab 87b8f4e1
git cherry-pick f4f78f03..adam/inspiring-raman-bc078b
```
Expected: new branch `adam/migration-tab` at PR 72's tree, plus clean cherry-picks adding `docs/superpowers/specs/...`, `docs/superpowers/plans/...`, and the `.gitignore` line (the range is every doc commit this worktree's branch added on top of `main` at `f4f78f03`). If `.gitignore` conflicts, keep both hunks and `git cherry-pick --continue`.

- [ ] **Step 2: Remove PR 72's debug-only UI (keep the Rust/binding machinery)**

```bash
git rm lib/src/features/debug/keystone_batch_debug_screen.dart
```

- [ ] **Step 3: Revert the debug-only wiring in `app.dart`**

In `lib/app.dart`, delete the import line:
```dart
import 'src/features/debug/keystone_batch_debug_screen.dart';
```
and delete the debug route block (right after the `/home` route):
```dart
      if (kDebugMode)
        GoRoute(
          path: '/debug/keystone-batch',
          builder: (_, _) => const KeystoneBatchDebugScreen(),
        ),
```
If `kDebugMode` / the `flutter/foundation.dart` import is now unused in `app.dart`, leave it only if still referenced elsewhere; otherwise remove that import too.

- [ ] **Step 4: Revert the debug-only sidebar item in `app_main_sidebar.dart`**

In `lib/src/core/layout/app_main_sidebar.dart`, delete the `if (kDebugMode) ...[ AppSidebarItem(label: 'Keystone batch', ...) ]` block, and the `import 'package:flutter/foundation.dart' show kDebugMode;` line (added by PR 72) — unless `kDebugMode` is used elsewhere in that file (it is not, in PR 72's version).

- [ ] **Step 5: Verify it still analyzes, then commit**

Run: `fvm flutter analyze lib/app.dart lib/src/core/layout/app_main_sidebar.dart`
Expected: No issues (no dangling references to the deleted screen).

```bash
git add -A
git commit -m "chore: base migration feature on batch machinery; drop PR72 debug screen"
```

---

## Task 1: `MigrationDemoState` model

**Files:**
- Create: `lib/src/features/migration/models/migration_demo_state.dart`
- Test: `test/features/migration/migration_demo_state_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vizor/src/features/migration/models/migration_demo_state.dart';

void main() {
  // 24h window; transfer offsets at 0, 4h, 15h.
  const fourH = 4 * 60 * 60 * 1000;
  const fifteenH = 15 * 60 * 60 * 1000;
  final state = MigrationDemoState(
    accountUuid: 'acc-1',
    startedAtEpochMs: 1_000_000,
    totalDurationMs: MigrationDemoState.defaultDurationMs,
    displayAmountZatoshi: BigInt.from(123450000),
    transferOffsetsMs: const [0, fourH, fifteenH],
    txids: const ['tx1', 'tx2', 'tx3'],
  );

  DateTime at(int offsetMs) =>
      DateTime.fromMillisecondsSinceEpoch(1_000_000 + offsetMs);

  test('json round-trips including BigInt amount', () {
    final decoded = MigrationDemoState.decode(state.encode());
    expect(decoded.accountUuid, 'acc-1');
    expect(decoded.displayAmountZatoshi, BigInt.from(123450000));
    expect(decoded.transferOffsetsMs, const [0, fourH, fifteenH]);
    expect(decoded.txids, const ['tx1', 'tx2', 'tx3']);
  });

  test('progress and remaining derive from now', () {
    expect(state.progressFraction(at(0)), 0.0);
    expect(state.isComplete(at(0)), isFalse);
    final mid = MigrationDemoState.defaultDurationMs ~/ 2;
    expect(state.progressFraction(at(mid)), closeTo(0.5, 0.001));
    expect(state.isComplete(at(MigrationDemoState.defaultDurationMs)), isTrue);
    expect(state.progressFraction(at(MigrationDemoState.defaultDurationMs * 2)),
        1.0);
  });

  test('transfersSent flips per offset; eta counts down', () {
    expect(state.transfersSent(at(0)), const [true, false, false]);
    expect(state.transfersSent(at(fourH)), const [true, true, false]);
    expect(state.transfersSent(at(fifteenH)), const [true, true, true]);
    expect(state.transferEta(1, at(0)).inHours, 4);
    expect(state.transferEta(1, at(fourH)), Duration.zero);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/migration/migration_demo_state_test.dart`
Expected: FAIL — `Target of URI doesn't exist` / undefined `MigrationDemoState`.

- [ ] **Step 3: Write the implementation**

```dart
import 'dart:convert';

/// Persisted, time-derived state for the (faked) Orchard→Ironwood migration.
///
/// The migration is theater: all three transfers are broadcast immediately.
/// Everything time-based here is computed from [startedAtEpochMs] against a
/// caller-supplied `now`, so it stays pure and testable.
class MigrationDemoState {
  const MigrationDemoState({
    required this.accountUuid,
    required this.startedAtEpochMs,
    required this.totalDurationMs,
    required this.displayAmountZatoshi,
    required this.transferOffsetsMs,
    required this.txids,
  });

  final String accountUuid;
  final int startedAtEpochMs;
  final int totalDurationMs;
  final BigInt displayAmountZatoshi;

  /// Per-transfer "fires at" offsets from start (ms), ascending, first == 0.
  final List<int> transferOffsetsMs;
  final List<String> txids;

  static const int defaultDurationMs = 24 * 60 * 60 * 1000;
  static const int transferCount = 3;

  int _rawElapsed(DateTime now) => now.millisecondsSinceEpoch - startedAtEpochMs;

  int elapsedMs(DateTime now) =>
      _rawElapsed(now).clamp(0, totalDurationMs);

  double progressFraction(DateTime now) =>
      totalDurationMs == 0 ? 1.0 : elapsedMs(now) / totalDurationMs;

  Duration remaining(DateTime now) =>
      Duration(milliseconds: totalDurationMs - elapsedMs(now));

  Duration sinceStart(DateTime now) =>
      Duration(milliseconds: elapsedMs(now));

  bool isComplete(DateTime now) => _rawElapsed(now) >= totalDurationMs;

  List<bool> transfersSent(DateTime now) {
    final elapsed = _rawElapsed(now);
    return [for (final o in transferOffsetsMs) elapsed >= o];
  }

  Duration transferEta(int index, DateTime now) {
    final delta = transferOffsetsMs[index] - _rawElapsed(now);
    return Duration(milliseconds: delta < 0 ? 0 : delta);
  }

  Map<String, dynamic> toJson() => {
        'accountUuid': accountUuid,
        'startedAtEpochMs': startedAtEpochMs,
        'totalDurationMs': totalDurationMs,
        'displayAmountZatoshi': displayAmountZatoshi.toString(),
        'transferOffsetsMs': transferOffsetsMs,
        'txids': txids,
      };

  static MigrationDemoState fromJson(Map<String, dynamic> json) =>
      MigrationDemoState(
        accountUuid: json['accountUuid'] as String,
        startedAtEpochMs: json['startedAtEpochMs'] as int,
        totalDurationMs: json['totalDurationMs'] as int,
        displayAmountZatoshi:
            BigInt.parse(json['displayAmountZatoshi'] as String),
        transferOffsetsMs:
            (json['transferOffsetsMs'] as List).map((e) => e as int).toList(),
        txids: (json['txids'] as List).map((e) => e as String).toList(),
      );

  String encode() => jsonEncode(toJson());

  static MigrationDemoState decode(String raw) =>
      fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
```

> Note: the test imports `package:vizor/...`. Confirm the package name in `pubspec.yaml` (`name:`) and use it consistently in all test imports. If it differs, substitute it everywhere.

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/features/migration/migration_demo_state_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/migration/models/migration_demo_state.dart test/features/migration/migration_demo_state_test.dart
git commit -m "feat(migration): add MigrationDemoState model"
```

---

## Task 2: `buildMigrationDemoState` schedule builder

**Files:**
- Create: `lib/src/features/migration/models/migration_schedule.dart`
- Test: `test/features/migration/migration_schedule_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:vizor/src/features/migration/models/migration_demo_state.dart';
import 'package:vizor/src/features/migration/models/migration_schedule.dart';

void main() {
  test('builds a staggered, ascending schedule with first transfer at 0', () {
    final now = DateTime.fromMillisecondsSinceEpoch(5_000_000);
    final state = buildMigrationDemoState(
      accountUuid: 'acc-1',
      displayAmountZatoshi: BigInt.from(42),
      txids: const ['a', 'b', 'c'],
      now: now,
      random: Random(7),
    );

    expect(state.accountUuid, 'acc-1');
    expect(state.startedAtEpochMs, 5_000_000);
    expect(state.totalDurationMs, MigrationDemoState.defaultDurationMs);
    expect(state.transferOffsetsMs.length, 3);
    expect(state.transferOffsetsMs.first, 0);
    // Ascending and within the window.
    final sorted = [...state.transferOffsetsMs]..sort();
    expect(state.transferOffsetsMs, sorted);
    expect(state.transferOffsetsMs.last,
        lessThan(MigrationDemoState.defaultDurationMs));
    // Transfers 2 and 3 are staggered (not both at 0).
    expect(state.transferOffsetsMs[1], greaterThan(0));
  });

  test('is deterministic for a fixed seed', () {
    final now = DateTime.fromMillisecondsSinceEpoch(0);
    final a = buildMigrationDemoState(
        accountUuid: 'x', displayAmountZatoshi: BigInt.one, txids: const [],
        now: now, random: Random(1));
    final b = buildMigrationDemoState(
        accountUuid: 'x', displayAmountZatoshi: BigInt.one, txids: const [],
        now: now, random: Random(1));
    expect(a.transferOffsetsMs, b.transferOffsetsMs);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/migration/migration_schedule_test.dart`
Expected: FAIL — undefined `buildMigrationDemoState`.

- [ ] **Step 3: Write the implementation**

```dart
import 'dart:math';

import 'migration_demo_state.dart';

/// Builds a believable, staggered transfer schedule for the migration demo.
///
/// Transfer 1 "fires" immediately (offset 0); transfers 2 and 3 fire at random
/// points inside the window so the in-progress UI looks naturally spaced.
/// [now] and [random] are injected for deterministic tests.
MigrationDemoState buildMigrationDemoState({
  required String accountUuid,
  required BigInt displayAmountZatoshi,
  required List<String> txids,
  required DateTime now,
  required Random random,
  int totalDurationMs = MigrationDemoState.defaultDurationMs,
}) {
  final second = _randomInRange(
    random,
    (totalDurationMs * 0.15).round(),
    (totalDurationMs * 0.55).round(),
  );
  final third = _randomInRange(
    random,
    (totalDurationMs * 0.55).round(),
    (totalDurationMs * 0.92).round(),
  );
  final offsets = <int>[0, second, third]..sort();

  return MigrationDemoState(
    accountUuid: accountUuid,
    startedAtEpochMs: now.millisecondsSinceEpoch,
    totalDurationMs: totalDurationMs,
    displayAmountZatoshi: displayAmountZatoshi,
    transferOffsetsMs: offsets,
    txids: txids,
  );
}

int _randomInRange(Random random, int minMs, int maxMs) {
  final span = (maxMs - minMs).clamp(1, 1 << 31);
  return minMs + random.nextInt(span);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/features/migration/migration_schedule_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/migration/models/migration_schedule.dart test/features/migration/migration_schedule_test.dart
git commit -m "feat(migration): add demo schedule builder"
```

---

## Task 3: Batch verification helpers

**Files:**
- Create: `lib/src/features/migration/models/migration_batch.dart`
- Test: `test/features/migration/migration_batch_test.dart`

These wrap the only two pieces of batch logic that can fail in pure Dart: distinct-note reservation and sign-result matching. They consume PR 72's binding types `ReservedPcztBatchItem` (`rust/api/sync.dart`) and `ZcashBatchSignResult` / `ZcashBatchSignedMessage` (`rust/wallet/keystone.dart`).

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:vizor/src/features/migration/models/migration_batch.dart';
import 'package:vizor/src/rust/api/sync.dart' show ReservedPcztBatchItem;
import 'package:vizor/src/rust/wallet/keystone.dart'
    show ZcashBatchSignResult, ZcashBatchSignedMessage;

ReservedPcztBatchItem item(String id, List<String> nfs) => ReservedPcztBatchItem(
      id: id,
      pcztWithProofs: Uint8List(0),
      redactedPczt: Uint8List(0),
      feeZatoshi: BigInt.zero,
      spendNullifiers: nfs,
    );

ZcashBatchSignedMessage signed(String id) => ZcashBatchSignedMessage(
      id: id, status: 1, kind: 1, signedPcztBytes: Uint8List(0),
      payloadDigestHex: '');

void main() {
  test('verifyDistinctNotes passes when all notes are unique', () {
    expect(
      () => verifyDistinctNotes([
        item('tx-1', const ['orchard:aa']),
        item('tx-2', const ['orchard:bb']),
        item('tx-3', const ['orchard:cc']),
      ]),
      returnsNormally,
    );
  });

  test('verifyDistinctNotes throws on a shared note', () {
    expect(
      () => verifyDistinctNotes([
        item('tx-1', const ['orchard:aa']),
        item('tx-2', const ['orchard:aa']),
      ]),
      throwsA(isA<MigrationBatchError>()),
    );
  });

  test('verifySignResult accepts a matching result', () {
    final result = ZcashBatchSignResult(
      version: 1, requestId: 'req-1',
      results: [signed('tx-1'), signed('tx-2'), signed('tx-3')]);
    expect(
      () => verifySignResult(result, 'req-1', {'tx-1', 'tx-2', 'tx-3'}),
      returnsNormally,
    );
  });

  test('verifySignResult rejects wrong request id and mismatched ids', () {
    final wrongReq = ZcashBatchSignResult(
      version: 1, requestId: 'other', results: [signed('tx-1')]);
    expect(() => verifySignResult(wrongReq, 'req-1', {'tx-1'}),
        throwsA(isA<MigrationBatchError>()));
    final wrongIds = ZcashBatchSignResult(
      version: 1, requestId: 'req-1', results: [signed('tx-1'), signed('tx-9')]);
    expect(() => verifySignResult(wrongIds, 'req-1', {'tx-1', 'tx-2'}),
        throwsA(isA<MigrationBatchError>()));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/migration/migration_batch_test.dart`
Expected: FAIL — undefined `MigrationBatchError` / `verifyDistinctNotes`.

- [ ] **Step 3: Write the implementation**

```dart
import '../../../rust/api/sync.dart' show ReservedPcztBatchItem;
import '../../../rust/wallet/keystone.dart' show ZcashBatchSignResult;

/// User-facing error for the migration batch flow. Its [message] is safe to
/// show directly.
class MigrationBatchError implements Exception {
  MigrationBatchError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Throws if any two batch items reserve the same shielded note, which would
/// make the batch invalid. Mirrors PR 72's collision guard.
void verifyDistinctNotes(List<ReservedPcztBatchItem> items) {
  final owners = <String, String>{};
  for (final item in items) {
    for (final nullifier in item.spendNullifiers) {
      if (owners.containsKey(nullifier)) {
        throw MigrationBatchError(
          'This demo needs at least 3 spendable notes. Receive a few '
          'payments, let Vizor sync, then try again.',
        );
      }
      owners[nullifier] = item.id;
    }
  }
}

/// Throws if the scanned sign-result does not correspond to the batch we sent.
void verifySignResult(
  ZcashBatchSignResult result,
  String expectedRequestId,
  Set<String> expectedIds,
) {
  if (result.requestId != expectedRequestId) {
    throw MigrationBatchError('Scanned result is for a different request.');
  }
  final ids = result.results.map((m) => m.id).toSet();
  if (result.results.length != expectedIds.length ||
      !ids.containsAll(expectedIds)) {
    throw MigrationBatchError('Scanned result does not match this migration.');
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/features/migration/migration_batch_test.dart`
Expected: PASS (4 tests). If a binding constructor signature differs (field names/order), adjust the test helpers to match `rust/api/sync.dart` / `rust/wallet/keystone.dart` exactly — do not change the binding files.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/migration/models/migration_batch.dart test/features/migration/migration_batch_test.dart
git commit -m "feat(migration): add batch verification helpers"
```

---

## Task 4: Migration formatters

**Files:**
- Create: `lib/src/features/migration/migration_formatters.dart`
- Test: `test/features/migration/migration_formatters_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vizor/src/features/migration/migration_formatters.dart';

void main() {
  test('formatRemaining', () {
    expect(formatRemaining(const Duration(hours: 16)),
        'About 16 hours remaining');
    expect(formatRemaining(const Duration(hours: 1)), 'About 1 hour remaining');
    expect(formatRemaining(const Duration(minutes: 40)),
        'About 40 minutes remaining');
    expect(formatRemaining(Duration.zero), 'Wrapping up');
  });

  test('formatStartedAgo', () {
    expect(formatStartedAgo(const Duration(hours: 8)), 'started 8h ago');
    expect(formatStartedAgo(const Duration(minutes: 5)), 'started 5m ago');
    expect(formatStartedAgo(const Duration(seconds: 10)), 'started just now');
  });

  test('formatTransferEta', () {
    expect(formatTransferEta(const Duration(hours: 4)), '~4h');
    expect(formatTransferEta(const Duration(minutes: 30)), '~30m');
    expect(formatTransferEta(Duration.zero), 'Soon');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/migration/migration_formatters_test.dart`
Expected: FAIL — undefined functions.

- [ ] **Step 3: Write the implementation**

```dart
String formatRemaining(Duration remaining) {
  if (remaining.inMinutes <= 0) return 'Wrapping up';
  if (remaining.inHours >= 1) {
    final h = remaining.inHours;
    return 'About $h hour${h == 1 ? '' : 's'} remaining';
  }
  final m = remaining.inMinutes;
  return 'About $m minute${m == 1 ? '' : 's'} remaining';
}

String formatStartedAgo(Duration sinceStart) {
  if (sinceStart.inMinutes < 1) return 'started just now';
  if (sinceStart.inHours >= 1) return 'started ${sinceStart.inHours}h ago';
  return 'started ${sinceStart.inMinutes}m ago';
}

String formatTransferEta(Duration eta) {
  if (eta.inMinutes <= 0) return 'Soon';
  if (eta.inHours >= 1) return '~${eta.inHours}h';
  return '~${eta.inMinutes}m';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/features/migration/migration_formatters_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/migration/migration_formatters.dart test/features/migration/migration_formatters_test.dart
git commit -m "feat(migration): add demo formatters"
```

---

## Task 5: `MigrationDemoStore` persistence

**Files:**
- Create: `lib/src/features/migration/services/migration_demo_store.dart`
- Test: `test/features/migration/migration_demo_store_test.dart`

- [ ] **Step 1: Write the failing test**

Uses an in-memory fake of the `flutter_secure_storage` interface via `AppSecureStore.testing`.

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vizor/src/core/storage/app_secure_store.dart';
import 'package:vizor/src/features/migration/models/migration_demo_state.dart';
import 'package:vizor/src/features/migration/services/migration_demo_store.dart';

class _MemStorage implements FlutterSecureStorage {
  final Map<String, String> _m = {};
  @override
  Future<String?> read({required String key, /* options */ dynamic iOptions,
      dynamic aOptions, dynamic lOptions, dynamic mOptions, dynamic wOptions,
      dynamic webOptions}) async => _m[key];
  @override
  Future<void> write({required String key, required String? value,
      dynamic iOptions, dynamic aOptions, dynamic lOptions, dynamic mOptions,
      dynamic wOptions, dynamic webOptions}) async {
    if (value == null) { _m.remove(key); } else { _m[key] = value; }
  }
  @override
  Future<void> delete({required String key, dynamic iOptions, dynamic aOptions,
      dynamic lOptions, dynamic mOptions, dynamic wOptions,
      dynamic webOptions}) async => _m.remove(key);
  @override
  Future<Map<String, String>> readAll({dynamic iOptions, dynamic aOptions,
      dynamic lOptions, dynamic mOptions, dynamic wOptions,
      dynamic webOptions}) async => Map.of(_m);
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late MigrationDemoStore store;
  setUp(() {
    final secure = AppSecureStore.testing(storage: _MemStorage());
    store = MigrationDemoStore(store: secure);
  });

  MigrationDemoState sample(String acc) => MigrationDemoState(
        accountUuid: acc, startedAtEpochMs: 1, totalDurationMs: 10,
        displayAmountZatoshi: BigInt.from(99),
        transferOffsetsMs: const [0, 4, 7], txids: const ['a']);

  test('read returns null before any write', () async {
    expect(await store.read('acc-1'), isNull);
  });

  test('write then read round-trips, scoped per account', () async {
    await store.write(sample('acc-1'));
    final got = await store.read('acc-1');
    expect(got, isNotNull);
    expect(got!.displayAmountZatoshi, BigInt.from(99));
    expect(await store.read('acc-2'), isNull);
  });

  test('clear removes the account entry', () async {
    await store.write(sample('acc-1'));
    await store.clear('acc-1');
    expect(await store.read('acc-1'), isNull);
  });
}
```

> If `_MemStorage`'s `implements` signature drifts from the installed `flutter_secure_storage` version, simplify by extending and overriding only `read`/`write`/`delete`/`readAll`, leaving `noSuchMethod` for the rest. Confirm the version in `pubspec.lock`.

- [ ] **Step 2: Run test to verify it fails**

Run: `fvm flutter test test/features/migration/migration_demo_store_test.dart`
Expected: FAIL — undefined `MigrationDemoStore`.

- [ ] **Step 3: Write the implementation**

```dart
import '../../../core/storage/app_secure_store.dart';
import '../models/migration_demo_state.dart';

/// Persists the migration demo state per account in plain (non-secret) storage.
class MigrationDemoStore {
  MigrationDemoStore({AppSecureStore? store})
      : _store = store ?? AppSecureStore.instance;

  final AppSecureStore _store;

  static const _prefix = 'vizor_migration_demo_state_';
  static String _key(String accountUuid) => '$_prefix$accountUuid';

  Future<MigrationDemoState?> read(String accountUuid) async {
    final raw = await _store.readPlain(_key(accountUuid));
    if (raw == null || raw.isEmpty) return null;
    try {
      return MigrationDemoState.decode(raw);
    } catch (_) {
      await clear(accountUuid);
      return null;
    }
  }

  Future<void> write(MigrationDemoState state) =>
      _store.writePlain(_key(state.accountUuid), state.encode());

  Future<void> clear(String accountUuid) =>
      _store.deletePlainKeysWithPrefix(_key(accountUuid));
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `fvm flutter test test/features/migration/migration_demo_store_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/migration/services/migration_demo_store.dart test/features/migration/migration_demo_store_test.dart
git commit -m "feat(migration): add demo-state persistence store"
```

---

## Task 6: `migrationDemoProvider`

**Files:**
- Create: `lib/src/features/migration/providers/migration_demo_provider.dart`
- Test: `test/features/migration/migration_demo_provider_test.dart`

The provider exposes the active account's demo state and the `startDemo`/`reset` mutations. It watches `accountProvider` for the active account UUID.

- [ ] **Step 1: Confirm the accessor used to read the active account UUID**

Run: `grep -n "activeAccountUuid" lib/src/providers/account_provider.dart | head -3`
Expected: an `activeAccountUuid` getter on the account state (as used in `app_main_sidebar.dart` via `accountAsync.value?.activeAccountUuid`). Use that exact path.

- [ ] **Step 2: Write the implementation**

```dart
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/account_provider.dart';
import '../models/migration_demo_state.dart';
import '../models/migration_schedule.dart';
import '../services/migration_demo_store.dart';

final migrationDemoProvider =
    AsyncNotifierProvider<MigrationDemoNotifier, MigrationDemoState?>(
  MigrationDemoNotifier.new,
);

class MigrationDemoNotifier extends AsyncNotifier<MigrationDemoState?> {
  final MigrationDemoStore _store = MigrationDemoStore();

  @override
  Future<MigrationDemoState?> build() async {
    final accountUuid = ref.watch(accountProvider).value?.activeAccountUuid;
    if (accountUuid == null) return null;
    return _store.read(accountUuid);
  }

  /// Records that a migration just started (all txs already broadcast).
  Future<void> startDemo({
    required BigInt displayAmountZatoshi,
    required List<String> txids,
  }) async {
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    if (accountUuid == null) return;
    final demo = buildMigrationDemoState(
      accountUuid: accountUuid,
      displayAmountZatoshi: displayAmountZatoshi,
      txids: txids,
      now: DateTime.now(),
      random: Random(),
    );
    await _store.write(demo);
    state = AsyncData(demo);
  }

  /// Clears the demo so the tab returns to its idle/landing state.
  Future<void> reset() async {
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    if (accountUuid != null) {
      await _store.clear(accountUuid);
    }
    state = const AsyncData(null);
  }
}
```

- [ ] **Step 3: Write a light test (build returns null without an account)**

This avoids heavy account/sync fakes; it asserts the safe default. Deeper behavior is covered by the store/model tests and manual verification.

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vizor/src/features/migration/providers/migration_demo_provider.dart';

void main() {
  test('provider yields null when there is no active account', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final value = await container.read(migrationDemoProvider.future);
    expect(value, isNull);
  });
}
```

> If `accountProvider`'s default build in a bare `ProviderContainer` throws (e.g. it touches platform storage), override it in the test with a minimal stub that exposes `activeAccountUuid == null`, following the pattern in `test/providers/account_provider_test.dart`. Inspect that file first and reuse its setup.

- [ ] **Step 4: Run test**

Run: `fvm flutter test test/features/migration/migration_demo_provider_test.dart`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/migration/providers/migration_demo_provider.dart test/features/migration/migration_demo_provider_test.dart
git commit -m "feat(migration): add migrationDemoProvider"
```

---

## Task 7: Migration copy constants

**Files:**
- Create: `lib/src/features/migration/migration_copy.dart`

Centralizes user-facing strings (sentence case per AGENTS.md). No test (constants only); they are asserted indirectly by the widget test in Task 11.

- [ ] **Step 1: Write the implementation**

```dart
/// User-facing copy for the migration showcase. Sentence case per AGENTS.md.
abstract final class MigrationCopy {
  static const tabLabel = 'Migration';

  // Idle / landing
  static const idleTitle = 'Migration';
  static const idleBody =
      "Move your shielded ZEC to Ironwood, Zcash's next-generation shielded "
      'pool. Your Keystone approves the whole migration in one signature.';
  static const fromPoolName = 'Orchard';
  static const fromPoolTag = 'Current pool';
  static const toPoolName = 'Ironwood';
  static const toPoolTag = 'New pool';
  static const readyToMigrateLabel = 'Ready to migrate';
  static const poolFlow = 'Orchard pool → Ironwood pool';
  static const bullet1 = 'Funds move in small batches over random intervals.';
  static const bullet2 = 'Migration can take up to 24 hours to finish.';
  static const bullet3 = 'Keep Vizor open until it completes.';
  static const startCta = 'Start migration';

  // Software-account (no Keystone) state
  static const keystoneRequiredTitle = 'Migration';
  static const keystoneRequiredBody =
      'Migration is available for Keystone accounts. Switch to or add a '
      'Keystone account to try it.';

  // Signing
  static const signTitle = 'Approve your migration';
  static const signSubtitle = 'Scan this code with your Keystone';
  static const signInstruction =
      'Your Keystone signs all 3 transfers in one step. Approve on the device, '
      'then scan the result.';
  static const signPrimary = 'Scan signed result';
  static const signCancel = 'Cancel';
  static const broadcastingTitle = 'Broadcasting migration';
  static const broadcastingSubtitle = 'Sending your transfers';
  static const broadcastingInstruction =
      'Keep Vizor open while your transfers are sent.';
  static const signBack = 'Back';

  // Scan
  static const scanTitle = 'Scan the signed migration';
  static const scanBody =
      'Point your camera at the signed result QR on your Keystone.';
  static const scanDecodingLabel = 'Reading signed migration...';
  static const scanUnavailable =
      'Scanning the signed migration uses camera QR scanning only. Connect a '
      'camera and try again.';

  // Completion popup
  static const completeTitle = 'Migration started';
  static const completeBody =
      'Your funds are on their way to the Ironwood pool. Transfers go out in '
      'small batches over random intervals across the next 24 hours.\n\n'
      'Keep Vizor open so the migration can finish.';
  static const completeButton = 'Got it';

  // In progress
  static const inProgressTitle = 'Migration in progress';
  static const inProgressBody =
      'Your funds are moving from Orchard to Ironwood. This finishes on its '
      'own — just keep Vizor open.';
  static String migratingAmount(String amount) => 'Migrating $amount';
  static String transferLabel(int index) => 'Transfer $index of 3';
  static const transferSent = 'Sent';
  static const keepOpenWarning =
      'Keep Vizor open. Closing the app pauses the remaining transfers until '
      'you reopen it.';
  static const resetCta = 'Reset demo';

  // Done
  static const doneTitle = 'Migration complete';
  static const doneBody =
      'Your funds have finished moving to the Ironwood pool.';
  static const doneButton = 'Done';

  // Errors
  static const genericError = 'Migration could not be started. Please try again.';
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/src/features/migration/migration_copy.dart
git commit -m "feat(migration): add centralized copy"
```

---

## Task 8: `MigrationScanScreen`

**Files:**
- Create: `lib/src/features/migration/screens/migration_scan_screen.dart`

Mirrors `lib/src/features/send/screens/keystone_send_scan_screen.dart`, but returns the **raw** `zcash-sign-result` CBOR (the batch decode happens in the overlay), not a decoded single PCZT.

- [ ] **Step 1: Write the implementation**

```dart
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../services/qr_scanner.dart';
import '../../keystone/widgets/keystone_qr_scanner_card.dart';
import '../migration_copy.dart';

class MigrationScanScreen extends ConsumerStatefulWidget {
  const MigrationScanScreen({super.key});

  @override
  ConsumerState<MigrationScanScreen> createState() =>
      _MigrationScanScreenState();
}

class _MigrationScanScreenState extends ConsumerState<MigrationScanScreen> {
  static const _signResultUrType = 'zcash-sign-result';

  bool _decoding = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
    });
  }

  void _handleComplete(ScanResult result) {
    if (_decoding) return;
    setState(() => _decoding = true);
    context.pop(Uint8List.fromList(result.data));
  }

  void _handleDecodeError(Object error) {
    if (!mounted || _decoding) return;
    final message = error.toString().contains('Unexpected UR type')
        ? 'Open the signed migration QR on Keystone, then scan again.'
        : 'Keep the QR code steady and fully visible.';
    if (_error == message) return;
    setState(() => _error = message);
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/migration');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppRouteBackLink(onTap: _goBack),
            const SizedBox(height: AppSpacing.s),
            Text(
              MigrationCopy.scanTitle,
              style: AppTypography.displaySmall.copyWith(
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              MigrationCopy.scanBody,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: Center(
                child: KeystoneQrScannerCard(
                  expectedUrType: _signResultUrType,
                  decoding: _decoding,
                  error: _error,
                  onComplete: _handleComplete,
                  onDecodeError: _handleDecodeError,
                  decodingLabel: MigrationCopy.scanDecodingLabel,
                  unavailableMessage: MigrationCopy.scanUnavailable,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify the `AppRouteBackLink` API matches**

Run: `grep -n "class AppRouteBackLink\|AppRouteBackLink({" lib/src/core/widgets/app_back_link.dart`
Expected: a widget that accepts an `onTap` (the shield/send screens use `const AppRouteBackLink()` with default back behavior). If it takes no `onTap`, use `const AppRouteBackLink()` and delete `_goBack`. Match the real signature.

- [ ] **Step 3: Verify the `KeystoneQrScannerCard` API matches**

Run: `grep -n "KeystoneQrScannerCard({" -A 14 lib/src/features/keystone/widgets/keystone_qr_scanner_card.dart`
Expected: named params `expectedUrType`, `decoding`, `error`, `onComplete`, `onDecodeError`, `decodingLabel`, `unavailableMessage` (PR 72's debug screen used these). If `onProgress` is required, add `onProgress: (_) {}`. Adjust to the real signature.

- [ ] **Step 4: Analyze**

Run: `fvm flutter analyze lib/src/features/migration/screens/migration_scan_screen.dart`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/migration/screens/migration_scan_screen.dart
git commit -m "feat(migration): add signed-result scan screen"
```

---

## Task 9: `MigrationSigningOverlay`

**Files:**
- Create: `lib/src/features/migration/widgets/migration_signing_overlay.dart`

Modeled on `lib/src/features/home/widgets/keystone_shield_signing_overlay.dart`, using the batch APIs. On a successful broadcast it records the demo via `migrationDemoProvider`, then calls `onComplete`.

- [ ] **Step 1: Write the implementation**

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/layout/app_layout.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../rust/api/sync.dart' as rust_sync;
import '../../../rust/wallet/keystone.dart';
import '../../keystone/widgets/keystone_signing_modal.dart';
import '../migration_copy.dart';
import '../models/migration_batch.dart';
import '../providers/migration_demo_provider.dart';

enum _MigrationSignPhase { preparing, ready, broadcasting, failed }

class MigrationSigningOverlay extends ConsumerStatefulWidget {
  const MigrationSigningOverlay({
    required this.onCancel,
    required this.onComplete,
    super.key,
  });

  final VoidCallback onCancel;
  final VoidCallback onComplete;

  @override
  ConsumerState<MigrationSigningOverlay> createState() =>
      _MigrationSigningOverlayState();
}

class _MigrationSigningOverlayState
    extends ConsumerState<MigrationSigningOverlay> {
  static const int _transferCount = 3;
  static const int _amountPerTransferZatoshi = 10000; // 0.0001 ZEC

  _MigrationSignPhase _phase = _MigrationSignPhase.preparing;
  String? _error;
  List<String> _urParts = const [];
  String? _requestId;
  List<ZcashBatchMessageInput> _messages = const [];
  Map<String, List<int>> _pcztsWithProofsById = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
      unawaited(_prepareBatch());
    });
  }

  Future<void> _prepareBatch() async {
    try {
      final accountState = ref.read(accountProvider).value;
      final account = accountState?.activeAccount;
      final accountUuid = accountState?.activeAccountUuid;
      final address = accountState?.activeAddress;
      if (account == null || accountUuid == null || address == null ||
          address.isEmpty) {
        throw MigrationBatchError('No active account.');
      }
      if (!account.isHardware) {
        throw MigrationBatchError('Migration requires a Keystone account.');
      }

      final dbPath = await getWalletDbPath();
      final endpoint = ref.read(rpcEndpointProvider);
      final requestId =
          'vizor-migration-${DateTime.now().millisecondsSinceEpoch}';

      final batchItems = await rust_sync.createReservedPcztBatch(
        dbPath: dbPath,
        network: endpoint.networkName,
        accountUuid: accountUuid,
        requests: [
          for (var i = 0; i < _transferCount; i++)
            rust_sync.ReservedPcztBatchRequest(
              id: 'tx-${i + 1}',
              sendFlowId: '$requestId-${i + 1}',
              toAddress: address,
              amountZatoshi: BigInt.from(_amountPerTransferZatoshi),
              memo: 'Ironwood migration ${i + 1}/$_transferCount',
            ),
        ],
      );

      if (batchItems.length != _transferCount) {
        throw MigrationBatchError(
          'This demo needs at least 3 spendable notes. Receive a few '
          'payments, let Vizor sync, then try again.',
        );
      }
      verifyDistinctNotes(batchItems);

      final messages = <ZcashBatchMessageInput>[];
      final proofsById = <String, List<int>>{};
      for (final item in batchItems) {
        proofsById[item.id] = item.pcztWithProofs;
        messages.add(
          ZcashBatchMessageInput(id: item.id, pcztBytes: item.redactedPczt),
        );
      }

      final urParts = await rust_keystone.encodeZcashSignBatchUrParts(
        requestId: requestId,
        messages: messages,
        maxFragmentLen: BigInt.from(200),
      );

      if (!mounted) return;
      setState(() {
        _phase = _MigrationSignPhase.ready;
        _requestId = requestId;
        _messages = messages;
        _pcztsWithProofsById = proofsById;
        _urParts = urParts;
      });
    } catch (e, st) {
      log('MigrationSigningOverlay._prepareBatch: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _phase = _MigrationSignPhase.failed;
        _error = _friendlyError(e);
      });
    }
  }

  Future<void> _getSignature() async {
    if (_phase != _MigrationSignPhase.ready) return;
    final cbor = await context.push<Uint8List>('/migration/scan');
    if (cbor == null || !mounted) return;
    await _broadcast(cbor);
  }

  Future<void> _broadcast(Uint8List cbor) async {
    setState(() {
      _phase = _MigrationSignPhase.broadcasting;
      _error = null;
    });
    try {
      final requestId = _requestId;
      if (requestId == null || _messages.isEmpty) {
        throw MigrationBatchError('Prepare the migration before broadcasting.');
      }

      final result = await rust_keystone.decodeZcashSignResultCbor(cbor: cbor);
      verifySignResult(
        result,
        requestId,
        _messages.map((m) => m.id).toSet(),
      );

      final dbPath = await getWalletDbPath();
      final endpoint = ref.read(rpcEndpointProvider);
      final txids = <String>[];
      for (final signed in result.results) {
        final proofs = _pcztsWithProofsById[signed.id];
        if (proofs == null) {
          throw MigrationBatchError('Missing proof data for ${signed.id}.');
        }
        final broadcast = await rust_sync.extractAndBroadcastPczt(
          dbPath: dbPath,
          lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
          network: endpoint.networkName,
          pcztWithProofsBytes: proofs,
          pcztWithSignaturesBytes: signed.signedPcztBytes,
        );
        if (broadcast.status != 'broadcasted') {
          throw MigrationBatchError(
            'A transfer could not be broadcast (${broadcast.status}).',
          );
        }
        txids.add(broadcast.txid);
      }

      final orchardBalance =
          ref.read(syncProvider).value?.orchardBalance ?? BigInt.zero;
      await ref.read(migrationDemoProvider.notifier).startDemo(
            displayAmountZatoshi: orchardBalance,
            txids: txids,
          );

      try {
        await ref.read(syncProvider.notifier).refreshAfterSend();
      } catch (e) {
        log('MigrationSigningOverlay: refreshAfterSend failed: $e');
      }

      if (!mounted) return;
      widget.onComplete();
    } catch (e, st) {
      log('MigrationSigningOverlay._broadcast: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _phase = _MigrationSignPhase.failed;
        _error = _friendlyError(e);
      });
    }
  }

  String _friendlyError(Object error) {
    if (error is MigrationBatchError) return error.message;
    final lower = error.toString().toLowerCase();
    if (lower.contains('sync')) {
      return 'Sync the wallet before migrating.';
    }
    return MigrationCopy.genericError;
  }

  void _cancel() {
    if (_phase == _MigrationSignPhase.broadcasting) return;
    widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    final isBroadcasting = _phase == _MigrationSignPhase.broadcasting;
    final isFailed = _phase == _MigrationSignPhase.failed;
    final modalPhase = switch (_phase) {
      _MigrationSignPhase.ready => KeystoneSigningModalPhase.ready,
      _MigrationSignPhase.failed => KeystoneSigningModalPhase.failed,
      _MigrationSignPhase.preparing ||
      _MigrationSignPhase.broadcasting =>
        KeystoneSigningModalPhase.preparing,
    };

    return AppPaneModalOverlay(
      onDismiss: _cancel,
      child: KeystoneSigningModal(
        phase: modalPhase,
        urParts: _urParts,
        error: _error,
        title: isBroadcasting
            ? MigrationCopy.broadcastingTitle
            : MigrationCopy.signTitle,
        subtitle: isBroadcasting
            ? MigrationCopy.broadcastingSubtitle
            : MigrationCopy.signSubtitle,
        instruction: isBroadcasting
            ? MigrationCopy.broadcastingInstruction
            : isFailed
                ? null
                : MigrationCopy.signInstruction,
        primaryLabel: _phase == _MigrationSignPhase.ready
            ? MigrationCopy.signPrimary
            : null,
        onPrimary: _phase == _MigrationSignPhase.ready
            ? () => unawaited(_getSignature())
            : null,
        secondaryLabel: isBroadcasting
            ? null
            : isFailed
                ? MigrationCopy.signBack
                : MigrationCopy.signCancel,
        onSecondary: _cancel,
      ),
    );
  }
}
```

- [ ] **Step 2: Verify consumed APIs/fields against the real bindings**

Run:
```bash
grep -n "activeAccount\b\|activeAccountUuid\|activeAddress\|isHardware" lib/src/providers/account_provider.dart | head
grep -n "orchardBalance\|refreshAfterSend" lib/src/providers/sync_provider.dart | head
grep -n "ReservedPcztBatchRequest\|createReservedPcztBatch\|extractAndBroadcastPczt\|ExtractAndBroadcastPcztResult" lib/src/rust/api/sync.dart | head
grep -n "encodeZcashSignBatchUrParts\|decodeZcashSignResultCbor" lib/src/rust/api/keystone.dart | head
```
Expected: every referenced symbol exists with the used name. Fix references to match (e.g. if the account state getter is `activeAccount` returning an `AccountInfo` with `.isHardware`, as `app_main_sidebar.dart`/PR 72 use). Do **not** modify the binding files.

- [ ] **Step 3: Verify the `KeystoneSigningModal` constructor params**

Run: `grep -n "required this\.\|this\." lib/src/features/keystone/widgets/keystone_signing_modal.dart | head -20`
Expected: `phase, urParts, error, title, subtitle, instruction, primaryLabel, onPrimary, secondaryLabel, onSecondary` (confirmed in the read of this file). Match exactly.

- [ ] **Step 4: Analyze**

Run: `fvm flutter analyze lib/src/features/migration/widgets/migration_signing_overlay.dart`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/migration/widgets/migration_signing_overlay.dart
git commit -m "feat(migration): add batch signing overlay"
```

---

## Task 10: `MigrationCompletionDialog`

**Files:**
- Create: `lib/src/features/migration/widgets/migration_completion_dialog.dart`

A centered success dialog shown after broadcast. Exposes `showMigrationCompletionDialog(context)`.

- [ ] **Step 1: Write the implementation**

```dart
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../migration_copy.dart';

Future<void> showMigrationCompletionDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => const _MigrationCompletionDialog(),
  );
}

class _MigrationCompletionDialog extends StatelessWidget {
  const _MigrationCompletionDialog();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      backgroundColor: colors.background.ground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colors.background.neutralSubtleOpacity,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: AppIcon(
                  AppIcons.checkCircle,
                  size: AppIconSize.large,
                  color: colors.icon.success,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            Text(
              MigrationCopy.completeTitle,
              textAlign: TextAlign.center,
              style: AppTypography.bodyLarge.copyWith(
                color: colors.text.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              MigrationCopy.completeBody,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: AppButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(MigrationCopy.completeButton),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify theme tokens exist**

Run:
```bash
grep -rn "neutralSubtleOpacity\|background.ground" lib/src/core/theme/colors/*.dart | head
grep -n "success" lib/src/core/theme/colors/*.dart | grep -i icon | head
grep -n "checkCircle\|AppIconSize" lib/src/core/widgets/app_icon.dart | head
```
Expected: `colors.background.ground`, `colors.background.neutralSubtleOpacity`, `colors.icon.success`, `AppIcons.checkCircle`, `AppIconSize.large` all exist (the shield overlay/debug screen use these families). Adjust names to the real tokens if any differ.

- [ ] **Step 3: Analyze**

Run: `fvm flutter analyze lib/src/features/migration/widgets/migration_completion_dialog.dart`
Expected: No issues.

- [ ] **Step 4: Commit**

```bash
git add lib/src/features/migration/widgets/migration_completion_dialog.dart
git commit -m "feat(migration): add completion dialog"
```

---

## Task 11: `MigrationScreen` (the tab) + widget test

**Files:**
- Create: `lib/src/features/migration/screens/migration_screen.dart`
- Test: `test/features/migration/migration_screen_test.dart`

Renders four states based on `accountProvider` (Keystone?) and `migrationDemoProvider` (active demo?), hosts the signing overlay, and ticks once per second while a demo is in progress.

- [ ] **Step 1: Write the implementation**

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/sync_provider.dart';
import '../migration_copy.dart';
import '../migration_formatters.dart';
import '../models/migration_demo_state.dart';
import '../providers/migration_demo_provider.dart';
import '../widgets/migration_completion_dialog.dart';
import '../widgets/migration_signing_overlay.dart';

class MigrationScreen extends ConsumerStatefulWidget {
  const MigrationScreen({super.key});

  @override
  ConsumerState<MigrationScreen> createState() => _MigrationScreenState();
}

class _MigrationScreenState extends ConsumerState<MigrationScreen> {
  bool _signing = false;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _ensureTicker(bool active) {
    if (active && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!active && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  void _startSigning() => setState(() => _signing = true);
  void _cancelSigning() => setState(() => _signing = false);

  Future<void> _completeSigning() async {
    setState(() => _signing = false);
    await showMigrationCompletionDialog(context);
  }

  Future<void> _resetDemo() =>
      ref.read(migrationDemoProvider.notifier).reset();

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountProvider).value?.activeAccount;
    final isHardware = account?.isHardware ?? false;
    final demo = ref.watch(migrationDemoProvider).value;
    final now = DateTime.now();

    final inProgress = demo != null && !demo.isComplete(now);
    _ensureTicker(inProgress);

    final Widget body;
    if (!isHardware) {
      body = const _KeystoneRequiredView();
    } else if (demo == null) {
      body = _IdleView(onStart: _startSigning);
    } else if (demo.isComplete(now)) {
      body = _CompleteView(onDone: _resetDemo);
    } else {
      body = _InProgressView(demo: demo, now: now, onReset: _resetDemo);
    }

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: body,
            ),
            if (_signing)
              MigrationSigningOverlay(
                onCancel: _cancelSigning,
                onComplete: () => unawaited(_completeSigning()),
              ),
          ],
        ),
      ),
    );
  }
}

class _IdleView extends ConsumerWidget {
  const _IdleView({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final orchard = ref.watch(syncProvider).value?.orchardBalance ?? BigInt.zero;
    final amount = ZecAmount.fromZatoshi(orchard)
        .pretty(denomStyle: ZecDenomStyle.upper)
        .toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(MigrationCopy.idleTitle,
            style: AppTypography.displaySmall
                .copyWith(color: colors.text.accent)),
        const SizedBox(height: AppSpacing.xs),
        Text(MigrationCopy.idleBody,
            style: AppTypography.bodyMedium
                .copyWith(color: colors.text.secondary)),
        const SizedBox(height: AppSpacing.md),
        const _PoolTransition(),
        const SizedBox(height: AppSpacing.md),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(MigrationCopy.readyToMigrateLabel,
                  style: AppTypography.labelLarge
                      .copyWith(color: colors.text.secondary)),
              const SizedBox(height: AppSpacing.xxs),
              Text('$amount',
                  key: const ValueKey('migration_ready_amount'),
                  style: AppTypography.displaySmall
                      .copyWith(color: colors.text.accent)),
              const SizedBox(height: AppSpacing.xxs),
              Text(MigrationCopy.poolFlow,
                  style: AppTypography.bodyExtraSmall
                      .copyWith(color: colors.text.secondary)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        const _Bullets(),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          key: const ValueKey('migration_start_button'),
          onPressed: onStart,
          leading: const AppIcon(AppIcons.doubleArrowVertical),
          child: const Text(MigrationCopy.startCta),
        ),
      ],
    );
  }
}

class _KeystoneRequiredView extends StatelessWidget {
  const _KeystoneRequiredView();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(MigrationCopy.keystoneRequiredTitle,
            style: AppTypography.displaySmall
                .copyWith(color: colors.text.accent)),
        const SizedBox(height: AppSpacing.s),
        _Card(
          child: Text(
            MigrationCopy.keystoneRequiredBody,
            key: const ValueKey('migration_keystone_required'),
            style:
                AppTypography.bodyMedium.copyWith(color: colors.text.secondary),
          ),
        ),
      ],
    );
  }
}

class _InProgressView extends StatelessWidget {
  const _InProgressView(
      {required this.demo, required this.now, required this.onReset});
  final MigrationDemoState demo;
  final DateTime now;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final amount = ZecAmount.fromZatoshi(demo.displayAmountZatoshi)
        .pretty(denomStyle: ZecDenomStyle.upper)
        .toString();
    final sent = demo.transfersSent(now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(MigrationCopy.inProgressTitle,
            key: const ValueKey('migration_in_progress_title'),
            style: AppTypography.displaySmall
                .copyWith(color: colors.text.accent)),
        const SizedBox(height: AppSpacing.xs),
        Text(MigrationCopy.inProgressBody,
            style: AppTypography.bodyMedium
                .copyWith(color: colors.text.secondary)),
        const SizedBox(height: AppSpacing.md),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(MigrationCopy.migratingAmount('$amount'),
                  style: AppTypography.labelLarge
                      .copyWith(color: colors.text.secondary)),
              const SizedBox(height: AppSpacing.s),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.full),
                child: LinearProgressIndicator(
                  value: demo.progressFraction(now),
                  minHeight: 8,
                  backgroundColor: colors.background.neutralSubtleOpacity,
                  color: colors.icon.success,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${formatRemaining(demo.remaining(now))} · '
                '${formatStartedAgo(demo.sinceStart(now))}',
                style: AppTypography.bodyExtraSmall
                    .copyWith(color: colors.text.secondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        _Card(
          child: Column(
            children: [
              for (var i = 0; i < demo.transferOffsetsMs.length; i++) ...[
                if (i > 0)
                  Divider(height: AppSpacing.md, color: colors.border.subtle),
                Row(
                  children: [
                    AppIcon(
                      sent[i] ? AppIcons.checkCircle : AppIcons.time,
                      size: AppIconSize.medium,
                      color:
                          sent[i] ? colors.icon.success : colors.icon.muted,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(MigrationCopy.transferLabel(i + 1),
                          style: AppTypography.bodyMedium
                              .copyWith(color: colors.text.accent)),
                    ),
                    Text(
                      sent[i]
                          ? MigrationCopy.transferSent
                          : formatTransferEta(demo.transferEta(i, now)),
                      style: AppTypography.bodyMedium
                          .copyWith(color: colors.text.secondary),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        _Card(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppIcon(AppIcons.warning,
                  size: AppIconSize.medium, color: colors.icon.muted),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(MigrationCopy.keepOpenWarning,
                    style: AppTypography.bodyExtraSmall
                        .copyWith(color: colors.text.secondary)),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          key: const ValueKey('migration_reset_button'),
          onPressed: onReset,
          variant: AppButtonVariant.ghost,
          size: AppButtonSize.medium,
          child: const Text(MigrationCopy.resetCta),
        ),
      ],
    );
  }
}

class _CompleteView extends StatelessWidget {
  const _CompleteView({required this.onDone});
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(MigrationCopy.doneTitle,
            key: const ValueKey('migration_done_title'),
            style: AppTypography.displaySmall
                .copyWith(color: colors.text.accent)),
        const SizedBox(height: AppSpacing.xs),
        Text(MigrationCopy.doneBody,
            style: AppTypography.bodyMedium
                .copyWith(color: colors.text.secondary)),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          onPressed: onDone,
          child: const Text(MigrationCopy.doneButton),
        ),
      ],
    );
  }
}

class _PoolTransition extends StatelessWidget {
  const _PoolTransition();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: _Card(
            child: Column(
              children: [
                Text(MigrationCopy.fromPoolName,
                    style: AppTypography.bodyLarge
                        .copyWith(color: colors.text.accent)),
                Text(MigrationCopy.fromPoolTag,
                    style: AppTypography.bodyExtraSmall
                        .copyWith(color: colors.text.secondary)),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
          child: AppIcon(AppIcons.arrowForwardIos,
              size: AppIconSize.medium, color: colors.icon.muted),
        ),
        Expanded(
          child: _Card(
            child: Column(
              children: [
                Text(MigrationCopy.toPoolName,
                    style: AppTypography.bodyLarge
                        .copyWith(color: colors.text.accent)),
                Text(MigrationCopy.toPoolTag,
                    style: AppTypography.bodyExtraSmall
                        .copyWith(color: colors.text.secondary)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Bullets extends StatelessWidget {
  const _Bullets();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget bullet(String text) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('›  ',
                  style: AppTypography.bodyMedium
                      .copyWith(color: colors.text.secondary)),
              Expanded(
                child: Text(text,
                    style: AppTypography.bodyMedium
                        .copyWith(color: colors.text.secondary)),
              ),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        bullet(MigrationCopy.bullet1),
        bullet(MigrationCopy.bullet2),
        bullet(MigrationCopy.bullet3),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.background.neutralSubtleOpacity,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: child,
    );
  }
}
```

- [ ] **Step 2: Verify icon + token names used here**

Run:
```bash
grep -n "doubleArrowVertical\|arrowForwardIos\|checkCircle\|time\b\|warning" lib/src/core/widgets/app_icon.dart | head
grep -rn "neutralSubtleOpacity\|border.subtle\|icon.muted\|icon.success" lib/src/core/theme/colors/*.dart | head
```
Expected: all referenced `AppIcons.*` and `colors.*` exist (these names appear in the sidebar/debug/shield files). Replace any that don't with the nearest real token.

- [ ] **Step 3: Write the widget test (idle + keystone-required states)**

Override the heavy providers so the screen renders deterministically. Inspect `test/providers/account_provider_test.dart` and `test/fakes/fake_sync_notifier.dart` first and reuse their setup helpers for `accountProvider` / `syncProvider`. The test asserts the gating + key copy.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vizor/src/features/migration/migration_copy.dart';
import 'package:vizor/src/features/migration/models/migration_demo_state.dart';
import 'package:vizor/src/features/migration/providers/migration_demo_provider.dart';
import 'package:vizor/src/features/migration/screens/migration_screen.dart';
// Import the app's theme host + account/sync providers; mirror an existing
// widget test's harness (see test/core/widgets/*_test.dart) for ThemeHost wrap.

void main() {
  // Pseudocode harness — fill in using the existing widget-test harness in
  // this repo (ThemeHost/AppTheme wrapper + provider overrides). The assertions
  // below are the contract this screen must satisfy:

  testWidgets('keystone-required state shows when account is software',
      (tester) async {
    // Override accountProvider so activeAccount.isHardware == false, and
    // migrationDemoProvider -> null. Pump MigrationScreen inside the app theme.
    // expect(find.byKey(const ValueKey('migration_keystone_required')),
    //     findsOneWidget);
  }, skip: 'enable once wired to the repo widget-test harness');

  testWidgets('idle state shows Start migration for a Keystone account',
      (tester) async {
    // Override accountProvider so activeAccount.isHardware == true, demo null.
    // expect(find.byKey(const ValueKey('migration_start_button')),
    //     findsOneWidget);
    // expect(find.text(MigrationCopy.startCta), findsOneWidget);
  }, skip: 'enable once wired to the repo widget-test harness');
}
```

> The two tests are `skip`-marked scaffolds because faithful overrides of `accountProvider`/`syncProvider` depend on this repo's existing harness, which the implementing engineer should wire using the referenced example tests. Removing `skip` and filling the overrides is part of this step. If wiring proves heavy, downgrade to verifying the pure state-selection logic by extracting a `migrationViewState(isHardware, demo, now)` enum function and unit-testing that instead — and update this screen to use it.

- [ ] **Step 4: Analyze + run tests**

Run: `fvm flutter analyze lib/src/features/migration/screens/migration_screen.dart`
Run: `fvm flutter test test/features/migration/migration_screen_test.dart`
Expected: analyze clean; tests pass (or are explicitly skipped per the note, with the extracted-logic unit test passing if that fallback is taken).

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/migration/screens/migration_screen.dart test/features/migration/migration_screen_test.dart
git commit -m "feat(migration): add Migration tab screen with all states"
```

---

## Task 12: Wire the sidebar item + routes

**Files:**
- Modify: `lib/src/core/layout/app_main_sidebar.dart`
- Modify: `lib/app.dart`

- [ ] **Step 1: Add the sidebar item (after the Vote item)**

In `app_main_sidebar.dart`, immediately after the `AppSidebarItem(key: const ValueKey('sidebar_voting_button'), ...)` block, insert:

```dart
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    key: const ValueKey('sidebar_migration_button'),
                    label: 'Migration',
                    iconName: AppIcons.doubleArrowVertical,
                    active: _matches('/migration'),
                    onTap: _matches('/migration')
                        ? null
                        : () => _navigateTo('/migration'),
                  ),
```

- [ ] **Step 2: Add routes in `app.dart`**

Add imports near the other feature-screen imports:
```dart
import 'src/features/migration/screens/migration_screen.dart';
import 'src/features/migration/screens/migration_scan_screen.dart';
```
Add routes near the `/home` route:
```dart
      GoRoute(path: '/migration', builder: (_, _) => const MigrationScreen()),
      GoRoute(
        path: '/migration/scan',
        builder: (_, _) => const MigrationScanScreen(),
      ),
```

- [ ] **Step 3: Analyze the wired files**

Run: `fvm flutter analyze lib/app.dart lib/src/core/layout/app_main_sidebar.dart`
Expected: No issues.

- [ ] **Step 4: Commit**

```bash
git add lib/app.dart lib/src/core/layout/app_main_sidebar.dart
git commit -m "feat(migration): add sidebar entry and routes"
```

---

## Task 13: Full verification + manual checklist

**Files:** (none — verification only)

- [ ] **Step 1: Full analyze**

Run: `fvm flutter analyze`
Expected: No issues in the new feature (pre-existing repo warnings unrelated to `lib/src/features/migration/**`, `lib/app.dart`, `lib/src/core/layout/app_main_sidebar.dart` are out of scope).

- [ ] **Step 2: Full test suite for the feature**

Run: `fvm flutter test test/features/migration/`
Expected: All migration tests pass.

- [ ] **Step 3: Full test suite (regression)**

Run: `fvm flutter test`
Expected: No new failures introduced by this change.

- [ ] **Step 4: Manual verification (macOS desktop, Keystone account)**

Per the user's CLAUDE.md recipe (local bundle id `com.adamtucker.vizor.local`, `xcodebuild` + `open -n`), build and launch, then:
1. Confirm "Migration" appears in the sidebar after "Vote".
2. With a **software** account active → the tab shows the Keystone-required message; no "Start migration" button.
3. With a **Keystone** account active (≥3 spendable Orchard notes) → idle landing shows the Orchard balance; "Start migration" opens the signing modal (animated QR), then "Scan signed result" → scan screen → after the device signs, all 3 broadcast → completion popup → tab flips to in-progress with the progress bar, 3 transfers (one "Sent"), and the keep-open warning.
4. "Reset demo" returns the tab to idle.
5. Restart the app mid-progress → in-progress state rehydrates and keeps advancing.
6. Error path: with <3 distinct notes → friendly "needs at least 3 spendable notes" message, returns to idle.

> Note (from CLAUDE.md): the self-sends are **real transactions**; verify on **testnet/regtest** to avoid mainnet fees. Do not regenerate FRB bindings on this machine.

- [ ] **Step 5: Push and open the PR**

```bash
git push -u origin adam/migration-tab
```
Open a PR titled "Add Ironwood migration showcase (incl. Keystone batch-signing support)". Body: short summary + that it's a UI showcase (no real pool migration), self-sends are real, built on the batch machinery. Per the user's CLAUDE.md, do NOT reference other repos' PR numbers; describe the batch-signing dependency in prose. The user opens/sends any PR review comments — not the agent.

---

## Self-review notes (author)

- **Spec coverage:** sidebar entry (T12), idle/software/in-progress/complete states (T11), signing journey + copy (T7/T9/T10), batch mechanism (T9), persistence + reset + rehydrate (T1/T5/T6/T11), Keystone-only gating (T9/T11), edge cases (T3/T9), PR base strategy (T0), testing (T1-6, T11, T13). All mapped.
- **Type consistency:** `MigrationDemoState`, `buildMigrationDemoState`, `MigrationBatchError`/`verifyDistinctNotes`/`verifySignResult`, `MigrationDemoStore.{read,write,clear}`, `migrationDemoProvider`/`MigrationDemoNotifier.{startDemo,reset}`, `MigrationSigningOverlay`, `MigrationScanScreen`, `MigrationScreen`, `showMigrationCompletionDialog`, `MigrationCopy.*` are used consistently across tasks.
- **Verification seams:** every task that consumes a binding/widget/theme token includes an explicit `grep` step to confirm the real signature before relying on it, because some names are inferred from usage rather than read in full. Adjust call sites (never the bindings) to match.
