-module(torrent@peer@protocol).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/torrent/peer/protocol.gleam").
-export([connect/1, handshake/3, send_message/2, extension_message_id/1, message_id/1, send_extended_handshake/1, log/1, receive_message/1, describe_error/1]).
-export_type([peer_message/0, extension_message/0, peer_id/0, endpoint/0, protocol_error/0]).

-type peer_message() :: choke |
    unchoke |
    interested |
    not_interested |
    have |
    {bit_field, bitstring()} |
    {request, integer(), integer(), integer()} |
    {piece, integer(), integer(), bitstring()} |
    {extension, extension_message()}.

-type extension_message() :: {handshake, list({binary(), integer()})}.

-type peer_id() :: {peer_id, bitstring()}.

-type endpoint() :: {endpoint, binary(), integer()}.

-type protocol_error() :: invalid_message |
    info_hash_mismatch |
    {t_c_p_error, mug:error()} |
    {unknown_message_id, integer()} |
    {unexpected_message, integer()} |
    {protocol_error_msg, binary()} |
    {bencode_error, bencode:bencode_error()}.

-file("src/torrent/peer/protocol.gleam", 34).
-spec connect(endpoint()) -> {ok, mug:socket()} | {error, protocol_error()}.
connect(Endpoint) ->
    _pipe = mug:connect(
        {connection_options,
            erlang:element(2, Endpoint),
            erlang:element(3, Endpoint),
            5000,
            ipv4_only}
    ),
    gleam@result:map_error(_pipe, fun(Err) -> case Err of
                {connect_failed_ipv4, Err@1} ->
                    {t_c_p_error, Err@1};

                _ ->
                    erlang:error(#{gleam_error => panic,
                            message => <<"`panic` expression evaluated."/utf8>>,
                            file => <<?FILEPATH/utf8>>,
                            module => <<"torrent/peer/protocol"/utf8>>,
                            function => <<"connect"/utf8>>,
                            line => 44})
            end end).

-file("src/torrent/peer/protocol.gleam", 61).
-spec peer_handshake(mug:socket(), bitstring(), bitstring()) -> {ok,
        {peer_id(), bitstring()}} |
    {error, protocol_error()}.
peer_handshake(Socket, Info_hash, Peer_id) ->
    Handshake_msg = <<19/integer,
        "BitTorrent protocol"/utf8,
        16#00,
        16#00,
        16#00,
        16#00,
        16#00,
        16#10,
        16#00,
        16#00,
        Info_hash/bitstring,
        Peer_id/bitstring>>,
    gleam@result:'try'(
        begin
            _pipe = mug:send(Socket, Handshake_msg),
            gleam@result:map_error(
                _pipe,
                fun(Field@0) -> {t_c_p_error, Field@0} end
            )
        end,
        fun(_) ->
            gleam@result:'try'(
                begin
                    _pipe@1 = mug:receive_exact(
                        Socket,
                        ((20 + 8) + 20) + 20,
                        5000
                    ),
                    gleam@result:map_error(
                        _pipe@1,
                        fun(Field@0) -> {t_c_p_error, Field@0} end
                    )
                end,
                fun(Handshake_back) -> case Handshake_back of
                        <<19/integer,
                            "BitTorrent protocol"/utf8,
                            Reserved:8/binary,
                            Rev_info_hash:20/binary-unit:8,
                            Peer_id@1:20/binary-unit:8>> ->
                            case Rev_info_hash =:= Info_hash of
                                true ->
                                    {ok, {{peer_id, Peer_id@1}, Reserved}};

                                false ->
                                    {error, info_hash_mismatch}
                            end;

                        _ ->
                            {error, invalid_message}
                    end end
            )
        end
    ).

-file("src/torrent/peer/protocol.gleam", 49).
-spec handshake(endpoint(), bitstring(), peer_id()) -> {ok,
        {mug:socket(), peer_id(), boolean()}} |
    {error, protocol_error()}.
handshake(Endpoint, Info_hash, Peer_id) ->
    gleam@result:'try'(
        connect(Endpoint),
        fun(Socket) ->
            {peer_id, Id} = Peer_id,
            gleam@result:'try'(
                peer_handshake(Socket, Info_hash, Id),
                fun(_use0) ->
                    {Peer_peer_id, Reserved} = _use0,
                    _pipe = case Reserved of
                        <<_:(64 - 20), 1:1, _/bitstring>> ->
                            {Socket, Peer_peer_id, true};

                        _ ->
                            {Socket, Peer_peer_id, false}
                    end,
                    {ok, _pipe}
                end
            )
        end
    ).

