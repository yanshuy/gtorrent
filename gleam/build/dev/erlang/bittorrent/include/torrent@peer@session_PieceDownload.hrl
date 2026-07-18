-record(piece_download, {
    index :: integer(),
    length :: integer(),
    blocks :: gleam@dict:dict(integer(), bitstring()),
    pending_requests :: list(torrent@peer@session:block_request()),
    outstanding_requests :: gleam@dict:dict(integer(), torrent@peer@session:block_request())
}).
