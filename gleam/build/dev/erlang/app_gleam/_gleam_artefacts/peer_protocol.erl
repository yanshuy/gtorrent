-module(peer_protocol).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/peer_protocol.gleam").
-export([peer_handshake/3, one_piece/5, handshake/3, describe_error/1]).
-export_type([protocol_error/0, peer_message/0, peer_state/0, piece_download/0, peer_outcome/0]).

-type protocol_error() :: invalid_endpoint |
    invalid_response |
    info_hash_mismatch |
    {t_c_p_error, mug:error()} |
    {unknown_message_id, integer()} |
    {unexpected_message, integer()} |
    {protocol_error, binary()}.

-type peer_message() :: choke |
    unchoke |
    interested |
    not_interested |
    have |
    {bit_field, bitstring()} |
    {request, integer(), integer(), integer()} |
    {piece, integer(), integer(), bitstring()}.

-type peer_state() :: {peer_state, boolean(), boolean()}.

-type piece_download() :: {piece_download,
        integer(),
        integer(),
        bitstring(),
        integer(),
        list(bitstring())}.

-type peer_outcome() :: {piece_downloaded, bitstring()} |
    peer_does_not_have_piece.

-file("src/peer_protocol.gleam", 331).
-spec piece_length(integer(), integer(), integer()) -> integer().
piece_length(Index, File_length, Piece_length) ->
    Piece_count = case Piece_length of
        0 -> 0;
        Gleam@denominator -> ((File_length + Piece_length) - 1) div Gleam@denominator
    end,
    case (Piece_count - 1) =:= Index of
        true ->
            case case Piece_length of
                0 -> 0;
                Gleam@denominator@1 -> File_length rem Gleam@denominator@1
            end of
                0 ->
                    Piece_length;

                Rem ->
                    Rem
            end;

        false ->
            Piece_length
    end.

-file("src/peer_protocol.gleam", 309).
-spec peer_message_id(peer_message()) -> integer().
peer_message_id(Message) ->
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
            7
    end.

-file("src/peer_protocol.gleam", 322).
-spec verify_piece(bitstring(), bitstring()) -> {ok, nil} |
    {error, protocol_error()}.
verify_piece(Binary, Hash) ->
    Calc = gleam@crypto:hash(sha1, Binary),
    case Calc =:= Hash of
        true ->
            {ok, nil};

        false ->
            {error, {protocol_error, <<"hashes dont match"/utf8>>}}
    end.

-file("src/peer_protocol.gleam", 241).
-spec request_piece(mug:socket(), piece_download()) -> {ok, nil} |
    {error, protocol_error()}.
request_piece(Socket, Piece) ->
    {piece_download, Index, Length, _, Offset, _} = Piece,
    Block_length = gleam@int:min(Length - Offset, 16384),
    Req = {request, Index, Offset, Block_length},
    Id = peer_message_id(Req),
    Request_message = <<13:4/big-unit:8,
        Id/integer,
        (erlang:element(2, Req)):4/big-unit:8,
        (erlang:element(3, Req)):4/big-unit:8,
        (erlang:element(4, Req)):4/big-unit:8>>,
    _pipe = mug:send(Socket, Request_message),
    gleam@result:map_error(_pipe, fun(Field@0) -> {t_c_p_error, Field@0} end).

-file("src/peer_protocol.gleam", 208).
-spec handle_piece_block(peer_message(), piece_download()) -> {ok,
        piece_download()} |
    {error, protocol_error()}.
