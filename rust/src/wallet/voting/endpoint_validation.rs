use zcash_voting::Transport;

use crate::wallet::network::WalletNetwork;

static RUSTLS_PROVIDER: std::sync::OnceLock<()> = std::sync::OnceLock::new();

/// Install the Rustls crypto provider for direct Hyper/Rustls validation probes.
fn ensure_rustls_provider() {
    RUSTLS_PROVIDER.get_or_init(|| {
        let _ = rustls::crypto::ring::default_provider().install_default();
    });
}

/// Validate the base URL used for vote commitment tree sync.
///
/// The upstream tree client appends the authenticated `round_id` to the path, so
/// this check keeps the Rust boundary limited to a well-formed base endpoint.
pub fn validate_tree_base_endpoint(base_url: &str, round_id: &str) -> Result<String, String> {
    validate_round_id(round_id)?;
    let endpoint = ParsedEndpoint::parse("vote-tree", base_url)?;
    Ok(endpoint.normalized_base_url)
}

/// Validate a PIR endpoint before any private proof queries are sent.
///
/// This fails closed unless `/root.height` exactly matches the round snapshot.
pub async fn validate_pir_endpoint(
    pir_server_url: &str,
    _network: WalletNetwork,
    round_params: &zcash_voting::VotingRoundParams,
) -> Result<String, String> {
    validate_round_id(&round_params.vote_round_id)?;
    let endpoint = ParsedEndpoint::parse("PIR", pir_server_url)?;
    let root_url = endpoint.child_url("root");
    let expected_height = round_params.snapshot_height;

    ensure_rustls_provider();
    let transport = zcash_voting::HyperTransport::new();
    let response = transport
        .get(&root_url)
        .await
        .map_err(|e| format!("PIR endpoint validation failed: GET /root failed: {e}"))?;
    if response.status != 200 {
        return Err(format!(
            "PIR endpoint validation failed: GET /root returned HTTP {}",
            response.status
        ));
    }

    let root: serde_json::Value = serde_json::from_slice(&response.body)
        .map_err(|e| format!("PIR endpoint validation failed: malformed /root JSON: {e}"))?;
    let reported_height = json_u64(
        &root,
        &[
            "height",
            "root_height",
            "rootHeight",
            "snapshot_height",
            "snapshotHeight",
        ],
    )
    .ok_or_else(|| "PIR endpoint validation failed: /root did not include height".to_string())?;
    if reported_height != expected_height {
        return Err(format!(
            "PIR endpoint validation failed: /root height {reported_height} does not match round snapshot_height {expected_height}"
        ));
    }

    Ok(endpoint.normalized_base_url)
}

#[derive(Clone, Debug)]
struct ParsedEndpoint {
    normalized_base_url: String,
}

impl ParsedEndpoint {
    /// Parse and normalize endpoints without accepting URL features that could
    /// change the upstream request target after validation.
    fn parse(kind: &str, value: &str) -> Result<Self, String> {
        let trimmed = value.trim();
        if trimmed.is_empty() {
            return Err(format!("{kind} endpoint validation failed: URL is empty"));
        }
        let (scheme, rest) = trimmed
            .split_once("://")
            .ok_or_else(|| format!("{kind} endpoint validation failed: URL has no scheme"))?;
        if scheme != "https" && scheme != "http" {
            return Err(format!(
                "{kind} endpoint validation failed: unsupported URL scheme {scheme:?}"
            ));
        }
        if rest.contains('#') || rest.contains('?') {
            return Err(format!(
                "{kind} endpoint validation failed: URL must not include query or fragment"
            ));
        }

        let authority_end = rest.find('/').unwrap_or(rest.len());
        let authority = &rest[..authority_end];
        if authority.is_empty() {
            return Err(format!(
                "{kind} endpoint validation failed: URL has no host"
            ));
        }
        if authority.contains('@') {
            return Err(format!(
                "{kind} endpoint validation failed: URL must not include user info"
            ));
        }

        let normalized_base_url = trimmed.trim_end_matches('/').to_string();
        Ok(Self {
            normalized_base_url,
        })
    }

