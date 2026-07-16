-record(torrent_state, {
    info :: torrent@torrent:torrent_info(),
    pending_pieces :: list(torrent@torrent:piece_info()),
    leased_pieces :: list(torrent@torrent:piece_info()),
    peers :: gleam@dict:dict(torrent@peer@protocol:peer_id(), bitstring())
}).
