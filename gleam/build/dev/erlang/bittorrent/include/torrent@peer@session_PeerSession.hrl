-record(peer_session, {
    socket :: mug:socket(),
    peer_id :: torrent@peer@protocol:peer_id(),
    bitfield :: gleam@option:option(bitstring()),
    extensions :: gleam@option:option(gleam@dict:dict(binary(), integer())),
    state :: torrent@peer@session:state(),
    choked :: boolean(),
    interested :: boolean()
}).
