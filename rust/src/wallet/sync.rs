use std::convert::Infallible;
use std::num::NonZeroUsize;

use rand::rngs::OsRng;
use secrecy::{ExposeSecret, SecretVec};
use zcash_client_backend::{
    data_api::{
        Account as _, InputSource, WalletCommitmentTrees, WalletRead, WalletWrite,
        chain::{scan_cached_blocks, CommitmentTreeRoot},
        scanning::ScanPriority,
        wallet::{
            self, ConfirmationsPolicy,
            input_selection::GreedyInputSelector,
            propose_transfer, create_proposed_transactions,
        },
    },
    fees::{
        DustOutputPolicy, SplitPolicy, StandardFeeRule,
        zip317::MultiOutputChangeStrategy,
    },
    proto::service::TreeState,
    wallet::OvkPolicy,
    zip321::{Payment, TransactionRequest},
};
use zcash_client_sqlite::{
    FsBlockDb,
    WalletDb,
    chain::{BlockMeta, init::init_blockmeta_db},
    util::SystemClock,
};
use zcash_keys::keys::UnifiedSpendingKey;
use zcash_primitives::block::BlockHash;
use zcash_proofs::prover::LocalTxProver;
use zcash_protocol::{
    ShieldedProtocol,
    consensus::{BlockHeight, Network},
    memo::{Memo, MemoBytes},
    value::Zatoshis,
};

type WalletDatabase = WalletDb<rusqlite::Connection, Network, SystemClock, OsRng>;

fn open_wallet_db(db_path: &str, network: Network) -> Result<WalletDatabase, String> {
    WalletDb::for_path(db_path, network, SystemClock, OsRng)
        .map_err(|e| format!("Failed to open wallet DB: {e}"))
}

fn open_block_cache(cache_path: &str) -> Result<FsBlockDb, String> {
    std::fs::create_dir_all(cache_path)
        .map_err(|e| format!("Failed to create cache dir: {e}"))?;
    let mut db_cache = FsBlockDb::for_path(cache_path)
        .map_err(|e| format!("Failed to open block cache: {e:?}"))?;
    init_blockmeta_db(&mut db_cache)
        .map_err(|e| format!("Failed to init block cache: {e}"))?;
    Ok(db_cache)
}

fn get_first_account_id(db: &WalletDatabase) -> Result<zcash_client_sqlite::AccountUuid, String> {
    let accounts = db
        .get_account_ids()
        .map_err(|e| format!("Failed to list accounts: {e}"))?;
    accounts
        .into_iter()
        .next()
        .ok_or_else(|| "No accounts found in wallet".to_string())
}

// ======================== Sync ========================

pub fn update_chain_tip(db_path: &str, network: Network, height: u64) -> Result<(), String> {
    let mut db = open_wallet_db(db_path, network)?;
    db.update_chain_tip(BlockHeight::from_u32(height as u32))
        .map_err(|e| format!("Failed to update chain tip: {e}"))
}

pub fn put_sapling_subtree_roots(
    db_path: &str, network: Network, roots: &[(u64, Vec<u8>)],
) -> Result<(), String> {
    let mut db = open_wallet_db(db_path, network)?;
    let parsed: Vec<_> = roots.iter().map(|(h, bytes)| {
        let arr: [u8; 32] = bytes[..32].try_into().map_err(|_| "bad hash len")?;
        let node = Option::from(sapling_crypto::Node::from_bytes(arr)).ok_or("bad sapling hash")?;
        Ok::<_, String>(CommitmentTreeRoot::from_parts(BlockHeight::from_u32(*h as u32), node))
    }).collect::<Result<Vec<_>, _>>()?;
    if !parsed.is_empty() {
        db.put_sapling_subtree_roots(0, parsed.as_slice())
            .map_err(|e| format!("{e}"))?;
    }
    Ok(())
}

pub fn put_orchard_subtree_roots(
    db_path: &str, network: Network, roots: &[(u64, Vec<u8>)],
) -> Result<(), String> {
    let mut db = open_wallet_db(db_path, network)?;
    let parsed: Vec<_> = roots.iter().map(|(h, bytes)| {
        let arr: [u8; 32] = bytes[..32].try_into().map_err(|_| "bad hash len")?;
        let node = Option::from(orchard::tree::MerkleHashOrchard::from_bytes(&arr)).ok_or("bad orchard hash")?;
        Ok::<_, String>(CommitmentTreeRoot::from_parts(BlockHeight::from_u32(*h as u32), node))
    }).collect::<Result<Vec<_>, _>>()?;
    if !parsed.is_empty() {
        db.put_orchard_subtree_roots(0, parsed.as_slice())
            .map_err(|e| format!("{e}"))?;
    }
    Ok(())
}

pub(crate) struct ScanRangeInfo { pub start: u64, pub end: u64, pub priority: u8 }

