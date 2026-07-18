-record(ready, {
    peer :: torrent@peer@protocol:peer_id(),
    subject :: gleam@erlang@process:subject(torrent@torrent:piece_info())
}).
