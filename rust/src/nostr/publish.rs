//! Publishing an event without waiting for the slowest relay.
//!
//! `Client::send_event` returns only when every relay of the pool has
//! acknowledged the event, refused it or timed out (nostr-sdk waits ten
//! seconds for each `OK`). One relay that is slow, or never answers, makes
//! every send as slow as it is, although the event was on the other relays
//! long before.
//!
//! [`publish`] sends to every connected relay at once and returns at the
//! **first** one that takes the event. The others keep being sent to in the
//! background, so the event still reaches each of them.

use futures_util::stream::{FuturesUnordered, StreamExt};
use nostr_sdk::prelude::*;
use tokio::sync::oneshot;

/// How publishing an event went.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Published {
    /// A relay took it.
    Taken,
    /// It was sent to the connected relays and none took it: each refused
    /// it, timed out or dropped the connection. A relay that did not answer
    /// may still have it.
    Unconfirmed,
    /// No relay is connected: nothing was sent.
    NoRelay,
}

/// Send `event` to every connected relay and return as soon as one takes it,
/// or when all of them have ended without taking it.
pub(crate) async fn publish(client: &Client, event: &Event) -> Published {
    let urls: Vec<RelayUrl> = client
        .relays()
        .await
        .into_iter()
        .filter(|(_, relay)| relay.status() == RelayStatus::Connected)
        .map(|(url, _)| url)
        .collect();
    if urls.is_empty() {
        return Published::NoRelay;
    }

    let (first, taken) = oneshot::channel();
    let (client, event) = (client.clone(), event.clone());
    // On its own task: the relays that have not answered yet are still sent
    // to after this returns.
    crate::rt::spawn(async move {
        let sends = urls.iter().map(|url| send_to(&client, &event, url));
        until_all_ended(sends, first).await;
    });
    match taken.await {
        Ok(()) => Published::Taken,
        Err(_) => Published::Unconfirmed,
    }
}

/// Send `event` to one relay and wait for its `OK`: whether it took it.
async fn send_to(client: &Client, event: &Event, url: &RelayUrl) -> bool {
    match client.send_event(event).to([url]).await {
        Ok(output) if !output.success.is_empty() => true,
        Ok(output) => {
            for why in output.failed.values() {
                log::warn!("[publish] {url} did not take the event: {why}");
            }
            false
        }
        Err(e) => {
            log::warn!("[publish] not sent to {url}: {e}");
            false
        }
    }
}

/// Run every send to its end. `first` is told at the first one that
/// succeeds; when none does it is dropped, which tells that too.
async fn until_all_ended<I, F>(sends: I, first: oneshot::Sender<()>)
where
    I: IntoIterator<Item = F>,
    F: std::future::Future<Output = bool>,
{
    let mut sends: FuturesUnordered<F> = sends.into_iter().collect();
    let mut first = Some(first);
    while let Some(took) = sends.next().await {
        if took {
            if let Some(first) = first.take() {
                let _ = first.send(());
            }
        }
    }
}

#[cfg(all(test, not(target_arch = "wasm32")))]
pub(crate) mod tests {
    use super::*;
    use nostr_sdk::local_relay::{LocalRelay, MockRelay, WritePolicy, WritePolicyResult};
    use std::future::Future;
    use std::net::SocketAddr;
    use std::pin::Pin;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;
    use std::time::{Duration, Instant};

    /// A relay that takes an event and answers nothing for `0`: longer than
    /// any test waits.
    #[derive(Debug)]
    struct Silent(Duration);

