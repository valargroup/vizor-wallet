//! Hardware-wallet PCZT pipeline.
//!
//! Software sends are handled by `sync/send.rs`. This module owns the
//! three-PCZT pipeline the hardware (Keystone) send flow uses, which
//! matches the `zcash-android-wallet-sdk` / Zashi pattern:
//!
//! ```text
//!   1. create_pczt_from_proposal                      → base PCZT (phone)
//!      (IO-finalized, no proofs, no signatures)
//!         │
//!         ├── 2a. add_proofs_to_pczt(base, params?)   → pcztWithProofs   (phone, CPU)
//!         │       (Orchard proof always; Sapling output proofs if
//!         │        the proposal has a non-empty Sapling bundle)
//!         │
//!         └── 2b. redact_pczt_for_signer(base)        → redactedPczt     (phone)
//!                 → Keystone device (animated QR)
//!                 → device signs Orchard spend_auth_sig
//!                 → signed PCZT back to phone          → pcztWithSignatures
//!                                                            │
//!   3. extract_and_broadcast_pczt(                             │
//!        pcztWithProofs, pcztWithSignatures,                   │
//!        spend_params?, output_params?,                        │
//!      )                                               → finalize transparent spends
//!                                                        + extract tx + txid ◄┘
//! ```
//!
//! ## Critical invariants (each of these was a real regression at some point)
//!
//! 1. **`extract_and_broadcast_pczt` broadcasts before it persists.**
//!    Extract the `Transaction` in-memory, send it to the network,
//!    and *only then* write it to the wallet DB. The naive
//!    store-then-broadcast path leaves the wallet unrecoverable when
//!    lightwalletd rejects the tx: the DB thinks the notes are
//!    spent, the network has no record, and the user has to
//!    manually rescue the wallet.
//!
//! 2. **Local storage failure after a successful broadcast must not
//!    surface as a send failure.** Primary store path is
//!    `extract_and_store_transaction_from_pczt` (preserves rich
//!    PCZT recipient/memo metadata). On failure, fall back to
//!    `decrypt_and_store_transaction` — the same path sync uses when
//!    it discovers one of our sent txs on-chain. Spent notes still
//!    get marked spent via nullifier matching; only the PCZT-only
//!    display metadata is lost. Only if both paths fail do we
//!    return an error — and the error explains the tx is on the
//!    network and not to retry.
//!
//! 3. **Sapling params must be passed to BOTH `add_proofs_to_pczt`
//!    AND `extract_and_broadcast_pczt` whenever the PCZT contains a
//!    Sapling bundle.** `add_proofs_to_pczt` uses `LocalTxProver` to
//!    build Sapling output proofs; `extract_and_broadcast_pczt`
//!    uses `LocalTxProver::verifying_keys()` to validate the
//!    extracted transaction and to let
//!    `extract_and_store_transaction_from_pczt` store it. If the
//!    caller supplied params to `add_proofs_to_pczt` but passed
//!    `None` here, extraction bails with `SaplingRequired` and the
//!    user sees a cryptic error after already downloading 50MB of
//!    params and approving on the device. The Dart call site in
//!    `send_screen.dart` threads
//!    `proposal.needsSaplingParams ? spendPath : null` into both —
//!    keep it that way.
//!
//! 4. **`PROPOSAL_STORE` is consume-on-entry for both execute paths,
//!    plus explicit discard on cancel.** `create_pczt_from_proposal`
//!    calls `PROPOSAL_STORE.remove()` at the top (dropping the lock
//!    before any DB work). A second call with the same `proposal_id`
//!    returns "Proposal not found (expired or already consumed)".
//!    `discard_proposal` is idempotent; the Dart `finally` cleanup
//!    calls it when the consume path was never reached (user
//!    cancelled, exception before the consume call, etc.).

use std::convert::Infallible;

use sha2::{Digest, Sha256};
use zcash_primitives::transaction::TxVersion;
use zcash_proofs::prover::LocalTxProver;

