-record(piece_download, {
    info :: torrent@torrent:piece_info(),
    blocks :: gleam@dict:dict(integer(), bitstring()),
    pending_requests :: list(torrent@peer@session:block_request()),
    outstanding_requests :: gleam@dict:dict(integer(), torrent@peer@session:block_request())
}).
