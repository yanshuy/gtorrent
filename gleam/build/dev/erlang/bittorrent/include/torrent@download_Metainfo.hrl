-record(metainfo, {
    peers :: gleam@dict:dict(torrent@peer@protocol:peer_id(), bitstring())
}).
