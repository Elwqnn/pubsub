use bytes::Bytes;
use serde::{Deserialize, Deserializer, Serialize, Serializer};

/// Current wire protocol version.
pub const PROTOCOL_VERSION: u8 = 1;

/// A frame on the wire. This is the unit of communication between client and broker.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Frame {
    /// Client -> Broker: publish a message to a topic.
    Publish {
        topic: String,
        payload: Bytes,
        reply_to: Option<String>,
    },

    /// Client -> Broker: subscribe to a subject pattern.
    Subscribe {
        sid: u64,
        subject: String,
        queue_group: Option<String>,
    },

    /// Client -> Broker: unsubscribe from a subscription.
    Unsubscribe { sid: u64 },

    /// Broker -> Client: deliver a message to a subscriber.
    Message {
        topic: String,
        sid: u64,
        payload: Bytes,
        reply_to: Option<String>,
    },

    /// Bidirectional: keepalive ping.
    Ping,

    /// Bidirectional: keepalive pong.
    Pong,

    /// Broker -> Client: operation succeeded.
    Ok,

    /// Broker -> Client: operation failed.
    Err { message: String },
}

// Custom serde to handle Bytes as Vec<u8> for msgpack compatibility.
impl Serialize for Frame {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        FrameHelper::from(self).serialize(serializer)
    }
}

impl<'de> Deserialize<'de> for Frame {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        FrameHelper::deserialize(deserializer).map(Frame::from)
    }
}

/// Serde-friendly mirror of Frame that uses Vec<u8> instead of Bytes.
#[derive(Serialize, Deserialize)]
enum FrameHelper {
    Publish {
        topic: String,
        payload: Vec<u8>,
        reply_to: Option<String>,
    },
    Subscribe {
        sid: u64,
        subject: String,
        queue_group: Option<String>,
    },
    Unsubscribe {
        sid: u64,
    },
    Message {
        topic: String,
        sid: u64,
        payload: Vec<u8>,
        reply_to: Option<String>,
    },
    Ping,
    Pong,
    Ok,
    Err {
        message: String,
    },
}

impl From<&Frame> for FrameHelper {
    fn from(frame: &Frame) -> Self {
        match frame {
            Frame::Publish {
                topic,
                payload,
                reply_to,
            } => FrameHelper::Publish {
                topic: topic.clone(),
                payload: payload.to_vec(),
                reply_to: reply_to.clone(),
            },
            Frame::Subscribe {
                sid,
                subject,
                queue_group,
            } => FrameHelper::Subscribe {
                sid: *sid,
                subject: subject.clone(),
                queue_group: queue_group.clone(),
            },
            Frame::Unsubscribe { sid } => FrameHelper::Unsubscribe { sid: *sid },
            Frame::Message {
                topic,
                sid,
                payload,
                reply_to,
            } => FrameHelper::Message {
                topic: topic.clone(),
                sid: *sid,
                payload: payload.to_vec(),
                reply_to: reply_to.clone(),
            },
            Frame::Ping => FrameHelper::Ping,
            Frame::Pong => FrameHelper::Pong,
            Frame::Ok => FrameHelper::Ok,
            Frame::Err { message } => FrameHelper::Err {
                message: message.clone(),
            },
        }
    }
}

impl From<FrameHelper> for Frame {
    fn from(helper: FrameHelper) -> Self {
        match helper {
            FrameHelper::Publish {
                topic,
                payload,
                reply_to,
            } => Frame::Publish {
                topic,
                payload: Bytes::from(payload),
                reply_to,
            },
            FrameHelper::Subscribe {
                sid,
                subject,
                queue_group,
            } => Frame::Subscribe {
                sid,
                subject,
                queue_group,
            },
            FrameHelper::Unsubscribe { sid } => Frame::Unsubscribe { sid },
            FrameHelper::Message {
                topic,
                sid,
                payload,
                reply_to,
            } => Frame::Message {
                topic,
                sid,
                payload: Bytes::from(payload),
                reply_to,
            },
            FrameHelper::Ping => Frame::Ping,
            FrameHelper::Pong => Frame::Pong,
            FrameHelper::Ok => Frame::Ok,
            FrameHelper::Err { message } => Frame::Err { message },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn roundtrip(frame: &Frame) -> Frame {
        let encoded = rmp_serde::to_vec(frame).unwrap();
        rmp_serde::from_slice(&encoded).unwrap()
    }

    #[test]
    fn roundtrip_publish() {
        let frame = Frame::Publish {
            topic: "test.topic".into(),
            payload: Bytes::from("hello"),
            reply_to: None,
        };
        assert_eq!(roundtrip(&frame), frame);
    }

    #[test]
    fn roundtrip_publish_with_reply() {
        let frame = Frame::Publish {
            topic: "req".into(),
            payload: Bytes::from("data"),
            reply_to: Some("inbox.123".into()),
        };
        assert_eq!(roundtrip(&frame), frame);
    }

    #[test]
    fn roundtrip_subscribe() {
        let frame = Frame::Subscribe {
            sid: 42,
            subject: "sensors.>".into(),
            queue_group: Some("workers".into()),
        };
        assert_eq!(roundtrip(&frame), frame);
    }

    #[test]
    fn roundtrip_unsubscribe() {
        let frame = Frame::Unsubscribe { sid: 7 };
        assert_eq!(roundtrip(&frame), frame);
    }

    #[test]
    fn roundtrip_message() {
        let frame = Frame::Message {
            topic: "sensors.temp".into(),
            sid: 1,
            payload: Bytes::from("25.3"),
            reply_to: None,
        };
        assert_eq!(roundtrip(&frame), frame);
    }

    #[test]
    fn roundtrip_ping_pong() {
        assert_eq!(roundtrip(&Frame::Ping), Frame::Ping);
        assert_eq!(roundtrip(&Frame::Pong), Frame::Pong);
    }

    #[test]
    fn roundtrip_ok() {
        assert_eq!(roundtrip(&Frame::Ok), Frame::Ok);
    }

    #[test]
    fn roundtrip_err() {
        let frame = Frame::Err {
            message: "bad request".into(),
        };
        assert_eq!(roundtrip(&frame), frame);
    }

    #[test]
    fn empty_payload() {
        let frame = Frame::Publish {
            topic: "t".into(),
            payload: Bytes::new(),
            reply_to: None,
        };
        assert_eq!(roundtrip(&frame), frame);
    }
}