handle_piece_block(Message, Piece) ->
    {Peer_piece_index@1, Begin@1, Block@1} = case Message of
        {piece, Peer_piece_index, Begin, Block} -> {
        Peer_piece_index,
            Begin,
            Block};
        _assert_fail ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"peer_protocol"/utf8>>,
                        function => <<"handle_piece_block"/utf8>>,
                        line => 212,
                        value => _assert_fail,
                        start => 5255,
                        'end' => 5313,
                        pattern_start => 5266,
                        pattern_end => 5303})
    end,
    gleam@bool:guard(
        Peer_piece_index@1 /= erlang:element(2, Piece),
        {error, {protocol_error, <<"piece index mismatch"/utf8>>}},
        fun() ->
            gleam@bool:guard(
                Begin@1 /= erlang:element(5, Piece),
                {error, {protocol_error, <<"piece index mismatch"/utf8>>}},
                fun() ->
                    Rem = erlang:element(3, Piece) - Begin@1,
                    Expected_length = case Rem > 16384 of
                        true ->
                            16384;

                        false ->
                            Rem
                    end,
                    Rx_block_size = erlang:byte_size(Block@1),
                    gleam@bool:guard(
                        Rx_block_size /= Expected_length,
                        {error, {protocol_error, <<"incomplete block"/utf8>>}},
                        fun() ->
                            {ok,
                                {piece_download,
                                    erlang:element(2, Piece),
                                    erlang:element(3, Piece),
                                    erlang:element(4, Piece),
                                    erlang:element(5, Piece) + Rx_block_size,
                                    [Block@1 | erlang:element(6, Piece)]}}
                        end
                    )
                end
            )
        end
    ).

-file("src/peer_protocol.gleam", 185).
-spec handle_bit_field(mug:socket(), bitstring(), peer_state()) -> {ok,
        peer_state()} |
    {error, protocol_error()}.
handle_bit_field(Socket, Payload, State) ->
    Interested = true,
    case Interested of
        true ->
            Id = peer_message_id(interested),
            Message = <<1:4/big-unit:8, Id/integer>>,
            gleam@result:'try'(
                begin
                    _pipe = mug:send(Socket, Message),
                    gleam@result:map_error(
                        _pipe,
                        fun(Field@0) -> {t_c_p_error, Field@0} end
                    )
                end,
                fun(_) -> {ok, {peer_state, erlang:element(2, State), true}} end
            );

        false ->
            Id@1 = peer_message_id(not_interested),
            Message@1 = <<1:4/big-unit:8, Id@1/integer>>,
            gleam@result:'try'(
                begin
                    _pipe@1 = mug:send(Socket, Message@1),
                    gleam@result:map_error(
                        _pipe@1,
                        fun(Field@0) -> {t_c_p_error, Field@0} end
                    )
                end,
                fun(_) ->
                    {ok, {peer_state, erlang:element(2, State), false}}
                end
            )
    end.

-file("src/peer_protocol.gleam", 280).
-spec parse_message(bitstring()) -> {ok, peer_message()} |
    {error, protocol_error()}.
parse_message(Message) ->
    {Message_id@1, Payload@1} = case Message of
        <<Message_id, Payload/bitstring>> -> {Message_id, Payload};
        _assert_fail ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"peer_protocol"/utf8>>,
                        function => <<"parse_message"/utf8>>,
                        line => 281,
                        value => _assert_fail,
                        start => 7127,
                        'end' => 7176,
                        pattern_start => 7138,
                        pattern_end => 7166})
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
                                module => <<"peer_protocol"/utf8>>,
                                function => <<"parse_message"/utf8>>,
                                line => 290,
                                value => _assert_fail@1,
                                start => 7354,
                                'end' => 7498,
                                pattern_start => 7365,
                                pattern_end => 7488})
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
                                module => <<"peer_protocol"/utf8>>,
                                function => <<"parse_message"/utf8>>,
                                line => 298,
                                value => _assert_fail@2,
                                start => 7568,
                                'end' => 7696,
                                pattern_start => 7579,
                                pattern_end => 7686})
            end,
            {ok, {piece, Piece_index@3, Begin@3, Block@1}};

        Id ->
            {error, {unknown_message_id, Id}}
    end.

-file("src/peer_protocol.gleam", 261).
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
                                module => <<"peer_protocol"/utf8>>,
                                function => <<"receive_message"/utf8>>,
                                line => 265,
                                value => _assert_fail,
                                start => 6725,
                                'end' => 6786,
                                pattern_start => 6736,
                                pattern_end => 6779})
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