-file("src/torrent/peer/protocol.gleam", 133).
-spec send_message(mug:socket(), bitstring()) -> {ok, nil} |
    {error, protocol_error()}.
send_message(Socket, Message) ->
    _pipe = mug:send(Socket, Message),
    gleam@result:map_error(_pipe, fun(Field@0) -> {t_c_p_error, Field@0} end).

-file("src/torrent/peer/protocol.gleam", 114).
-spec encode_extension_message(extension_message()) -> bitstring().
encode_extension_message(Message) ->
    case Message of
        {handshake, Extensions} ->
            _pipe = Extensions,
            _pipe@1 = gleam@list:map(
                _pipe,
                fun(Item) ->
                    {erlang:element(1, Item), {int, erlang:element(2, Item)}}
                end
            ),
            _pipe@2 = {dict, _pipe@1},
            _pipe@3 = bencode:to_bencode(_pipe@2),
            bencode:encode(_pipe@3)
    end.

-file("src/torrent/peer/protocol.gleam", 242).
-spec extension_message_id(extension_message()) -> integer().
extension_message_id(Message) ->
    case Message of
        {handshake, _} ->
            0
    end.

-file("src/torrent/peer/protocol.gleam", 228).
-spec message_id(peer_message()) -> integer().
message_id(Message) ->
    case Message of
        choke ->
            0;

        unchoke ->
            1;

        interested ->
            2;

        not_interested ->
            3;

        have ->
            4;

        {bit_field, _} ->
            5;

        {request, _, _, _} ->
            6;

        {piece, _, _, _} ->
            7;

        {extension, _} ->
            20
    end.

-file("src/torrent/peer/protocol.gleam", 93).
-spec send_extended_handshake(mug:socket()) -> {ok, nil} |
    {error, protocol_error()}.
send_extended_handshake(Socket) ->
    Extensions = [{<<"ut_metadata"/utf8>>, 10}],
    Ext_message = {handshake, Extensions},
    Id = message_id({extension, Ext_message}),
    Ext_message_id = extension_message_id(Ext_message),
    Encoded = encode_extension_message(Ext_message),
    Message_len = (1 + 1) + erlang:byte_size(Encoded),
    Extension_message = <<Message_len:32/big,
        Id/integer,
        Ext_message_id/integer,
        Encoded/bitstring>>,
    send_message(Socket, Extension_message).

-file("src/torrent/peer/protocol.gleam", 126).
-spec log(peer_message()) -> peer_message().
log(M) ->
    case M of
        {piece, _, _, _} ->
            {piece, erlang:element(2, M), erlang:element(3, M), <<>>};

        _ ->
            M
    end.

-file("src/torrent/peer/protocol.gleam", 196).
-spec parse_extension_message(bitstring()) -> {ok, peer_message()} |
    {error, protocol_error()}.
parse_extension_message(Message) ->
    {Extension_id@1, Payload@1} = case Message of
        <<Extension_id/integer, Payload/bitstring>> -> {Extension_id, Payload};
        _assert_fail ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"torrent/peer/protocol"/utf8>>,
                        function => <<"parse_extension_message"/utf8>>,
                        line => 199,
                        value => _assert_fail,
                        start => 4780,
                        'end' => 4835,
                        pattern_start => 4791,
                        pattern_end => 4825})
    end,
    case Extension_id@1 of
        0 ->
            gleam@result:'try'(
                begin
                    _pipe = bencode:decode(Payload@1),
                    gleam@result:map_error(
                        _pipe,
                        fun(Field@0) -> {bencode_error, Field@0} end
                    )
                end,
                fun(Bencode) ->
                    gleam@result:'try'(
                        begin
                            _pipe@1 = bencode:dict(Bencode),
                            gleam@result:replace_error(
                                _pipe@1,
                                {protocol_error_msg,
                                    <<"invalid extension handshake response"/utf8>>}
                            )
                        end,
                        fun(Dict) ->
                            gleam@result:'try'(
                                begin
                                    _pipe@2 = bencode:get_entries(
                                        Dict,
                                        <<"m"/utf8>>
                                    ),
                                    gleam@result:replace_error(
                                        _pipe@2,
                                        {protocol_error_msg,
                                            <<"missing 'm' key in handshake"/utf8>>}
                                    )
                                end,
                                fun(Entries) ->
                                    gleam@result:'try'(
                                        gleam@list:try_map(
                                            Entries,
                                            fun(Entry) -> case Entry of
                                                    {Key, {b_integer, Int}} ->
                                                        {ok, {Key, Int}};

                                                    _ ->
                                                        {error,
                                                            {protocol_error_msg,
                                                                <<"invalid type inside 'm' dictionary"/utf8>>}}
                                                end end
                                        ),
                                        fun(Extensions) ->
                                            _pipe@3 = {extension,
                                                {handshake, Extensions}},
                                            {ok, _pipe@3}
                                        end
                                    )
                                end
                            )
                        end
                    )
                end
            );

        _ ->
            {error, {unknown_message_id, Extension_id@1}}
    end.

