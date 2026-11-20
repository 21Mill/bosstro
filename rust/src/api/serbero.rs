//! Serbero, the assistant Read solver (D13): which pubkey the solver trusts
//! as Serbero on each node.
//!
//! Serbero mediates with its own key, so Bosstro cannot open its chat with
//! the parties. At handoff it sends the brief and the transcript to the
//! solver key as `send-dm` messages; those are read only from the pubkey
//! kept here, one per node (D6), and never treated as protocol actions.

use anyhow::{bail, Result};

use crate::api::nodes::parse_node_pubkey;
use crate::db::{settings_keys, Storage};

/// The Serbero pubkey trusted on `node`, as an npub to show, or `None` when
/// none is set.
pub async fn get_serbero_npub(node: String) -> Result<Option<String>> {
    match crate::db::app_db::db() {
        Some(db) => read_serbero(db, &node)
            .await?
            .map(|hex| npub(&hex))
            .transpose(),
        None => Ok(None),
    }
}

/// Trust `pubkey` (hex or `npub1…`) as Serbero on `node`, or stop trusting
/// any with `None`. Returns it as an npub to show.
///
/// **Errors**: `PrivateKeyNotAllowed`, `InvalidPubkey`, `SerberoIsNode` (the
/// node's own key), `NotInitialized`, or a storage failure.
pub async fn set_serbero_pubkey(node: String, pubkey: Option<String>) -> Result<Option<String>> {
    let Some(db) = crate::db::app_db::db() else {
        bail!("NotInitialized: storage is not ready");
    };
    write_serbero(db, &node, pubkey.as_deref())
        .await?
        .map(|hex| npub(&hex))
        .transpose()
}

fn npub(hex: &str) -> Result<String> {
    use nostr_sdk::prelude::{PublicKey, ToBech32};
    Ok(PublicKey::from_hex(hex)?.to_bech32()?)
}

async fn read_serbero(db: &impl Storage, node: &str) -> Result<Option<String>> {
    Ok(db
        .get_setting(&settings_keys::serbero_pubkey(node))
        .await?
        .and_then(|stored| parse_node_pubkey(&stored).ok()))
}

async fn write_serbero(
    db: &impl Storage,
    node: &str,
    pubkey: Option<&str>,
) -> Result<Option<String>> {
    let key = settings_keys::serbero_pubkey(node);
    let Some(input) = pubkey.filter(|p| !p.trim().is_empty()) else {
        db.delete_setting(&key).await?;
        return Ok(None);
    };
    let hex = parse_node_pubkey(input)?;
    if hex == node {
        bail!("SerberoIsNode: the node's own key cannot be Serbero");
    }
    db.set_setting(&key, &hex).await?;
    Ok(Some(hex))
}

#[cfg(all(test, not(target_arch = "wasm32")))]
mod tests {
    use super::*;
    use nostr_sdk::prelude::{Keys, ToBech32};

    #[tokio::test]
    async fn none_is_trusted_until_one_is_set() {
        let db = crate::db::sqlite::tests::store().await;
        let node = Keys::generate().public_key().to_hex();
        assert_eq!(read_serbero(&db, &node).await.unwrap(), None);
    }

    #[tokio::test]
    async fn an_npub_is_kept_as_hex_per_node_and_cleared() {
        let db = crate::db::sqlite::tests::store().await;
        let node = Keys::generate().public_key().to_hex();
        let other = Keys::generate().public_key().to_hex();
        let serbero = Keys::generate().public_key();
        let stored = write_serbero(&db, &node, Some(&serbero.to_bech32().unwrap()))
            .await
            .unwrap();
        assert_eq!(stored, Some(serbero.to_hex()));
        assert_eq!(
            read_serbero(&db, &node).await.unwrap(),
            Some(serbero.to_hex())
        );
        assert_eq!(
            read_serbero(&db, &other).await.unwrap(),
            None,
            "per node (D6)"
        );
        assert_eq!(write_serbero(&db, &node, None).await.unwrap(), None);
        assert_eq!(read_serbero(&db, &node).await.unwrap(), None);
    }

    #[tokio::test]
    async fn a_blank_input_clears() {
        let db = crate::db::sqlite::tests::store().await;
        let node = Keys::generate().public_key().to_hex();
        let serbero = Keys::generate().public_key().to_hex();
        write_serbero(&db, &node, Some(&serbero)).await.unwrap();
        assert_eq!(write_serbero(&db, &node, Some("  ")).await.unwrap(), None);
        assert_eq!(read_serbero(&db, &node).await.unwrap(), None);
    }

    #[tokio::test]
    async fn bad_inputs_are_refused_and_change_nothing() {
        let db = crate::db::sqlite::tests::store().await;
        let node = Keys::generate().public_key().to_hex();
        let serbero = Keys::generate().public_key().to_hex();
        write_serbero(&db, &node, Some(&serbero)).await.unwrap();
        let nsec = Keys::generate().secret_key().to_bech32().unwrap();
        for (input, marker) in [
            ("not a key", "InvalidPubkey"),
            (nsec.as_str(), "PrivateKeyNotAllowed"),
            (node.as_str(), "SerberoIsNode"),
        ] {
            let error = write_serbero(&db, &node, Some(input)).await.unwrap_err();
            assert!(error.to_string().starts_with(marker), "{input}: {error}");
        }
        assert_eq!(read_serbero(&db, &node).await.unwrap(), Some(serbero));
    }
}