    fn child_url(&self, child: &str) -> String {
        format!("{}/{}", self.normalized_base_url, child)
    }
}

/// Round IDs are path material for tree/PIR endpoints, so validate them before
/// constructing any upstream request.
fn validate_round_id(round_id: &str) -> Result<(), String> {
    if round_id.len() == 64 && round_id.bytes().all(|b| b.is_ascii_hexdigit()) {
        Ok(())
    } else {
        Err(format!(
            "voting endpoint validation failed: round_id {round_id:?} must be 64 hex characters"
        ))
    }
}

fn json_u64(value: &serde_json::Value, keys: &[&str]) -> Option<u64> {
    keys.iter().find_map(|key| match value.get(*key)? {
        serde_json::Value::Number(number) => number.as_u64(),
        serde_json::Value::String(string) => string.parse::<u64>().ok(),
        _ => None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        io::{Read, Write},
        net::TcpListener,
        thread,
    };

    const ROUND_ID: &str = "0000000000000000000000000000000000000000000000000000000000000001";

    #[test]
    fn tree_endpoint_validation_rejects_unsafe_urls() {
        assert!(validate_tree_base_endpoint("https://node.example", ROUND_ID).is_ok());
        assert!(validate_tree_base_endpoint("ftp://node.example", ROUND_ID).is_err());
        assert!(validate_tree_base_endpoint("https://user@node.example", ROUND_ID).is_err());
        assert!(validate_tree_base_endpoint("https://node.example?x=1", ROUND_ID).is_err());
    }

    #[tokio::test]
    async fn pir_endpoint_validation_accepts_matching_root_metadata() {
        let (server_url, request_path) = start_root_server(
            200,
            serde_json::json!({
                "height": 100,
                "network_id": 0,
                "round_id": ROUND_ID,
                "root29": "unused-by-validation",
            })
            .to_string(),
        );

        let result =
            validate_pir_endpoint(&server_url, WalletNetwork::Test, &test_round_params()).await;

        assert_eq!(result.unwrap(), server_url);
        assert_eq!(request_path.join().unwrap(), "/root");
    }

    #[tokio::test]
    async fn pir_endpoint_validation_accepts_matching_root_without_identity() {
        let (server_url, request_path) =
            start_root_server(200, serde_json::json!({ "height": 100 }).to_string());

        let result =
            validate_pir_endpoint(&server_url, WalletNetwork::Test, &test_round_params()).await;

        assert_eq!(result.unwrap(), server_url);
        assert_eq!(request_path.join().unwrap(), "/root");
    }

    #[tokio::test]
    async fn pir_endpoint_validation_rejects_snapshot_height_mismatch() {
        let (server_url, request_path) = start_root_server(
            200,
            serde_json::json!({
                "height": 99,
                "network_id": 0,
                "round_id": ROUND_ID,
            })
            .to_string(),
        );

        let err = validate_pir_endpoint(&server_url, WalletNetwork::Test, &test_round_params())
            .await
            .unwrap_err();

        assert!(err.contains("height 99"));
        assert!(err.contains("snapshot_height 100"));
        assert_eq!(request_path.join().unwrap(), "/root");
    }

    fn start_root_server(status: u16, body: String) -> (String, thread::JoinHandle<String>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        let request_path = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut request = [0u8; 2048];
            let len = stream.read(&mut request).unwrap();
            let request = String::from_utf8_lossy(&request[..len]);
            let path = request
                .lines()
                .next()
                .and_then(|line| line.split_whitespace().nth(1))
                .unwrap_or("/")
                .to_string();
            let response = format!(
                "HTTP/1.1 {status} OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                body.len(),
                body
            );
            stream.write_all(response.as_bytes()).unwrap();
            path
        });
        (url, request_path)
    }

    fn test_round_params() -> zcash_voting::VotingRoundParams {
        zcash_voting::VotingRoundParams {
            vote_round_id: ROUND_ID.to_string(),
            snapshot_height: 100,
            ea_pk: vec![1; 32],
            nc_root: vec![2; 32],
            nullifier_imt_root: vec![3; 32],
        }
    }
}
