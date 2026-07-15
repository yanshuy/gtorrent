-record(ready, {
    peer :: torrent@peer@protocol:peer_id(),
    bitfield :: bitstring(),
    reply_subject :: gleam@erlang@process:subject(torrent@torrent:piece_info())
}).
