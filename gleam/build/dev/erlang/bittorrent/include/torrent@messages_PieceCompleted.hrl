-record(piece_completed, {
    peer :: torrent@peer@protocol:peer_id(),
    index :: integer(),
    piece :: bitstring()
}).
