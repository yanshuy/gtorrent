-record(torrent, {
    info :: torrent@torrent:torrent_info(),
    download_path :: binary(),
    peers :: gleam@set:set(torrent@peer@protocol:peer_id()),
    pending_pieces :: list(torrent@torrent:piece_info())
}).