use crate::wallet::db::with_wallet_db_write_lock;
use crate::wallet::network::WalletNetwork;

use super::{consume_stored_proposal, discard_stored_proposal, open_wallet_db};

const QLEAK_V5_RANDOMIZED_CIPHERTEXT_MARKER: &str = "qleak:v5-randomized-enc-ciphertext";

pub struct ExtractAndBroadcastPcztResult {
    pub txid: String,
    pub status: String,
    pub message: Option<String>,
}

impl ExtractAndBroadcastPcztResult {
    const BROADCASTED: &'static str = "broadcasted";
    const BROADCAST_UNKNOWN: &'static str = "broadcast_unknown";
    const BROADCASTED_STORAGE_FAILED: &'static str = "broadcasted_storage_failed";

    fn broadcasted(txid: String) -> Self {
        Self {
            txid,
            status: Self::BROADCASTED.to_string(),
            message: None,
        }
    }

    fn broadcast_unknown(txid: String, message: String) -> Self {
        Self {
            txid,
            status: Self::BROADCAST_UNKNOWN.to_string(),
            message: Some(message),
        }
    }

    fn broadcasted_storage_failed(txid: String, message: String) -> Self {
        Self {
            txid,
            status: Self::BROADCASTED_STORAGE_FAILED.to_string(),
            message: Some(message),
        }
    }
}

#[derive(Clone, Debug)]
struct QleakCiphertextAudit {
    action_index: usize,
    cmx_sha256: String,
    enc_ciphertext_sha256: String,
    enc_ciphertext_len: usize,
    value_present: bool,
    zero_value: bool,
    no_user_address: bool,
    marker_present: bool,
}

fn sha256_hex(bytes: impl AsRef<[u8]>) -> String {
    hex::encode(Sha256::digest(bytes.as_ref()))
}

fn qleak_randomized_output_stats(pczt: &pczt::Pczt) -> (usize, usize, usize, usize) {
    pczt.orchard().actions().iter().fold(
        (0usize, 0usize, 0usize, 0usize),
        |(total, value_present, zero_value, no_user_address), action| {
            let output = action.output();
            if output
                .proprietary()
                .contains_key(QLEAK_V5_RANDOMIZED_CIPHERTEXT_MARKER)
            {
                (
                    total + 1,
                    value_present + usize::from(output.value().is_some()),
                    zero_value
                        + usize::from(output.value().as_ref().is_some_and(|value| *value == 0)),
                    no_user_address + usize::from(output.user_address().is_none()),
                )
            } else {
                (total, value_present, zero_value, no_user_address)
            }
        },
    )
}

fn qleak_marked_ciphertext_audits(pczt: &pczt::Pczt) -> Vec<QleakCiphertextAudit> {
    pczt.orchard()
        .actions()
        .iter()
        .enumerate()
        .filter_map(|(action_index, action)| {
            let output = action.output();
            let marker_present = output
                .proprietary()
                .contains_key(QLEAK_V5_RANDOMIZED_CIPHERTEXT_MARKER);
            marker_present.then(|| QleakCiphertextAudit {
                action_index,
                cmx_sha256: sha256_hex(output.cmx()),
                enc_ciphertext_sha256: sha256_hex(output.enc_ciphertext()),
                enc_ciphertext_len: output.enc_ciphertext().len(),
                value_present: output.value().is_some(),
                zero_value: output.value().as_ref().is_some_and(|value| *value == 0),
                no_user_address: output.user_address().is_none(),
                marker_present,
            })
        })
        .collect()
}

fn qleak_ciphertext_audit_for_action(
    action_index: usize,
    action: &pczt::orchard::Action,
) -> QleakCiphertextAudit {
    let output = action.output();
    QleakCiphertextAudit {
        action_index,
        cmx_sha256: sha256_hex(output.cmx()),
        enc_ciphertext_sha256: sha256_hex(output.enc_ciphertext()),
        enc_ciphertext_len: output.enc_ciphertext().len(),
        value_present: output.value().is_some(),
        zero_value: output.value().as_ref().is_some_and(|value| *value == 0),
        no_user_address: output.user_address().is_none(),
        marker_present: output
            .proprietary()
            .contains_key(QLEAK_V5_RANDOMIZED_CIPHERTEXT_MARKER),
    }
}