    impl WritePolicy for Silent {
        fn admit_event<'a>(
            &'a self,
            _event: &'a Event,
            _addr: &'a SocketAddr,
        ) -> Pin<Box<dyn Future<Output = WritePolicyResult> + Send + 'a>> {
            Box::pin(async move {
                tokio::time::sleep(self.0).await;
                WritePolicyResult::Accept
            })
        }
    }

    /// A relay that never acknowledges an event within a test.
    pub(crate) async fn silent_relay() -> LocalRelay {
        slow_relay(Duration::from_secs(3600)).await
    }

    /// A relay that acknowledges an event only after `delay`.
    pub(crate) async fn slow_relay(delay: Duration) -> LocalRelay {
        let relay = LocalRelay::builder().write_policy(Silent(delay)).build();
        relay.run().await.unwrap();
        relay
    }

    /// A relay that answers every direct message with a refusal.
    pub(crate) async fn refusing_relay() -> LocalRelay {
        let relay = LocalRelay::builder()
            .blacklist_kinds(&[Kind::PrivateDirectMessage])
            .build();
        relay.run().await.unwrap();
        relay
    }

    /// Add `url` to `client` and connect to it.
    pub(crate) async fn connect(client: &Client, url: &RelayUrl) {
        client.add_relay(url).await.unwrap();
        client
            .try_connect_relay(url, Duration::from_secs(3))
            .await
            .unwrap();
    }

    fn note() -> Event {
        EventBuilder::new(Kind::TextNote, "hello")
            .finalize(&Keys::generate())
            .unwrap()
    }

    // ── The race ─────────────────────────────────────────────────────────

    type Sending = Pin<Box<dyn Future<Output = bool> + Send>>;

    fn ends(after_ms: u64, took: bool, ended: &Arc<AtomicUsize>) -> Sending {
        let ended = ended.clone();
        Box::pin(async move {
            tokio::time::sleep(Duration::from_millis(after_ms)).await;
            ended.fetch_add(1, Ordering::SeqCst);
            took
        })
    }

    #[tokio::test]
    async fn the_first_relay_that_takes_it_is_told_and_the_others_still_end() {
        let ended = Arc::new(AtomicUsize::new(0));
        let sends = vec![
            ends(400, true, &ended),
            ends(20, false, &ended),
            ends(60, true, &ended),
        ];
        let (first, taken) = oneshot::channel();
        let all = tokio::spawn(until_all_ended(sends, first));
        let started = Instant::now();

        assert_eq!(taken.await, Ok(()));
        assert!(
            started.elapsed() < Duration::from_millis(300),
            "told at the first relay that took it, not at the last"
        );
        assert_eq!(ended.load(Ordering::SeqCst), 2, "the slow one is pending");

        all.await.unwrap();
        assert_eq!(ended.load(Ordering::SeqCst), 3, "and it was not dropped");
    }

    #[tokio::test]
    async fn no_relay_taking_it_is_told_when_the_last_one_ended() {
        let ended = Arc::new(AtomicUsize::new(0));
        let sends = vec![ends(20, false, &ended), ends(80, false, &ended)];
        let (first, taken) = oneshot::channel();
        tokio::spawn(until_all_ended(sends, first));

        assert!(taken.await.is_err());
        assert_eq!(ended.load(Ordering::SeqCst), 2);
    }

    // ── Against relays ───────────────────────────────────────────────────

    #[tokio::test]
    async fn a_relay_that_never_acknowledges_does_not_hold_the_send() {
        let fast = MockRelay::run().await.unwrap();
        let silent = silent_relay().await;
        let client = Client::new();
        connect(&client, &fast.url().await).await;
        connect(&client, &silent.url().await).await;
        let started = Instant::now();

        assert_eq!(publish(&client, &note()).await, Published::Taken);
        assert!(
            started.elapsed() < Duration::from_secs(3),
            "returned at the first OK, not after the silent relay's timeout"
        );
    }

    #[tokio::test]
    async fn the_slow_relay_still_gets_the_event() {
        let fast = MockRelay::run().await.unwrap();
        let slow = slow_relay(Duration::from_millis(600)).await;
        let client = Client::new();
        connect(&client, &fast.url().await).await;
        connect(&client, &slow.url().await).await;
        let event = note();

        assert_eq!(publish(&client, &event).await, Published::Taken);

        // Asked alone, a while after the send returned.
        tokio::time::sleep(Duration::from_millis(1500)).await;
        let reader = Client::new();
        connect(&reader, &slow.url().await).await;
        let held = reader
            .fetch_events(Filter::new().id(event.id))
            .timeout(Duration::from_secs(3))
            .await
            .unwrap();
        assert_eq!(held.len(), 1, "the slow relay was not abandoned");
    }

    #[tokio::test]
    async fn with_no_relay_connected_nothing_is_sent() {
        let relay = MockRelay::run().await.unwrap();
        let client = Client::new();
        connect(&client, &relay.url().await).await;
        client.disconnect().await;

        assert_eq!(publish(&client, &note()).await, Published::NoRelay);
        // No relay at all reads the same.
        assert_eq!(publish(&Client::new(), &note()).await, Published::NoRelay);
    }

    #[tokio::test]
    async fn an_event_every_relay_refuses_is_unconfirmed() {
        let relay = LocalRelay::builder()
            .blacklist_kinds(&[Kind::TextNote])
            .build();
        relay.run().await.unwrap();
        let client = Client::new();
        connect(&client, &relay.url().await).await;

        assert_eq!(publish(&client, &note()).await, Published::Unconfirmed);
    }
}