-file("src/peer_protocol.gleam", 169).
-spec continue(mug:socket(), peer_state(), piece_download()) -> {ok,
        peer_outcome()} |
    {error, protocol_error()}.
continue(Socket, State, Piece) ->
    case State of
        {peer_state, _, false} ->
            {ok, peer_does_not_have_piece};

        {peer_state, false, true} ->
            gleam@result:'try'(
                request_piece(Socket, Piece),
                fun(_) -> peer_exchange(Socket, State, Piece) end
            );

        {peer_state, true, true} ->
            peer_exchange(Socket, State, Piece)
    end.

-file("src/peer_protocol.gleam", 135).
-spec peer_exchange(mug:socket(), peer_state(), piece_download()) -> {ok,
        peer_outcome()} |
    {error, protocol_error()}.
peer_exchange(Socket, State, Piece) ->
    gleam@result:'try'(receive_message(Socket), fun(Message) -> case Message of
                choke ->
                    continue(
                        Socket,
                        {peer_state, true, erlang:element(3, State)},
                        Piece
                    );

                unchoke ->
                    continue(
                        Socket,
                        {peer_state, false, erlang:element(3, State)},
                        Piece
                    );

                have ->
                    peer_exchange(Socket, State, Piece);

                {bit_field, Payload} ->
                    gleam@result:'try'(
                        handle_bit_field(Socket, Payload, State),
                        fun(State@1) -> continue(Socket, State@1, Piece) end
                    );

                {piece, _, _, _} ->
                    gleam@result:'try'(
                        handle_piece_block(Message, Piece),
                        fun(Piece@1) ->
                            case erlang:element(5, Piece@1) =:= erlang:element(
                                3,
                                Piece@1
                            ) of
                                false ->
                                    gleam@result:'try'(
                                        request_piece(Socket, Piece@1),
                                        fun(_) ->
                                            peer_exchange(
                                                Socket,
                                                State,
                                                Piece@1
                                            )
                                        end
                                    );

                                true ->
                                    Binary = begin
                                        _pipe = lists:reverse(
                                            erlang:element(6, Piece@1)
                                        ),
                                        gleam_stdlib:bit_array_concat(_pipe)
                                    end,
                                    gleam@result:'try'(
                                        verify_piece(
                                            Binary,
                                            erlang:element(4, Piece@1)
                                        ),
                                        fun(_) ->
                                            {ok, {piece_downloaded, Binary}}
                                        end
                                    )
                            end
                        end
                    );

                Message@1 ->
                    {error, {unexpected_message, peer_message_id(Message@1)}}
            end end).

-file("src/peer_protocol.gleam", 100).
-spec peer_handshake(mug:socket(), bitstring(), bitstring()) -> {ok,
        bitstring()} |
    {error, protocol_error()}.
peer_handshake(Socket, Info_hash, Peer_id) ->
    Handshake_msg_length = ((20 + 8) + 20) + 20,
    Handshake_msg = <<19/integer,
        "BitTorrent protocol"/utf8,
        0:8/unit:8,
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
                        Handshake_msg_length,
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
                            _:8/unit:8,
                            Rev_info_hash:20/binary-unit:8,
                            Peer_id@1:20/binary-unit:8>> ->
                            case Rev_info_hash =:= Info_hash of
                                true ->
                                    {ok, Peer_id@1};

                                false ->
                                    {error, info_hash_mismatch}
                            end;

                        _ ->
                            {error, invalid_response}
                    end end
            )
        end
    ).

-file("src/peer_protocol.gleam", 85).
-spec connect(binary(), integer()) -> {ok, mug:socket()} |
    {error, protocol_error()}.
connect(Host, Port) ->
    _pipe = mug:connect({connection_options, Host, Port, 5000, ipv4_only}),
    gleam@result:map_error(_pipe, fun(Err) -> case Err of
                {connect_failed_ipv4, Err@1} ->
                    {t_c_p_error, Err@1};

                _ ->
                    erlang:error(#{gleam_error => panic,
                            message => <<"`panic` expression evaluated."/utf8>>,
                            file => <<?FILEPATH/utf8>>,
                            module => <<"peer_protocol"/utf8>>,
                            function => <<"connect"/utf8>>,
                            line => 95})
            end end).

