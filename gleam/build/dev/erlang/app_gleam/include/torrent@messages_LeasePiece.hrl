-record(lease_piece, {
    peer_id :: torrent@peer@protocol:peer_id(),
    reply_subject :: gleam@erlang@process:subject(torrent@torrent:piece_info())
}).