pub fn suggest_scan_ranges(db_path: &str, network: Network) -> Result<Vec<ScanRangeInfo>, String> {
    let db = open_wallet_db(db_path, network)?;
    let ranges = db.suggest_scan_ranges().map_err(|e| format!("{e}"))?;
    Ok(ranges.into_iter()
        .filter(|r| r.priority() != ScanPriority::Ignored && r.priority() != ScanPriority::Scanned)
        .map(|r| ScanRangeInfo {
            start: u32::from(r.block_range().start) as u64,
            end: u32::from(r.block_range().end) as u64,
            priority: match r.priority() {
                ScanPriority::Verify => 6, ScanPriority::ChainTip => 5,
                ScanPriority::FoundNote => 4, ScanPriority::OpenAdjacent => 3,
                ScanPriority::Historic => 2, ScanPriority::Scanned => 1,
                ScanPriority::Ignored => 0,
            },
        }).collect())
}

pub fn write_block_metadata(cache_path: &str, blocks: &[(u64, Vec<u8>, u32, u32, u32)]) -> Result<(), String> {
    let db_cache = open_block_cache(cache_path)?;
    let metas: Vec<BlockMeta> = blocks.iter().map(|(h, hash, time, sc, oc)| {
        let mut arr = [0u8; 32];
        arr[..hash.len().min(32)].copy_from_slice(&hash[..hash.len().min(32)]);
        BlockMeta { height: BlockHeight::from_u32(*h as u32), block_hash: BlockHash(arr), block_time: *time, sapling_outputs_count: *sc, orchard_actions_count: *oc }
    }).collect();
    db_cache.write_block_metadata(&metas).map_err(|e| format!("{e:?}"))
}

pub fn scan_blocks(
    db_path: &str, cache_path: &str, network: Network, from_height: u64,
    ts_network: &str, ts_height: u64, ts_hash: &str, ts_time: u32, ts_sapling: &str, ts_orchard: &str,
    limit: u64,
) -> Result<u64, String> {
    let db_cache = open_block_cache(cache_path)?;
    let mut db_data = open_wallet_db(db_path, network)?;
    let from_state = if ts_hash.is_empty() {
        zcash_client_backend::data_api::chain::ChainState::empty(
            BlockHeight::from_u32((from_height - 1) as u32), BlockHash([0u8; 32]),
        )
    } else {
        TreeState { network: ts_network.into(), height: ts_height, hash: ts_hash.into(), time: ts_time, sapling_tree: ts_sapling.into(), orchard_tree: ts_orchard.into() }
            .to_chain_state().map_err(|e| format!("{e}"))?
    };
    let result = scan_cached_blocks(&network, &db_cache, &mut db_data, BlockHeight::from_u32(from_height as u32), &from_state, limit as usize)
        .map_err(|e| format!("{e}"))?;
    Ok((u32::from(result.scanned_range().end) - u32::from(result.scanned_range().start)) as u64)
}

// ======================== Balance & Progress ========================

pub(crate) struct SyncProgress { pub scanned_height: u64, pub chain_tip_height: u64, pub is_syncing: bool }

pub fn get_sync_progress(db_path: &str, network: Network) -> Result<SyncProgress, String> {
    let db = open_wallet_db(db_path, network)?;
    match db.get_wallet_summary(ConfirmationsPolicy::default()).map_err(|e| format!("{e}"))? {
        Some(s) => Ok(SyncProgress {
            scanned_height: u32::from(s.fully_scanned_height()) as u64,
            chain_tip_height: u32::from(s.chain_tip_height()) as u64,
            is_syncing: s.fully_scanned_height() < s.chain_tip_height(),
        }),
        None => Ok(SyncProgress { scanned_height: 0, chain_tip_height: 0, is_syncing: false }),
    }
}

pub(crate) struct WalletBalance {
    pub transparent: u64, pub sapling: u64, pub orchard: u64,
    pub sapling_pending: u64, pub orchard_pending: u64,
}

pub fn get_wallet_balance(db_path: &str, network: Network) -> Result<WalletBalance, String> {
    let db = open_wallet_db(db_path, network)?;
    match db.get_wallet_summary(ConfirmationsPolicy::default()).map_err(|e| format!("{e}"))? {
        Some(s) => {
            let (mut t, mut sa, mut or, mut sp, mut op) = (0u64, 0u64, 0u64, 0u64, 0u64);
            for (_, b) in s.account_balances() {
                t += u64::from(b.unshielded_balance().spendable_value());
                sa += u64::from(b.sapling_balance().spendable_value());
                or += u64::from(b.orchard_balance().spendable_value());
                sp += u64::from(b.sapling_balance().change_pending_confirmation()) + u64::from(b.sapling_balance().value_pending_spendability());
                op += u64::from(b.orchard_balance().change_pending_confirmation()) + u64::from(b.orchard_balance().value_pending_spendability());
            }
            Ok(WalletBalance { transparent: t, sapling: sa, orchard: or, sapling_pending: sp, orchard_pending: op })
        }
        None => Ok(WalletBalance { transparent: 0, sapling: 0, orchard: 0, sapling_pending: 0, orchard_pending: 0 }),
    }
}