-file("src/torrent/peer/protocol.gleam", 161).
-spec parse_message(bitstring()) -> {ok, peer_message()} |
    {error, protocol_error()}.
parse_message(Message) ->
    {Message_id@1, Payload@1} = case Message of
        <<Message_id, Payload/bitstring>> -> {Message_id, Payload};
        _assert_fail ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"torrent/peer/protocol"/utf8>>,
                        function => <<"parse_message"/utf8>>,
                        line => 162,
                        value => _assert_fail,
                        start => 3879,
                        'end' => 3928,
                        pattern_start => 3890,
                        pattern_end => 3918})
    end,
    case Message_id@1 of
        0 ->
            {ok, choke};

        1 ->
            {ok, unchoke};

        2 ->
            {ok, interested};

        3 ->
            {ok, not_interested};

        4 ->
            {ok, have};

        5 ->
            {ok, {bit_field, Payload@1}};

        6 ->
            case Payload@1 of
                <<Piece_index:4/big-unit:8,
                    Begin:4/big-unit:8,
                    Length:4/big-unit:8>> ->
                    {ok, {request, Piece_index, Begin, Length}};

                _ ->
                    {error, invalid_message}
            end;

        7 ->
            case Payload@1 of
                <<Piece_index@1:4/big-unit:8,
                    Begin@1:4/big-unit:8,
                    Block/bitstring>> ->
                    {ok, {piece, Piece_index@1, Begin@1, Block}};

                _ ->
                    {error, invalid_message}
            end;

        20 ->
            parse_extension_message(Payload@1);

        Id ->
            {error, {unknown_message_id, Id}}
    end.

-file("src/torrent/peer/protocol.gleam", 140).
-spec receive_message(mug:socket()) -> {ok, peer_message()} |
    {error, protocol_error()}.
receive_message(Socket) ->
    gleam@result:'try'(
        begin
            _pipe = mug:receive_exact(Socket, 4, 5000),
            gleam@result:map_error(
                _pipe,
                fun(Field@0) -> {t_c_p_error, Field@0} end
            )
        end,
        fun(Bits) ->
            Message_length@1 = case Bits of
                <<Message_length:4/unsigned-big-unit:8>> -> Message_length;
                _assert_fail ->
                    erlang:error(#{gleam_error => let_assert,
                                message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                                file => <<?FILEPATH/utf8>>,
                                module => <<"torrent/peer/protocol"/utf8>>,
                                function => <<"receive_message"/utf8>>,
                                line => 146,
                                value => _assert_fail,
                                start => 3473,
                                'end' => 3538,
                                pattern_start => 3484,
                                pattern_end => 3531})
            end,
            case Message_length@1 of
                0 ->
                    receive_message(Socket);

                _ ->
                    gleam@result:'try'(
                        begin
                            _pipe@1 = mug:receive_exact(
                                Socket,
                                Message_length@1,
                                5000
                            ),
                            gleam@result:map_error(
                                _pipe@1,
                                fun(Field@0) -> {t_c_p_error, Field@0} end
                            )
                        end,
                        fun(Message) -> parse_message(Message) end
                    )
            end
        end
    ).

-file("src/torrent/peer/protocol.gleam", 258).
-spec describe_error(protocol_error()) -> binary().
describe_error(Error) ->
    case Error of
        invalid_message ->
            <<"Received an invalid message from the peer"/utf8>>;

        info_hash_mismatch ->
            <<"Peer responded with a different info hash"/utf8>>;

        {unknown_message_id, Msg_id} ->
            <<"Unknown Message Id "/utf8,
                (erlang:integer_to_binary(Msg_id))/binary>>;

        {unexpected_message, Msg_id@1} ->
            <<"Unexpected peer message: "/utf8,
                (erlang:integer_to_binary(Msg_id@1))/binary>>;

        {t_c_p_error, Err} ->
            mug:describe_error(Err);

        {bencode_error, Err@1} ->
            bencode:describe_error(Err@1);

        {protocol_error_msg, Err@2} ->
            Err@2
    end.
