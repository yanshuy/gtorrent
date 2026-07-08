-record(piece_result, {
    session :: torrent@peer@session:peer_session(),
    piece :: bitstring()
}).