fn log_qleak_ciphertext_audits(label: &str, audits: &[QleakCiphertextAudit]) {
    if audits.is_empty() {
        log::warn!("qleak: {label} marked_output count=0");
    }

    for audit in audits {
        log::info!(
            "qleak: {label} marked_output action_index={} value_present={} zero_value={} \
             no_user_address={} marker_present={} cmx_sha256={} enc_ciphertext_sha256={} \
             enc_ciphertext_len={}",
            audit.action_index,
            audit.value_present,
            audit.zero_value,
            audit.no_user_address,
            audit.marker_present,
            audit.cmx_sha256,
            audit.enc_ciphertext_sha256,
            audit.enc_ciphertext_len,
        );
    }
}

fn log_qleak_ciphertext_retention(
    label: &str,
    pczt: &pczt::Pczt,
    expected: &[QleakCiphertextAudit],
) {
    for expected_audit in expected {
        let matched =
            pczt.orchard()
                .actions()
                .iter()
                .enumerate()
                .find_map(|(action_index, action)| {
                    let output = action.output();
                    let cmx_matches = sha256_hex(output.cmx()) == expected_audit.cmx_sha256;
                    let enc_ciphertext_matches =
                        sha256_hex(output.enc_ciphertext()) == expected_audit.enc_ciphertext_sha256;
                    (cmx_matches && enc_ciphertext_matches)
                        .then(|| qleak_ciphertext_audit_for_action(action_index, action))
                });

        match matched {
            Some(actual) => log::info!(
                "qleak: {label} retained_marked_ciphertext expected_action_index={} \
                 matched_action_index={} value_present={} zero_value={} no_user_address={} \
                 marker_present={} cmx_sha256={} enc_ciphertext_sha256={} enc_ciphertext_len={}",
                expected_audit.action_index,
                actual.action_index,
                actual.value_present,
                actual.zero_value,
                actual.no_user_address,
                actual.marker_present,
                actual.cmx_sha256,
                actual.enc_ciphertext_sha256,
                actual.enc_ciphertext_len,
            ),
            None => log::error!(
                "qleak: {label} missing_marked_ciphertext expected_action_index={} \
                 cmx_sha256={} enc_ciphertext_sha256={} enc_ciphertext_len={}",
                expected_audit.action_index,
                expected_audit.cmx_sha256,
                expected_audit.enc_ciphertext_sha256,
                expected_audit.enc_ciphertext_len,
            ),
        }
    }
}

fn log_qleak_pczt_summary(label: &str, pczt: &pczt::Pczt) {
    let global = pczt.global();
    #[cfg(zcash_unstable = "nu6.3")]
    let ironwood_actions = pczt.ironwood().actions().len();
    #[cfg(not(zcash_unstable = "nu6.3"))]
    let ironwood_actions = 0usize;
    let (
        randomized_outputs,
        randomized_value_present,
        randomized_zero_value,
        randomized_no_user_address,
    ) = qleak_randomized_output_stats(pczt);

    log::info!(
        "qleak: {label} pczt tx_version={} version_group_id={:#x} consensus_branch_id={:#x} \
         orchard_actions={} orchard_flags={:#x} qleak_randomized_outputs={} \
         qleak_randomized_value_present={} qleak_randomized_zero_value={} \
         qleak_randomized_no_user_address={} ironwood_actions={}",
        global.tx_version(),
        global.version_group_id(),
        global.consensus_branch_id(),
        pczt.orchard().actions().len(),
        pczt.orchard().flags(),
        randomized_outputs,
        randomized_value_present,
        randomized_zero_value,
        randomized_no_user_address,
        ironwood_actions,
    );
}

