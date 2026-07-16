-record(peer_session, {
    socket :: mug:socket(),
    peer_id :: torrent@peer@protocol:peer_id(),
    extension :: boolean(),
    state :: torrent@peer@session:state(),
    bitfield :: bitstring(),
    choked :: boolean(),
    interested :: boolean()
}).
