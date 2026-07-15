-record(peer_session, {
    socket :: mug:socket(),
    peer_id :: torrent@peer@protocol:peer_id(),
    bitfield :: bitstring(),
    piece :: gleam@option:option(torrent@peer@session:piece_download()),
    choked :: boolean(),
    interested :: boolean()
}).
