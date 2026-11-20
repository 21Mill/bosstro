//! Serbero's reports to the loaded key, followed live: one kind 14
//! subscription authored by the Serbero pubkey trusted on the active node and
//! `p`-tagged to the loaded key, kept alive by `nostr::live_subs`, beside the
//! node's answers (`mostro::replies`) and the chats (`chat::router`).
//!
//! It reaches [`BACKLOG_SECS`] back, so a handoff sent while the app was
//! closed still arrives; storage keeps one row per event, so the backlog read
//! again on each start stores nothing twice. Without a trusted Serbero pubkey
//! there is no subscription, and nothing is read or kept.

use std::sync::{Arc, Mutex, OnceLock};

use nostr_sdk::prelude::{
    Client, ClientNotification, Event, Keys, Kind, PublicKey, RelayMessage, StreamExt,
    SubscriptionId, Timestamp,
};
use tokio::sync::{broadcast, mpsc};

use super::intake::{accept, reports_filter, BACKLOG_SECS};
use super::{SerberoRecord, SerberoRef};
use crate::db::Storage;
use crate::nostr::live_subs::LiveSubs;

/// How many updates a slow reader may fall behind before it reads again.
const UPDATE_CAPACITY: usize = 64;

/// A dispute whose Serbero reports changed on a node.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct SerberoUpdate {
    pub mostro_pubkey: String,
    pub dispute_id: String,
}

#[derive(Clone)]
struct Target {
    node: PublicKey,
    keys: Keys,
    serbero: PublicKey,
    sub: SubscriptionId,
}

impl Target {
    fn same_as(&self, other: &Target) -> bool {
        self.node == other.node
            && self.keys.public_key() == other.keys.public_key()
            && self.serbero == other.serbero
    }
}

/// The subscription id of `serbero` and `solver` (both hex), within NIP-01's
/// 64 characters.
fn subscription_id(serbero: &str, solver: &str) -> SubscriptionId {
    let short = |s: &str| s.chars().take(16).collect::<String>();
    SubscriptionId::new(format!("serbero-{}-{}", short(serbero), short(solver)))
}

fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
}

pub(crate) struct Router {
    client: Arc<Client>,
    subs: &'static LiveSubs,
    target: Mutex<Option<Target>>,
    /// Serialises retargets, each closing the previous subscription.
    retarget_lock: tokio::sync::Mutex<()>,
}

impl Router {
    pub(crate) fn new(client: Arc<Client>, subs: &'static LiveSubs) -> Arc<Self> {
        Arc::new(Self {
            client,
            subs,
            target: Mutex::new(None),
            retarget_lock: tokio::sync::Mutex::new(()),
        })
    }

    /// Read the client's notifications for as long as it lives, passing on
    /// only the kind 14 events of the current subscription, in order; a
    /// second task opens and stores them (as `mostro::replies`).
    fn spawn_reader(self: &Arc<Self>) {
        let (tx, mut rx) = mpsc::unbounded_channel::<Box<Event>>();
        let mut notifications = self.client.notifications();
        let router = self.clone();
        crate::rt::spawn(async move {
            while let Some(notification) = notifications.next().await {
                let ClientNotification::Message { message, .. } = notification else {
                    continue;
                };
                let RelayMessage::Event {
                    subscription_id,
                    event,
                } = *message
                else {
                    continue;
                };
                if event.kind != Kind::PrivateDirectMessage
                    || router.current_sub().as_ref() != Some(subscription_id.as_ref())
                {
                    continue;
                }
                if tx.send(Box::new(event.into_owned())).is_err() {
                    break;
                }
            }
        });
        let router = self.clone();
        crate::rt::spawn(async move {
            while let Some(event) = rx.recv().await {
                let Some(db) = crate::db::app_db::db() else {
                    continue;
                };
                router.handle(db, &event).await;
            }
        });
    }

    fn current_sub(&self) -> Option<SubscriptionId> {
        lock(&self.target).as_ref().map(|t| t.sub.clone())
    }

    /// Follow `serbero`'s reports to `keys` on `node`, or nothing. Following
    /// what it already follows changes nothing.
    pub(crate) async fn retarget(
        &self,
        node: Option<PublicKey>,
        keys: Option<Keys>,
        serbero: Option<PublicKey>,
    ) {
        let _guard = self.retarget_lock.lock().await;
        let next = match (node, keys, serbero) {
            (Some(node), Some(keys), Some(serbero)) => Some(Target {
                sub: subscription_id(&serbero.to_hex(), &keys.public_key().to_hex()),
                node,
                keys,
                serbero,
            }),
            _ => None,
        };
        let previous = {
            let mut target = lock(&self.target);
            let same = match (&*target, &next) {
                (Some(a), Some(b)) => a.same_as(b),
                (None, None) => true,
                _ => false,
            };
            if same {
                return;
            }
            std::mem::replace(&mut *target, next.clone())
        };
        if let Some(previous) = previous {
            self.subs.close(&self.client, &previous.sub).await;
        }
        let Some(target) = next else {
            return;
        };
        let since =
            Timestamp::from_secs((crate::rt::unix_now().max(0) as u64).saturating_sub(BACKLOG_SECS));
        let filter = reports_filter(&target.serbero, &target.keys.public_key(), since);
        if let Err(e) = self
            .subs
            .replace(&self.client, target.sub.clone(), filter)
            .await
        {
            log::warn!("[serbero] subscribe {} failed: {e}", target.sub);
        }
    }

