-module(handshake).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/handshake.gleam").
-export([handshake/4, describe_error/1]).
-export_type([handshake_error/0]).

-type handshake_error() :: invalid_handshake |
    info_hash_mismatch |
    {torrent_error, torrent:torrent_error()} |
    {handshake_error, binary()} |
    {t_c_p_error, mug:error()}.

-file("src/handshake.gleam", 67).
-spec validate_handshake_message(bitstring(), bitstring()) -> {ok, bitstring()} |
    {error, handshake_error()}.
validate_handshake_message(Info_hash, Resp) ->
    case Resp of
        <<19/integer,
            "BitTorrent protocol"/utf8,
            0:8/unit:8,
            Rev_info_hash:20/binary-unit:8,
            Peer_id:20/binary-unit:8>> ->
            case Rev_info_hash =:= Info_hash of
                true ->
                    {ok, Peer_id};

                false ->
                    {error, info_hash_mismatch}
            end;

        _ ->
            {error, invalid_handshake}
    end.

-file("src/handshake.gleam", 52).
-spec connect(binary(), integer()) -> {ok, mug:socket()} |
    {error, handshake_error()}.
connect(Host, Port) ->
    _pipe = mug:connect({connection_options, Host, Port, 1000, ipv4_only}),
    gleam@result:map_error(_pipe, fun(Err) -> case Err of
                {connect_failed_ipv4, Err@1} ->
                    {t_c_p_error, Err@1};

                _ ->
                    erlang:error(#{gleam_error => panic,
                            message => <<"`panic` expression evaluated."/utf8>>,
                            file => <<?FILEPATH/utf8>>,
                            module => <<"handshake"/utf8>>,
                            function => <<"connect"/utf8>>,
                            line => 62})
            end end).

-file("src/handshake.gleam", 17).
-spec handshake(binary(), integer(), bencode:bencode(), bitstring()) -> {ok,
        nil} |
    {error, handshake_error()}.
handshake(Host, Port, Torrent, Peer_id) ->
    gleam@result:'try'(
        begin
            _pipe = torrent:dict(Torrent),
            gleam@result:map_error(
                _pipe,
                fun(Field@0) -> {torrent_error, Field@0} end
            )
        end,
        fun(Dict) ->
            gleam@result:'try'(
                begin
                    _pipe@1 = torrent:get_entries(Dict, <<"info"/utf8>>),
                    gleam@result:map_error(
                        _pipe@1,
                        fun(Field@0) -> {torrent_error, Field@0} end
                    )
                end,
                fun(Info_entries) ->
                    Info_hash = torrent:digest_entries(Info_entries),
                    Handshake_msg = <<19/integer,
                        "BitTorrent protocol"/utf8,
                        0:8/unit:8,
                        Info_hash/bitstring,
                        Peer_id/bitstring>>,
                    gleam@result:'try'(
                        connect(Host, Port),
                        fun(Socket) ->
                            gleam@result:'try'(
                                begin
                                    _pipe@2 = mug:send(Socket, Handshake_msg),
                                    gleam@result:map_error(
                                        _pipe@2,
                                        fun(Field@0) -> {t_c_p_error, Field@0} end
                                    )
                                end,
                                fun(_) ->
                                    gleam@result:'try'(
                                        begin
                                            _pipe@3 = mug:'receive'(Socket, 500),
                                            gleam@result:map_error(
                                                _pipe@3,
                                                fun(Field@0) -> {t_c_p_error, Field@0} end
                                            )
                                        end,
                                        fun(Handshake_back) ->
                                            gleam@result:'try'(
                                                validate_handshake_message(
                                                    Info_hash,
                                                    Handshake_back
                                                ),
                                                fun(Peer_peer_id) ->
                                                    _pipe@4 = Peer_peer_id,
                                                    _pipe@5 = gleam_stdlib:base16_encode(
                                                        _pipe@4
                                                    ),
                                                    _pipe@6 = string:lowercase(
                                                        _pipe@5
                                                    ),
                                                    gleam_stdlib:println(
                                                        _pipe@6
                                                    ),
                                                    {ok, nil}
                                                end
                                            )
                                        end
                                    )
                                end
                            )
                        end
                    )
                end
            )
        end
    ).

-file("src/handshake.gleam", 88).
-spec describe_error(handshake_error()) -> binary().
describe_error(Error) ->
    case Error of
        invalid_handshake ->
            <<"Received malformed handshake (expected 68-byte BitTorrent handshake)"/utf8>>;

        info_hash_mismatch ->
            <<"Peer responded with a different info hash"/utf8>>;

        {t_c_p_error, Err} ->
            mug:describe_error(Err);

        {torrent_error, Err@1} ->
            torrent:describe_error(Err@1);

        {handshake_error, Msg} ->
            Msg
    end.
