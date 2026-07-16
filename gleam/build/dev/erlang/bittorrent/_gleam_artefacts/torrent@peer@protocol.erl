-module(torrent@peer@protocol).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/torrent/peer/protocol.gleam").
-export([connect/1, handshake/3, send_message/2, message_id/1, extension_handshake/1, log/1, receive_message/1, describe_error/1]).
-export_type([peer_message/0, peer_id/0, endpoint/0, protocol_error/0]).

-type peer_message() :: choke |
    unchoke |
    interested |
    not_interested |
    have |
    {bit_field, bitstring()} |
    {request, integer(), integer(), integer()} |
    {piece, integer(), integer(), bitstring()} |
    extension.

-type peer_id() :: {peer_id, bitstring()}.

-type endpoint() :: {endpoint, binary(), integer()}.

-type protocol_error() :: invalid_response |
    info_hash_mismatch |
    {t_c_p_error, mug:error()} |
    {unknown_message_id, integer()} |
    {unexpected_message, integer()} |
    {protocol_error_msg, binary()}.

-file("src/torrent/peer/protocol.gleam", 29).
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
                            line => 39})
            end end).

-file("src/torrent/peer/protocol.gleam", 58).
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
                            {error, invalid_response}
                    end end
            )
        end
    ).

-file("src/torrent/peer/protocol.gleam", 44).
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
                        <<_:44, 1:1, _/bitstring>> ->
                            {Socket, Peer_peer_id, true};

                        _ ->
                            {Socket, Peer_peer_id, false}
                    end,
                    {ok, _pipe}
                end
            )
        end
    ).

-file("src/torrent/peer/protocol.gleam", 118).
-spec send_message(mug:socket(), bitstring()) -> {ok, nil} |
    {error, protocol_error()}.
send_message(Socket, Message) ->
    _pipe = mug:send(Socket, Message),
    gleam@result:map_error(_pipe, fun(Field@0) -> {t_c_p_error, Field@0} end).

-file("src/torrent/peer/protocol.gleam", 175).
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

        extension ->
            20
    end.

-file("src/torrent/peer/protocol.gleam", 90).
-spec extension_handshake(mug:socket()) -> {ok, nil} | {error, protocol_error()}.
extension_handshake(Socket) ->
    Id = message_id(extension),
    Extension_message_id = 0,
    Payload_dict = bencode:encode(
        {b_dict,
            [{<<"m"/utf8>>,
                    {b_dict, [{<<"ut_metadata"/utf8>>, {b_integer, 1}}]}}]}
    ),
    Message_len = (1 + 1) + erlang:byte_size(Payload_dict),
    Extension_message = <<Message_len:32/big,
        Id/integer,
        Extension_message_id/integer,
        Payload_dict/bitstring>>,
    send_message(Socket, Extension_message).

-file("src/torrent/peer/protocol.gleam", 111).
-spec log(peer_message()) -> peer_message().
log(M) ->
    case M of
        {piece, _, _, _} ->
            {piece, erlang:element(2, M), erlang:element(3, M), <<>>};

        _ ->
            M
    end.

-file("src/torrent/peer/protocol.gleam", 146).
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
                        line => 147,
                        value => _assert_fail,
                        start => 3444,
                        'end' => 3493,
                        pattern_start => 3455,
                        pattern_end => 3483})
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
            {Piece_index@1, Begin@1, Length@1} = case Payload@1 of
                <<Piece_index:4/big-unit:8,
                    Begin:4/big-unit:8,
                    Length:4/big-unit:8>> -> {Piece_index, Begin, Length};
                _assert_fail@1 ->
                    erlang:error(#{gleam_error => let_assert,
                                message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                                file => <<?FILEPATH/utf8>>,
                                module => <<"torrent/peer/protocol"/utf8>>,
                                function => <<"parse_message"/utf8>>,
                                line => 156,
                                value => _assert_fail@1,
                                start => 3671,
                                'end' => 3815,
                                pattern_start => 3682,
                                pattern_end => 3805})
            end,
            {ok, {request, Piece_index@1, Begin@1, Length@1}};

        7 ->
            {Piece_index@3, Begin@3, Block@1} = case Payload@1 of
                <<Piece_index@2:4/big-unit:8,
                    Begin@2:4/big-unit:8,
                    Block/bitstring>> -> {Piece_index@2, Begin@2, Block};
                _assert_fail@2 ->
                    erlang:error(#{gleam_error => let_assert,
                                message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                                file => <<?FILEPATH/utf8>>,
                                module => <<"torrent/peer/protocol"/utf8>>,
                                function => <<"parse_message"/utf8>>,
                                line => 164,
                                value => _assert_fail@2,
                                start => 3885,
                                'end' => 4013,
                                pattern_start => 3896,
                                pattern_end => 4003})
            end,
            {ok, {piece, Piece_index@3, Begin@3, Block@1}};

        Id ->
            {error, {unknown_message_id, Id}}
    end.

-file("src/torrent/peer/protocol.gleam", 125).
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
                <<Message_length:(4 * 8)/unsigned-big>> -> Message_length;
                _assert_fail ->
                    erlang:error(#{gleam_error => let_assert,
                                message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                                file => <<?FILEPATH/utf8>>,
                                module => <<"torrent/peer/protocol"/utf8>>,
                                function => <<"receive_message"/utf8>>,
                                line => 131,
                                value => _assert_fail,
                                start => 3042,
                                'end' => 3103,
                                pattern_start => 3053,
                                pattern_end => 3096})
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

-file("src/torrent/peer/protocol.gleam", 198).
-spec describe_error(protocol_error()) -> binary().
describe_error(Error) ->
    case Error of
        invalid_response ->
            <<"Received an invalid response from the peer"/utf8>>;

        info_hash_mismatch ->
            <<"Peer responded with a different info hash"/utf8>>;

        {t_c_p_error, Err} ->
            mug:describe_error(Err);

        {protocol_error_msg, Err@1} ->
            Err@1;

        {unknown_message_id, Msg_id} ->
            <<"Unknown Message Id "/utf8,
                (erlang:integer_to_binary(Msg_id))/binary>>;

        {unexpected_message, Msg_id@1} ->
            <<"Unexpected peer message: "/utf8,
                (erlang:integer_to_binary(Msg_id@1))/binary>>
    end.
