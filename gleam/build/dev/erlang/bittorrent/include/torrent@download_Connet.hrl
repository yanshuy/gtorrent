-record(connet, {
    endpoints :: list(torrent@peer@protocol:endpoint()),
    torrent :: gleam@option:option(torrent@torrent:torrent_info())
}).