    /// One kind 14 of the current subscription: kept when it is a report of
    /// the trusted Serbero to the loaded key. Returns the update it made.
    pub(crate) async fn handle(&self, db: &impl Storage, event: &Event) -> Option<SerberoUpdate> {
        let target = lock(&self.target).clone()?;
        let accepted = accept(&target.keys, &target.serbero, event).await?;
        let record = SerberoRecord {
            conversation: SerberoRef {
                mostro_pubkey: target.node.to_hex(),
                dispute_id: accepted.report.dispute_id.clone(),
                solver_pubkey: target.keys.public_key().to_hex(),
            },
            event_id: accepted.event_id,
            serbero_pubkey: target.serbero.to_hex(),
            content: format!(
                "Dispute {} · {}\n{}",
                accepted.report.dispute_id, accepted.report.subject, accepted.report.body
            ),
            created_at: accepted.created_at,
            received_at: crate::rt::unix_now(),
        };
        // A retarget while it was opened: the report is not this target's.
        if !lock(&self.target).as_ref().is_some_and(|t| t.same_as(&target)) {
            return None;
        }
        match db.insert_serbero_message(&record).await {
            Ok(true) => {}
            Ok(false) => return None,
            Err(e) => {
                log::warn!("[serbero] a report was not stored: {e}");
                return None;
            }
        }
        let update = SerberoUpdate {
            mostro_pubkey: record.conversation.mostro_pubkey,
            dispute_id: record.conversation.dispute_id,
        };
        let _ = updates().send(update.clone());
        Some(update)
    }
}

static ROUTER: OnceLock<Arc<Router>> = OnceLock::new();

fn updates() -> &'static broadcast::Sender<SerberoUpdate> {
    static UPDATES: OnceLock<broadcast::Sender<SerberoUpdate>> = OnceLock::new();
    UPDATES.get_or_init(|| broadcast::channel(UPDATE_CAPACITY).0)
}

/// Every report stored from now on, as the dispute it changed.
pub(crate) fn subscribe_updates() -> broadcast::Receiver<SerberoUpdate> {
    updates().subscribe()
}

/// Start the router on the relay pool's client. Called once the pool
/// exists; later calls only re-point it.
pub(crate) async fn start(client: Arc<Client>) {
    let router = ROUTER.get_or_init(|| {
        let router = Router::new(client, crate::nostr::live_subs::live_subs());
        router.spawn_reader();
        router
    });
    follow_with(router).await;
}

/// Re-point the router at the active node, the loaded key and the Serbero
/// pubkey trusted on that node, after any of them changes. A no-op before
/// the pool started.
pub(crate) async fn follow() {
    if let Some(router) = ROUTER.get() {
        follow_with(router).await;
    }
}

async fn follow_with(router: &Router) {
    let keys = crate::solver_slot::SOLVER_SLOT.keys().await;
    let node = crate::config::active_mostro_pubkey();
    let serbero = match (&node, crate::db::app_db::db()) {
        (Some(node), Some(db)) => crate::api::serbero::trusted_serbero(db, node)
            .await
            .ok()
            .flatten(),
        _ => None,
    };
    let parse = |hex: Option<String>| hex.and_then(|h| PublicKey::from_hex(&h).ok());
    router.retarget(parse(node), keys, parse(serbero)).await;
}

#[cfg(all(test, not(target_arch = "wasm32")))]
mod tests {
    use super::*;
    use crate::serbero::intake::tests::{serbero_dm, transcript_text, DISPUTE};

    async fn router_for(node: &Keys, solver: &Keys, serbero: &Keys) -> Arc<Router> {
        let router = Router::new(Arc::new(Client::new()), crate::nostr::live_subs::live_subs());
        router
            .retarget(
                Some(node.public_key()),
                Some(solver.clone()),
                Some(serbero.public_key()),
            )
            .await;
        router
    }

    #[tokio::test]
    async fn a_report_is_stored_once_for_the_node_and_key() {
        let db = crate::db::sqlite::tests::store().await;
        let (node, solver, serbero) = (Keys::generate(), Keys::generate(), Keys::generate());
        let router = router_for(&node, &solver, &serbero).await;
        let event = serbero_dm(&serbero, &solver.public_key(), &transcript_text());

        let update = router.handle(&db, &event).await;
        assert_eq!(
            update,
            Some(SerberoUpdate {
                mostro_pubkey: node.public_key().to_hex(),
                dispute_id: DISPUTE.into(),
            })
        );
        assert_eq!(router.handle(&db, &event).await, None, "a copy");

        let rows = db
            .list_serbero_messages(&SerberoRef {
                mostro_pubkey: node.public_key().to_hex(),
                dispute_id: DISPUTE.into(),
                solver_pubkey: solver.public_key().to_hex(),
            })
            .await
            .unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].event_id, event.id.to_hex());
        assert_eq!(rows[0].serbero_pubkey, serbero.public_key().to_hex());
        assert_eq!(rows[0].content, transcript_text());
    }

    #[tokio::test]
    async fn without_a_trusted_serbero_nothing_is_kept() {
        let db = crate::db::sqlite::tests::store().await;
        let (node, solver, serbero) = (Keys::generate(), Keys::generate(), Keys::generate());
        let router = Router::new(Arc::new(Client::new()), crate::nostr::live_subs::live_subs());
        router
            .retarget(Some(node.public_key()), Some(solver.clone()), None)
            .await;
        let event = serbero_dm(&serbero, &solver.public_key(), &transcript_text());
        assert_eq!(router.handle(&db, &event).await, None);
    }

    #[tokio::test]
    async fn a_report_from_an_untrusted_key_is_not_kept() {
        let db = crate::db::sqlite::tests::store().await;
        let (node, solver, serbero, other) = (
            Keys::generate(),
            Keys::generate(),
            Keys::generate(),
            Keys::generate(),
        );
        let router = router_for(&node, &solver, &serbero).await;
        let event = serbero_dm(&other, &solver.public_key(), &transcript_text());
        assert_eq!(router.handle(&db, &event).await, None);
    }
}
