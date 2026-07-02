-module(peer_protocol).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/peer_protocol.gleam").
-export([ask_one_piece/2, handshake/3, describe_error/1]).
-export_type([peer_error/0]).

-type peer_error() :: invalid_endpoint |
    invalid_handshake |
    info_hash_mismatch |
    {torrent_error, torrent:torrent_error()} |
    {protocol_error, binary()} |
    {t_c_p_error, mug:error()}.

-file("src/peer_protocol.gleam", 17).
-spec ask_one_piece(bencode:bencode(), bitstring()) -> {ok, nil} |
    {error, peer_error()}.
ask_one_piece(Torrent, Peer_id) ->
    erlang:error(#{gleam_error => todo,
            message => <<"`todo` expression evaluated. This code has not yet been implemented."/utf8>>,
            file => <<?FILEPATH/utf8>>,
            module => <<"peer_protocol"/utf8>>,
            function => <<"ask_one_piece"/utf8>>,
            line => 21}).

-file("src/peer_protocol.gleam", 80).
-spec validate_handshake_message(bitstring(), bitstring()) -> {ok, bitstring()} |
    {error, peer_error()}.
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

-file("src/peer_protocol.gleam", 58).
-spec connect(binary(), integer()) -> {ok, mug:socket()} | {error, peer_error()}.
connect(Host, Port) ->
    _pipe = mug:connect({connection_options, Host, Port, 1000, ipv4_only}),
    gleam@result:map_error(_pipe, fun(Err) -> case Err of
                {connect_failed_ipv4, Err@1} ->
                    {t_c_p_error, Err@1};

                _ ->
                    erlang:error(#{gleam_error => panic,
                            message => <<"`panic` expression evaluated."/utf8>>,
                            file => <<?FILEPATH/utf8>>,
                            module => <<"peer_protocol"/utf8>>,
                            function => <<"connect"/utf8>>,
                            line => 68})
            end end).

-file("src/peer_protocol.gleam", 73).
-spec validate_endpoint(binary()) -> {ok, {binary(), binary()}} | {error, nil}.
validate_endpoint(Endpoint) ->
    case gleam@string:split(Endpoint, <<":"/utf8>>) of
        [Ipv4, Port] ->
            {ok, {Ipv4, Port}};

        _ ->
            {error, nil}
    end.

-file("src/peer_protocol.gleam", 24).
-spec handshake(binary(), bencode:bencode(), bitstring()) -> {ok, bitstring()} |
    {error, peer_error()}.
handshake(Endpoint, Torrent, Peer_id) ->
    gleam@result:'try'(
        begin
            _pipe = validate_endpoint(Endpoint),
            gleam@result:replace_error(_pipe, invalid_endpoint)
        end,
        fun(_use0) ->
            {Ip4_addr, Port_str} = _use0,
            gleam@result:'try'(
                begin
                    _pipe@1 = gleam_stdlib:parse_int(Port_str),
                    gleam@result:replace_error(_pipe@1, invalid_endpoint)
                end,
                fun(Port) ->
                    gleam@result:'try'(
                        begin
                            _pipe@2 = torrent:dict(Torrent),
                            gleam@result:map_error(
                                _pipe@2,
                                fun(Field@0) -> {torrent_error, Field@0} end
                            )
                        end,
                        fun(Dict) ->
                            gleam@result:'try'(
                                begin
                                    _pipe@3 = torrent:get_entries(
                                        Dict,
                                        <<"info"/utf8>>
                                    ),
                                    gleam@result:map_error(
                                        _pipe@3,
                                        fun(Field@0) -> {torrent_error, Field@0} end
                                    )
                                end,
                                fun(Info_entries) ->
                                    Info_hash = torrent:digest_entries(
                                        Info_entries
                                    ),
                                    Handshake_msg = <<19/integer,
                                        "BitTorrent protocol"/utf8,
                                        0:8/unit:8,
                                        Info_hash/bitstring,
                                        Peer_id/bitstring>>,
                                    gleam@result:'try'(
                                        connect(Ip4_addr, Port),
                                        fun(Socket) ->
                                            gleam@result:'try'(
                                                begin
                                                    _pipe@4 = mug:send(
                                                        Socket,
                                                        Handshake_msg
                                                    ),
                                                    gleam@result:map_error(
                                                        _pipe@4,
                                                        fun(Field@0) -> {t_c_p_error, Field@0} end
                                                    )
                                                end,
                                                fun(_) ->
                                                    gleam@result:'try'(
                                                        begin
                                                            _pipe@5 = mug:'receive'(
                                                                Socket,
                                                                500
                                                            ),
                                                            gleam@result:map_error(
                                                                _pipe@5,
                                                                fun(Field@0) -> {t_c_p_error, Field@0} end
                                                            )
                                                        end,
                                                        fun(Handshake_back) ->
                                                            gleam@result:'try'(
                                                                validate_handshake_message(
                                                                    Info_hash,
                                                                    Handshake_back
                                                                ),
                                                                fun(
                                                                    Peer_peer_id
                                                                ) ->
                                                                    {ok,
                                                                        Peer_peer_id}
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
                    )
                end
            )
        end
    ).

-file("src/peer_protocol.gleam", 101).
-spec describe_error(peer_error()) -> binary().
describe_error(Error) ->
    case Error of
        invalid_endpoint ->
            <<"Invalid endpoint. Expected <ip>:<port>."/utf8>>;

        invalid_handshake ->
            <<"Received malformed handshake (expected 68-byte BitTorrent handshake)"/utf8>>;

        info_hash_mismatch ->
            <<"Peer responded with a different info hash"/utf8>>;

        {t_c_p_error, Err} ->
            mug:describe_error(Err);

        {torrent_error, Err@1} ->
            torrent:describe_error(Err@1);

        {protocol_error, Msg} ->
            Msg
    end.
