use super::state::ensure_voting_table;

pub fn derive_hotkey(conn: &rusqlite::Connection) -> ! {
    ensure_voting_table(conn).expect("voting_round_state table migration failed");
    unimplemented!()
}
