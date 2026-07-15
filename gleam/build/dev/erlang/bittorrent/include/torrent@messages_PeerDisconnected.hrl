-record(peer_disconnected, {
    peer :: torrent@peer@protocol:peer_id(),
    reason :: binary()
}).