/// Create a PCZT from a stored proposal (for hardware wallet signing).
///
/// This is the hardware-wallet analogue of `execute_proposal`, and
/// mirrors its lifecycle: the proposal is **removed** from the store
/// on entry, so any subsequent failure (PCZT creation error,
/// hardware signing cancel, broadcast rejection) can't leave a
/// replayable proposal ID behind. If the caller aborts the send flow
/// before reaching this function (e.g. the confirmation dialog is
/// cancelled), Dart is expected to call [`discard_proposal`]
/// explicitly to release the stored proposal.
pub fn create_pczt_from_proposal(
    db_path: &str,
    network: WalletNetwork,
    proposal_id: u64,
    send_flow_id: &str,
) -> Result<Vec<u8>, String> {
    use zcash_client_backend::data_api::wallet::create_pczt_from_proposal_with_tx_version as zcb_create_pczt;
    use zcash_client_backend::wallet::OvkPolicy;

    // Consume the proposal up-front (matches execute_proposal), so
    // that any later failure path leaves the PROPOSAL_STORE clean.
    let stored = consume_stored_proposal(
        proposal_id,
        send_flow_id,
        "Proposal not found (expired or already consumed)",
    )?;

    let pczt = with_wallet_db_write_lock("pczt.create_pczt_from_proposal", || {
        let mut db = open_wallet_db(db_path, network)?;
        zcb_create_pczt::<_, _, Infallible, _, Infallible, _>(
            &mut db,
            &network,
            stored.account_id,
            OvkPolicy::Sender,
            &stored.proposal,
            TxVersion::V5,
        )
        .map_err(|e| format!("Create PCZT failed: {e}"))
    })?;

    log_qleak_pczt_summary("created", &pczt);

    Ok(pczt.serialize())
}

/// Release a stored proposal without executing it. Called from the
/// Dart send flow when the user cancels before
/// [`create_pczt_from_proposal`] (e.g. dismisses the confirmation
/// dialog, cancels the Sapling params download prompt). Idempotent:
/// safe to call for a proposal that has already been consumed or
/// never existed.
pub fn discard_proposal(proposal_id: u64, send_flow_id: &str) {
    discard_stored_proposal(proposal_id, send_flow_id);
}

/// Add Orchard (and, if needed, Sapling) proofs to a PCZT locally.
/// Returns a PCZT-with-proofs, which must later be combined with the
/// signed PCZT returned by the hardware signer.
///
/// Sapling params paths are only required when the PCZT contains a
/// non-empty Sapling bundle (e.g. the recipient is a Sapling-only
/// address or a Unified Address without an Orchard receiver).
/// Orchard-only sends can pass `None` for both paths. This matches
/// the Zashi / zcash-android-wallet-sdk hardware-wallet flow: the
/// hardware device only signs Orchard spends, the phone generates
/// all ZK proofs.
pub fn add_proofs_to_pczt(
    pczt_bytes: &[u8],
    spend_params_path: Option<&str>,
    output_params_path: Option<&str>,
) -> Result<Vec<u8>, String> {
    use pczt::roles::prover::Prover;

    let pczt = pczt::Pczt::parse(pczt_bytes).map_err(|e| format!("Parse PCZT: {e:?}"))?;

    let mut prover = Prover::new(pczt);

    if prover.requires_orchard_proof() {
        prover = prover
            .create_orchard_proof(&orchard::circuit::ProvingKey::build(
                orchard::circuit::OrchardCircuitVersion::FixedPostNu6_2,
            ))
            .map_err(|e| format!("Orchard proof: {e:?}"))?;
    }

    if prover.requires_sapling_proofs() {
        match (spend_params_path, output_params_path) {
            (Some(sp), Some(op)) if !sp.is_empty() && !op.is_empty() => {
                let local_prover =
                    LocalTxProver::new(std::path::Path::new(sp), std::path::Path::new(op));
                prover = prover
                    .create_sapling_proofs(&local_prover, &local_prover)
                    .map_err(|e| format!("Sapling proofs: {e:?}"))?;
            }
            _ => {
                return Err(
                    "PCZT requires Sapling proofs but no Sapling params were supplied. \
                     Download sapling-spend.params and sapling-output.params first."
                        .into(),
                );
            }
        }
    }

    Ok(prover.finish().serialize())
}