// ======================== Rewind ========================

pub fn rewind_to_height(db_path: &str, network: Network, height: u64) -> Result<u64, String> {
    let mut db = open_wallet_db(db_path, network)?;
    let result = db.truncate_to_height(BlockHeight::from_u32(height as u32)).map_err(|e| format!("{e}"))?;
    Ok(u32::from(result) as u64)
}

// ======================== Address Validation ========================

pub fn validate_address(address: &str) -> Result<String, String> {
    use zcash_address::ZcashAddress;
    let addr = ZcashAddress::try_from_encoded(address).map_err(|e| format!("Invalid: {e}"))?;
    let debug = format!("{:?}", addr);
    if debug.contains("Unified") { Ok("unified".into()) }
    else if debug.contains("Sapling") { Ok("sapling".into()) }
    else if debug.contains("P2pkh") || debug.contains("P2sh") { Ok("transparent".into()) }
    else { Ok("unknown".into()) }
}

// ======================== Send ========================

pub fn send_to_address(
    db_path: &str, network: Network, seed_bytes: &[u8],
    to_address: &str, amount_zatoshi: u64, memo_str: Option<&str>,
    spend_params_path: &str, output_params_path: &str,
) -> Result<String, String> {
    let mut db = open_wallet_db(db_path, network)?;
    let account_id = get_first_account_id(&db)?;
    let account = db.get_account(account_id).map_err(|e| format!("{e}"))?.ok_or("Account not found")?;

    let seed = SecretVec::new(seed_bytes.to_vec());
    let zip32_index = account.source().key_derivation().ok_or("No key derivation")?.account_index();
    let usk = UnifiedSpendingKey::from_seed(&network, seed.expose_secret(), zip32_index)
        .map_err(|e| format!("USK derivation failed: {e:?}"))?;

    let to: zcash_address::ZcashAddress = to_address.parse().map_err(|e| format!("Bad address: {e}"))?;
    let value = Zatoshis::from_u64(amount_zatoshi).map_err(|_| "Bad amount")?;
    let memo_bytes = match memo_str {
        Some(m) => {
            let bytes = MemoBytes::from(Memo::from_bytes(m.as_bytes()).map_err(|e| format!("Bad memo: {e}"))?);
            Some(bytes)
        }
        None => None,
    };

    let (change_strategy, input_selector) = zip317_helper::<WalletDatabase>(None);
    let payment = Payment::new(to, value, memo_bytes, None, None, vec![])
        .ok_or("Cannot send memo to this address type")?;
    let request = TransactionRequest::new(vec![payment]).map_err(|e| format!("{e:?}"))?;

    let proposal = propose_transfer::<_, _, _, _, Infallible>(
        &mut db, &network, account_id, &input_selector, &change_strategy,
        request, ConfirmationsPolicy::default(),
    ).map_err(|e| format!("Propose failed: {e}"))?;

    let prover = LocalTxProver::new(
        std::path::Path::new(spend_params_path),
        std::path::Path::new(output_params_path),
    );

    let txids = create_proposed_transactions::<_, _, Infallible, _, Infallible, _>(
        &mut db, &network, &prover, &prover,
        &wallet::SpendingKeys::from_unified_spending_key(usk),
        OvkPolicy::Sender, &proposal,
    ).map_err(|e| format!("Create TX failed: {e}"))?;

    Ok(txids.into_iter().map(|id| format!("{id}")).collect::<Vec<_>>().join(","))
}

// ======================== Diversified Address ========================

pub fn get_next_available_address(db_path: &str, network: Network) -> Result<String, String> {
    use zcash_keys::keys::{ReceiverRequirement, UnifiedAddressRequest};
    let mut db = open_wallet_db(db_path, network)?;
    let account_id = get_first_account_id(&db)?;
    let req = UnifiedAddressRequest::custom(
        ReceiverRequirement::Require, ReceiverRequirement::Require, ReceiverRequirement::Omit,
    ).map_err(|_| "bad request")?;
    let (ua, _) = db.get_next_available_address(account_id, req)
        .map_err(|e| format!("{e}"))?.ok_or("No address available")?;
    Ok(ua.encode(&network))
}

// ======================== Helpers ========================

pub fn get_blocks_dir(cache_path: &str) -> String {
    format!("{cache_path}/blocks")
}

fn zip317_helper<DbT: InputSource>(
    change_memo: Option<MemoBytes>,
) -> (MultiOutputChangeStrategy<StandardFeeRule, DbT>, GreedyInputSelector<DbT>) {
    (
        MultiOutputChangeStrategy::new(
            StandardFeeRule::Zip317, change_memo, ShieldedProtocol::Orchard,
            DustOutputPolicy::default(),
            SplitPolicy::with_min_output_value(NonZeroUsize::new(4).unwrap(), Zatoshis::const_from_u64(1000_0000)),
        ),
        GreedyInputSelector::new(),
    )
}
