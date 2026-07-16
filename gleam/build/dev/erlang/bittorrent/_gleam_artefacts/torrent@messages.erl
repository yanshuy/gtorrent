-module(torrent@messages).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/torrent/messages.gleam").
-export_type([peer_event/0]).

-type peer_event() :: {ready, torrent@peer@protocol:peer_id(), bitstring()} |
    {lease_piece,
        torrent@peer@protocol:peer_id(),
        gleam@erlang@process:subject(torrent@torrent:piece_info())} |
    {piece_completed, integer(), bitstring()} |
    {peer_disconnected, torrent@peer@protocol:peer_id(), binary()}.


