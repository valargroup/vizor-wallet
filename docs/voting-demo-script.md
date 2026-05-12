# Coinholder Polling Demo Script

This is the local macOS smoke path for the Vizor coinholder polling demo.
It assumes a software account. Keystone accounts intentionally show
`Hardware accounts coming soon` in Settings.

## Preconditions

- Run from the repository root.
- Use the configured voting service endpoints from the bundled/static voting
  config, or override the config before launch if testing a private service.
- The active account must be a software account with enough shielded funds at
  the poll snapshot height to produce at least one voting bundle.
- The wallet must be fully synced before opening the voting flow.

## Launch

```bash
fvm flutter run -d macos
```

## Happy Path

1. Unlock the wallet.
2. Open `Settings`.
3. Select `Coinholder Polling`.
4. Verify the poll list loads and shows endorsed and unverified badges.
5. Open an active poll.
6. Pick at least one proposal option.
7. Select `Review Votes`.
8. Verify the selected options are correct.
9. Select `Submit Votes`.
10. Keep the app foregrounded while the status screen progresses through:
    `Selecting notes`, `Generating delegation proof (ZKP1)`,
    `Broadcasting delegation`, `Generating vote proof (ZKP2)`, and
    `Submitting shares`.
11. Verify the app routes to results after completion.
12. Refresh the vote server tally externally, then reload the results screen.

## Resume Smoke

1. Start the happy path and wait until vote proof generation or share
   submission begins.
2. Quit the app.
3. Relaunch with `fvm flutter run -d macos`.
4. Navigate back to the same round.
5. Verify the session resumes from `VotingDb` recovery state instead of
   rebuilding completed delegation bundles.
6. Verify pending shares are confirmed or retried from stored share delegation
   rows.

## Timing Notes

Record these after each manual run:

- Machine:
- Network:
- Bundle count:
- ZKP1 duration:
- ZKP2 duration:
- Share submission latency:
- Resume point tested:
- Result:

## Known Demo Limits

- The current implementation is macOS-first and foreground-only.
- iOS background task plumbing is intentionally deferred.
- Hardware accounts are hidden from the live flow.
- Heavy regtest coverage remains a separate pass; do not run
  `./run-regtest-rust-tests.sh` unless explicitly requested.
