-record(torrent, {
    name :: binary(),
    announce :: binary(),
    length :: integer(),
    piece_length :: integer(),
    pieces :: list(bitstring()),
    info_hash :: bitstring()
}).
