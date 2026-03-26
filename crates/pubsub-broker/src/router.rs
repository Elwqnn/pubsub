use std::collections::HashMap;
use std::sync::Arc;

use tracing::{debug, warn};

use pubsub_core::{Message, SubscriptionId};

use crate::queue_group::QueueGroupSelector;
use crate::registry::SubscriptionRegistry;

/// Result of routing a single message.
#[derive(Debug, Default)]
pub struct RoutingResult {
    pub matched: usize,
    pub delivered: usize,
    pub dropped: usize,
}

/// Routes published messages to matching subscribers.
pub struct Router {
    registry: Arc<SubscriptionRegistry>,
    queue_selector: QueueGroupSelector,
}

impl Router {
    pub fn new(registry: Arc<SubscriptionRegistry>) -> Self {
        Self {
            registry,
            queue_selector: QueueGroupSelector::new(),
        }
    }

    /// Route a message to all matching subscribers.
    ///
    /// For queue groups, only one member per group receives the message.
    /// Uses `try_send` to avoid blocking -- drops messages for slow consumers.
    pub async fn route(&self, message: &Message) -> RoutingResult {
        let matching_sids = self.registry.match_topic(&message.topic).await;
        let mut result = RoutingResult {
            matched: matching_sids.len(),
            ..Default::default()
        };

        if matching_sids.is_empty() {
            return result;
        }

        // Partition subscriptions by queue group.
        let mut direct_sids = Vec::new();
        let mut queue_groups: HashMap<String, Vec<SubscriptionId>> = HashMap::new();

        for sid in &matching_sids {
            match self.registry.get_queue_group(*sid) {
                Some(group) => queue_groups.entry(group).or_default().push(*sid),
                None => direct_sids.push(*sid),
            }
        }

        // Deliver to all non-queue-group subscribers.
        for sid in &direct_sids {
            self.deliver(*sid, message, &mut result);
        }

        // For each queue group, pick one member.
        for members in queue_groups.values() {
            if let Some(selected) = self.queue_selector.select(members) {
                self.deliver(*selected, message, &mut result);
            }
        }

        debug!(
            topic = %message.topic,
            matched = result.matched,
            delivered = result.delivered,
            dropped = result.dropped,
            "message routed"
        );

        result
    }

    fn deliver(&self, sid: SubscriptionId, message: &Message, result: &mut RoutingResult) {
        let Some(sender) = self.registry.get_sender(sid) else {
            return;
        };

        if sender.try_send(message.clone()) {
            result.delivered += 1;
        } else {
            result.dropped += 1;
            warn!(sid = sid.0, topic = %message.topic, "message dropped (backpressure)");
        }
    }
}

#[cfg(test)]
mod tests {
    use bytes::Bytes;
    use tokio::sync::mpsc;

    use pubsub_core::{Subject, SubscriptionSender, TaggedMessage};

    use super::*;

    fn make_sender(sid: SubscriptionId) -> (SubscriptionSender, mpsc::Receiver<TaggedMessage>) {
        let (tx, rx) = mpsc::channel(16);
        (SubscriptionSender::new(sid, tx), rx)
    }

    #[tokio::test]
    async fn route_to_single_subscriber() {
        let registry = Arc::new(SubscriptionRegistry::new());
        let router = Router::new(registry.clone());

        let sid = SubscriptionId(1);
        let (sender, mut rx) = make_sender(sid);
        registry
            .subscribe(Subject::new("test").unwrap(), None, sender)
            .await;

        let msg = Message::new(Subject::new("test").unwrap(), Bytes::from("hello"));
        let result = router.route(&msg).await;

        assert_eq!(result.matched, 1);
        assert_eq!(result.delivered, 1);
        assert_eq!(result.dropped, 0);

        let (recv_sid, recv_msg) = rx.recv().await.unwrap();
        assert_eq!(recv_sid, sid);
        assert_eq!(recv_msg.payload, Bytes::from("hello"));
    }

    #[tokio::test]
    async fn route_fanout_to_multiple() {
        let registry = Arc::new(SubscriptionRegistry::new());
        let router = Router::new(registry.clone());

        let sid1 = SubscriptionId(1);
        let (sender1, mut rx1) = make_sender(sid1);
        let sid2 = SubscriptionId(2);
        let (sender2, mut rx2) = make_sender(sid2);

        registry
            .subscribe(Subject::new("test").unwrap(), None, sender1)
            .await;
        registry
            .subscribe(Subject::new("test").unwrap(), None, sender2)
            .await;

        let msg = Message::new(Subject::new("test").unwrap(), Bytes::from("fan"));
        let result = router.route(&msg).await;

        assert_eq!(result.matched, 2);
        assert_eq!(result.delivered, 2);
        assert!(rx1.recv().await.is_some());
        assert!(rx2.recv().await.is_some());
    }

    #[tokio::test]
    async fn no_match_delivers_nothing() {
        let registry = Arc::new(SubscriptionRegistry::new());
        let router = Router::new(registry.clone());

        let msg = Message::new(Subject::new("nothing").unwrap(), Bytes::from("data"));
        let result = router.route(&msg).await;

        assert_eq!(result.matched, 0);
        assert_eq!(result.delivered, 0);
    }

    #[tokio::test]
    async fn backpressure_drops_message() {
        let registry = Arc::new(SubscriptionRegistry::new());
        let router = Router::new(registry.clone());

        let sid = SubscriptionId(1);
        let (tx, _rx) = mpsc::channel(1); // buffer of 1
        let sender = SubscriptionSender::new(sid, tx);
        registry
            .subscribe(Subject::new("test").unwrap(), None, sender)
            .await;

        let msg = Message::new(Subject::new("test").unwrap(), Bytes::from("a"));

        // First should succeed.
        let r1 = router.route(&msg).await;
        assert_eq!(r1.delivered, 1);

        // Second should be dropped (buffer full).
        let r2 = router.route(&msg).await;
        assert_eq!(r2.dropped, 1);
    }

    #[tokio::test]
    async fn queue_group_delivers_to_one() {
        let registry = Arc::new(SubscriptionRegistry::new());
        let router = Router::new(registry.clone());

        let sid1 = SubscriptionId(1);
        let (sender1, mut rx1) = make_sender(sid1);
        let sid2 = SubscriptionId(2);
        let (sender2, mut rx2) = make_sender(sid2);

        registry
            .subscribe(
                Subject::new("work").unwrap(),
                Some("workers".into()),
                sender1,
            )
            .await;
        registry
            .subscribe(
                Subject::new("work").unwrap(),
                Some("workers".into()),
                sender2,
            )
            .await;

        let msg = Message::new(Subject::new("work").unwrap(), Bytes::from("job"));
        let result = router.route(&msg).await;

        assert_eq!(result.matched, 2);
        assert_eq!(result.delivered, 1); // only one in queue group

        // Exactly one should have received it.
        let got1 = rx1.try_recv().is_ok();
        let got2 = rx2.try_recv().is_ok();
        assert!(got1 ^ got2);
    }
}