/// Redact information from a PCZT that the signer role doesn't need
/// (witnesses, proprietary metadata). Produces the bytes to send to
/// the hardware wallet for signing.
pub fn redact_pczt_for_signer(pczt_bytes: &[u8]) -> Result<Vec<u8>, String> {
    use pczt::roles::redactor::Redactor;

    let pczt = pczt::Pczt::parse(pczt_bytes).map_err(|e| format!("Parse PCZT: {e:?}"))?;
    log_qleak_pczt_summary("pre-redact", &pczt);
    let pre_redact_audits = qleak_marked_ciphertext_audits(&pczt);
    log_qleak_ciphertext_audits("pre-redact", &pre_redact_audits);

    let redacted = Redactor::new(pczt)
        .redact_global_with(|mut r| r.redact_proprietary("zcash_client_backend:proposal_info"))
        .redact_orchard_with(|mut r| {
            r.redact_actions(|mut ar| {
                ar.clear_spend_witness();
                ar.redact_output_proprietary("zcash_client_backend:output_info");
                ar.redact_output_proprietary(QLEAK_V5_RANDOMIZED_CIPHERTEXT_MARKER);
            });
        })
        .redact_sapling_with(|mut r| {
            r.redact_spends(|mut sr| sr.clear_witness());
            r.redact_outputs(|mut or| {
                or.redact_proprietary("zcash_client_backend:output_info");
            });
        })
        .redact_transparent_with(|mut r| {
            r.redact_outputs(|mut or| {
                or.redact_proprietary("zcash_client_backend:output_info");
            });
        })
        .finish();
    log_qleak_pczt_summary("redacted", &redacted);
    log_qleak_ciphertext_retention("redacted", &redacted, &pre_redact_audits);

    let redacted_bytes = redacted
        .serialize_legacy_v1()
        .map_err(|e| format!("Serialize legacy PCZT v1 for signer: {e}"))?;
    let redacted_v1_roundtrip =
        pczt::Pczt::parse(&redacted_bytes).map_err(|e| format!("Parse redacted PCZT v1: {e:?}"))?;
    log_qleak_ciphertext_retention(
        "redacted-v1-roundtrip",
        &redacted_v1_roundtrip,
        &pre_redact_audits,
    );
    log::info!(
        "qleak: redacted signer PCZT serialized as legacy v1 byte_len={} sha256={}",
        redacted_bytes.len(),
        sha256_hex(&redacted_bytes),
    );

    Ok(redacted_bytes)
}