-file("src/peer_protocol.gleam", 343).
-spec validate_endpoint(binary()) -> {ok, {binary(), integer()}} | {error, nil}.
validate_endpoint(Endpoint) ->
    case gleam@string:split(Endpoint, <<":"/utf8>>) of
        [Ipv4, Port_str] ->
            gleam@result:'try'(
                gleam_stdlib:parse_int(Port_str),
                fun(Port) -> {ok, {Ipv4, Port}} end
            );

        _ ->
            {error, nil}
    end.

-file("src/peer_protocol.gleam", 55).
-spec one_piece(
    bencode:torrent(),
    binary(),
    integer(),
    bitstring(),
    bitstring()
) -> {ok, bitstring()} | {error, protocol_error()}.
one_piece(Torrent, Endpoint, Piece_index, Piece_hash, Peer_id) ->
    gleam@result:'try'(
        begin
            _pipe = validate_endpoint(Endpoint),
            gleam@result:replace_error(_pipe, invalid_endpoint)
        end,
        fun(_use0) ->
            {Ip4_addr, Port} = _use0,
            gleam@result:'try'(
                connect(Ip4_addr, Port),
                fun(Socket) ->
                    gleam@result:'try'(
                        peer_handshake(
                            Socket,
                            erlang:element(7, Torrent),
                            Peer_id
                        ),
                        fun(_) ->
                            gleam@result:'try'(
                                peer_exchange(
                                    Socket,
                                    {peer_state, true, false},
                                    {piece_download,
                                        Piece_index,
                                        piece_length(
                                            Piece_index,
                                            erlang:element(4, Torrent),
                                            erlang:element(5, Torrent)
                                        ),
                                        Piece_hash,
                                        0,
                                        []}
                                ),
                                fun(Outcome) -> case Outcome of
                                        {piece_downloaded, Piece} ->
                                            {ok, Piece};

                                        peer_does_not_have_piece ->
                                            {error,
                                                {protocol_error,
                                                    <<"They dont have it"/utf8>>}}
                                    end end
                            )
                        end
                    )
                end
            )
        end
    ).

-file("src/peer_protocol.gleam", 353).
-spec handshake(binary(), bencode:torrent(), bitstring()) -> {ok, bitstring()} |
    {error, protocol_error()}.
handshake(Endpoint, Torrent, Peer_id) ->
    gleam@result:'try'(
        begin
            _pipe = validate_endpoint(Endpoint),
            gleam@result:replace_error(_pipe, invalid_endpoint)
        end,
        fun(_use0) ->
            {Ip4_addr, Port} = _use0,
            gleam@result:'try'(
                connect(Ip4_addr, Port),
                fun(Socket) ->
                    peer_handshake(Socket, erlang:element(7, Torrent), Peer_id)
                end
            )
        end
    ).

-file("src/peer_protocol.gleam", 365).
-spec describe_error(protocol_error()) -> binary().
describe_error(Error) ->
    case Error of
        invalid_endpoint ->
            <<"Invalid endpoint. Expected <ip>:<port>."/utf8>>;

        invalid_response ->
            <<"Received an invalid response from the peer"/utf8>>;

        info_hash_mismatch ->
            <<"Peer responded with a different info hash"/utf8>>;

        {t_c_p_error, Err} ->
            mug:describe_error(Err);

        {protocol_error, Err@1} ->
            Err@1;

        {unknown_message_id, Msg_id} ->
            <<"Unknown Message Id "/utf8,
                (erlang:integer_to_binary(Msg_id))/binary>>;

        {unexpected_message, Msg_id@1} ->
            <<"Unexpected peer message: "/utf8,
                (erlang:integer_to_binary(Msg_id@1))/binary>>
    end.
