pub fn ensure_voting_table(conn: &rusqlite::Connection) -> Result<(), String> {
    conn.execute_batch(
        r#"
        CREATE TABLE IF NOT EXISTS voting_round_state (
          round_id TEXT NOT NULL,
          account_uuid TEXT NOT NULL,
          snapshot_height INTEGER NOT NULL,
          hotkey_blob BLOB,
          delegation_state TEXT,
          signed_pczt BLOB,
          signed_bundle_signatures BLOB,
          vote_commitments TEXT,
          submission_state TEXT,
          updated_at INTEGER NOT NULL,
          PRIMARY KEY (round_id, account_uuid)
        );
        "#,
    )
    .map_err(|e| format!("Failed to ensure voting_round_state table: {e}"))
}

pub fn load_round_state(conn: &rusqlite::Connection) -> ! {
    ensure_voting_table(conn).expect("voting_round_state table migration failed");
    unimplemented!()
}

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::{params, OptionalExtension};

    #[test]
    fn voting_round_state_create_and_drop() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let conn = rusqlite::Connection::open(db_path).unwrap();

        ensure_voting_table(&conn).unwrap();
        ensure_voting_table(&conn).unwrap();

        let exists: Option<String> = conn
            .query_row(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'voting_round_state'",
                [],
                |row| row.get(0),
            )
            .optional()
            .unwrap();
        assert_eq!(exists.as_deref(), Some("voting_round_state"));

        conn.execute("DROP TABLE voting_round_state", []).unwrap();

        let exists_after_drop: Option<String> = conn
            .query_row(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'voting_round_state'",
                [],
                |row| row.get(0),
            )
            .optional()
            .unwrap();
        assert!(exists_after_drop.is_none());
    }

    #[test]
    fn voting_round_state_roundtrip() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("zcash_wallet.db");
        let conn = rusqlite::Connection::open(db_path).unwrap();
        ensure_voting_table(&conn).unwrap();

        let hotkey_blob = vec![1_u8, 2, 3];
        let signed_pczt = vec![4_u8, 5, 6];
        let signed_bundle_signatures = vec![7_u8, 8, 9];

        conn.execute(
            r#"
            INSERT INTO voting_round_state (
              round_id,
              account_uuid,
              snapshot_height,
              hotkey_blob,
              delegation_state,
              signed_pczt,
              signed_bundle_signatures,
              vote_commitments,
              submission_state,
              updated_at
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
            "#,
            params![
                "round-1",
                "550e8400-e29b-41d4-a716-446655440000",
                2_500_000_i64,
                hotkey_blob,
                r#"{"delegated":true}"#,
                signed_pczt,
                signed_bundle_signatures,
                r#"["commitment-1"]"#,
                r#"{"submitted":false}"#,
                1_778_513_280_i64,
            ],
        )
        .unwrap();

        let row = conn
            .query_row(
                r#"
                SELECT
                  round_id,
                  account_uuid,
                  snapshot_height,
                  hotkey_blob,
                  delegation_state,
                  signed_pczt,
                  signed_bundle_signatures,
                  vote_commitments,
                  submission_state,
                  updated_at
                FROM voting_round_state
                WHERE round_id = ?1 AND account_uuid = ?2
                "#,
                params!["round-1", "550e8400-e29b-41d4-a716-446655440000"],
                |row| {
                    Ok((
                        row.get::<_, String>(0)?,
                        row.get::<_, String>(1)?,
                        row.get::<_, i64>(2)?,
                        row.get::<_, Vec<u8>>(3)?,
                        row.get::<_, String>(4)?,
                        row.get::<_, Vec<u8>>(5)?,
                        row.get::<_, Vec<u8>>(6)?,
                        row.get::<_, String>(7)?,
                        row.get::<_, String>(8)?,
                        row.get::<_, i64>(9)?,
                    ))
                },
            )
            .unwrap();

        assert_eq!(row.0, "round-1");
        assert_eq!(row.1, "550e8400-e29b-41d4-a716-446655440000");
        assert_eq!(row.2, 2_500_000);
        assert_eq!(row.3, vec![1, 2, 3]);
        assert_eq!(row.4, r#"{"delegated":true}"#);
        assert_eq!(row.5, vec![4, 5, 6]);
        assert_eq!(row.6, vec![7, 8, 9]);
        assert_eq!(row.7, r#"["commitment-1"]"#);
        assert_eq!(row.8, r#"{"submitted":false}"#);
        assert_eq!(row.9, 1_778_513_280);
    }
}