/// Combine a PCZT-with-proofs and a PCZT-with-signatures, broadcast
/// the resulting transaction, and persist it to the wallet DB after
/// the broadcast is accepted, or after a broadcast response deadline
/// leaves acceptance ambiguous.
///
/// Ordering is critical here. See invariants (1) and (2) in the
/// module-level docstring.
pub async fn extract_and_broadcast_pczt(
    db_path: &str,
    lightwalletd_url: &str,
    network: WalletNetwork,
    pczt_with_proofs_bytes: &[u8],
    pczt_with_signatures_bytes: &[u8],
    spend_params_path: Option<&str>,
    output_params_path: Option<&str>,
) -> Result<ExtractAndBroadcastPcztResult, String> {
    use pczt::roles::combiner::Combiner;
    use pczt::roles::spend_finalizer::SpendFinalizer;
    use pczt::roles::tx_extractor::TransactionExtractor;
    use zcash_client_backend::data_api::wallet::{
        decrypt_and_store_transaction, extract_and_store_transaction_from_pczt,
    };

    log::info!(
        "qleak: extract input PCZT hashes proofs_sha256={} signatures_sha256={}",
        sha256_hex(pczt_with_proofs_bytes),
        sha256_hex(pczt_with_signatures_bytes),
    );
    {
        let proofs_pczt = pczt::Pczt::parse(pczt_with_proofs_bytes)
            .map_err(|e| format!("Parse PCZT with proofs for qleak audit: {e:?}"))?;
        let signatures_pczt = pczt::Pczt::parse(pczt_with_signatures_bytes)
            .map_err(|e| format!("Parse PCZT with signatures for qleak audit: {e:?}"))?;
        let proof_audits = qleak_marked_ciphertext_audits(&proofs_pczt);
        log_qleak_pczt_summary("proofs-before-combine", &proofs_pczt);
        log_qleak_ciphertext_audits("proofs-before-combine", &proof_audits);
        log_qleak_pczt_summary("signed-before-combine", &signatures_pczt);
        log_qleak_ciphertext_retention("signed-before-combine", &signatures_pczt, &proof_audits);
    }

    // Re-parsing and re-combining is cheap compared to ZK proof
    // validation; we do it twice so we can hand one owned Pczt to
    // the in-memory extractor and a second owned Pczt to the storage
    // function after broadcast.
    fn combine_pczts(proofs: &[u8], sigs: &[u8]) -> Result<pczt::Pczt, String> {
        let p = pczt::Pczt::parse(proofs).map_err(|e| format!("Parse PCZT with proofs: {e:?}"))?;
        let s =
            pczt::Pczt::parse(sigs).map_err(|e| format!("Parse PCZT with signatures: {e:?}"))?;
        Combiner::new(vec![p, s])
            .combine()
            .map_err(|e| format!("Combine PCZTs: {e:?}"))
    }

    let orchard_vk = orchard::circuit::VerifyingKey::build(
        orchard::circuit::OrchardCircuitVersion::FixedPostNu6_2,
    );

    // Load Sapling verifying keys once if the caller supplied params.
    // The prover keeps the underlying params alive, and
    // `verifying_keys()` returns owned
    // `(SpendVerifyingKey, OutputVerifyingKey)`. We hand references
    // into this tuple to both `TransactionExtractor::with_sapling`
    // and `extract_and_store_transaction_from_pczt`.
    let sapling_vks: Option<(
        sapling_crypto::circuit::SpendVerifyingKey,
        sapling_crypto::circuit::OutputVerifyingKey,
    )> = match (spend_params_path, output_params_path) {
        (Some(sp), Some(op)) if !sp.is_empty() && !op.is_empty() => {
            let prover = LocalTxProver::new(std::path::Path::new(sp), std::path::Path::new(op));
            Some(prover.verifying_keys())
        }
        _ => None,
    };

    // Step 1: extract the Transaction without touching the DB. We
    // keep `tx` around after broadcast so the fallback storage path
    // can use it.
    let tx = {
        let finalized_pczt = SpendFinalizer::new(combine_pczts(
            pczt_with_proofs_bytes,
            pczt_with_signatures_bytes,
        )?)
        .finalize_spends()
        .map_err(|e| format!("Finalize transparent spends in PCZT: {e:?}"))?;

        let mut extractor = TransactionExtractor::new(finalized_pczt).with_orchard(&orchard_vk);
        if let Some((spend_vk, output_vk)) = sapling_vks.as_ref() {
            extractor = extractor.with_sapling(spend_vk, output_vk);
        }
        extractor
            .extract()
            .map_err(|e| format!("Extract TX from PCZT: {e:?}"))?
    };
    let txid = tx.txid();

    let tx_bytes = {
        let mut buf = Vec::new();
        tx.write(&mut buf)
            .map_err(|e| format!("Serialize TX: {e}"))?;
        buf
    };

    let store_locally = || -> Result<(), String> {
        with_wallet_db_write_lock("pczt.extract_and_broadcast_pczt.store", || {
            let mut db = open_wallet_db(db_path, network)?;

            // Primary path: rich PCZT-aware storage (preserves
            // recipient/memo). Hand Sapling verifying keys in whenever the
            // combined PCZT has a Sapling bundle, otherwise librustzcash
            // rejects the extraction with `SaplingRequired` before we can
            // store anything.
            let sapling_vk_pair = sapling_vks.as_ref().map(|(s, o)| (s, o));
            match extract_and_store_transaction_from_pczt::<_, zcash_client_sqlite::ReceivedNoteId>(
                &mut db,
                combine_pczts(pczt_with_proofs_bytes, pczt_with_signatures_bytes)?,
                sapling_vk_pair,
                Some(&orchard_vk),
            ) {
                Ok(_) => return Ok(()),
                Err(primary_err) => {
                    log::warn!(
                        "keystone: PCZT-aware storage failed \
                         (txid={txid}): {primary_err}. Falling back to chain-style \
                         decrypt_and_store_transaction; rich recipient metadata \
                         will not be available in history until the next sync."
                    );

                    // Fallback path: same code sync uses when it discovers a
                    // wallet tx on the chain. Marks spent notes correctly
                    // via nullifier matching and picks up any change note
                    // back to us from enc_ciphertext decryption. The
                    // recipient/memo metadata that was only in the PCZT
                    // proprietary fields is lost, but correctness is
                    // preserved — the spent notes no longer appear
                    // spendable.
                    decrypt_and_store_transaction(&network, &mut db, &tx, None).map_err(
                        |fallback_err| format!("Primary: {primary_err}. Fallback: {fallback_err}"),
                    )?;
                }
            }

            Ok(())
        })
    };

    // Step 2: broadcast. Definite rejection leaves the DB untouched,
    // but a response deadline is ambiguous: lightwalletd may already
    // have relayed the transaction, so we store locally and let the
    // normal pending/resubmit path reconcile it.
    let mut client = crate::wallet::sync_engine::open_lwd_channel(lightwalletd_url)
        .await
        .map_err(|e| e.to_string())?;

    let resp = match crate::wallet::sync_engine::send_transaction_with_status(
        &mut client,
        &tx_bytes,
    )
    .await
    {
        Ok(resp) => resp,
        Err(status) if status.code() == tonic::Code::DeadlineExceeded => {
            let mut message = format!(
                "Broadcast response timed out for txid={txid}. The transaction may already \
                 be on the network. Do not send again until sync or an explorer confirms \
                 whether this transaction was accepted."
            );
            match store_locally() {
                Ok(()) => {
                    message.push_str(
                        " It was stored locally and will retry automatically during sync until \
                         it is confirmed or expires.",
                    );
                }
                Err(storage_err) => {
                    log::error!(
                        "keystone: failed to store tx after ambiguous broadcast timeout \
                         (txid={txid}): {storage_err}"
                    );
                    message.push_str(&format!(
                        " Local tracking also failed: {storage_err}. Check an explorer before \
                         retrying this send."
                    ));
                }
            }
            return Ok(ExtractAndBroadcastPcztResult::broadcast_unknown(
                txid.to_string(),
                message,
            ));
        }
        Err(status) => return Err(format!("Broadcast: {status}")),
    };

    // zebra-lightwalletd returns the txid in `error_message` on
    // success, so the only reliable signal is `error_code`.
    if resp.error_code != 0 {
        return Err(format!(
            "Broadcast rejected: {} (code {})",
            resp.error_message, resp.error_code
        ));
    }

    // Step 3: broadcast was accepted. Persist locally so the UI
    // sees the tx immediately and the spent notes stop showing up
    // as spendable.
    if let Err(storage_err) = store_locally() {
        log::error!(
            "keystone: broadcast succeeded but local storage failed \
             (txid={txid}): {storage_err}"
        );
        return Ok(ExtractAndBroadcastPcztResult::broadcasted_storage_failed(
            txid.to_string(),
            format!(
                "Broadcast succeeded (txid={txid}) but local storage failed. {storage_err}. \
                 The transaction is on the network; check an explorer to confirm, and do not \
                 attempt to send again until the next sync reconciles your balance."
            ),
        ));
    }

    Ok(ExtractAndBroadcastPcztResult::broadcasted(txid.to_string()))
}
