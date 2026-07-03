-record(piece_download, {
    index :: integer(),
    length :: integer(),
    hash :: bitstring(),
    offset :: integer(),
    blocks :: list(bitstring())
}).
