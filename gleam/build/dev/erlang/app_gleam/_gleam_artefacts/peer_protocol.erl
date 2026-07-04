-module(peer_protocol).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/peer_protocol.gleam").
-export([new_peer/2, new_piece/3, one_piece/5, peer_handshake/3, connect/2, fetch_pieces/3, handshake/3, describe_error/1]).
-export_type([protocol_error/0, peer_message/0, peer_state/0, piece_download/0, peer_outcome/0]).

-type protocol_error() :: invalid_endpoint |
    invalid_response |
    info_hash_mismatch |
    {file_error, simplifile:file_error()} |
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

-type peer_state() :: {peer_state,
        binary(),
        binary(),
        boolean(),
        boolean(),
        gleam@option:option(bitstring())}.

-type piece_download() :: {piece_download,
        integer(),
        integer(),
        bitstring(),
        integer(),
        list(bitstring())}.

-type peer_outcome() :: {piece_downloaded, bitstring()} |
    peer_does_not_have_piece.

-file("src/peer_protocol.gleam", 64).
-spec new_peer(binary(), binary()) -> peer_state().
new_peer(Endpoint, Download_path) ->
    {peer_state, Endpoint, Download_path, true, false, none}.

-file("src/peer_protocol.gleam", 367).
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

-file("src/peer_protocol.gleam", 380).
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

-file("src/peer_protocol.gleam", 267).
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
                        line => 271,
                        value => _assert_fail,
                        start => 6667,
                        'end' => 6725,
                        pattern_start => 6678,
                        pattern_end => 6715})
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

-file("src/peer_protocol.gleam", 244).
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
                fun(_) ->
                    {ok,
                        {peer_state,
                            erlang:element(2, State),
                            erlang:element(3, State),
                            erlang:element(4, State),
                            true,
                            erlang:element(6, State)}}
                end
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
                    {ok,
                        {peer_state,
                            erlang:element(2, State),
                            erlang:element(3, State),
                            erlang:element(4, State),
                            false,
                            erlang:element(6, State)}}
                end
            )
    end.

-file("src/peer_protocol.gleam", 187).
-spec log(peer_message()) -> peer_message().
log(M) ->
    case M of
        {piece, Piece_index, Begin, _} ->
            {piece, erlang:element(2, M), erlang:element(3, M), <<>>};

        _ ->
            M
    end.

-file("src/peer_protocol.gleam", 338).
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
                        line => 339,
                        value => _assert_fail,
                        start => 8538,
                        'end' => 8587,
                        pattern_start => 8549,
                        pattern_end => 8577})
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
                                line => 348,
                                value => _assert_fail@1,
                                start => 8765,
                                'end' => 8909,
                                pattern_start => 8776,
                                pattern_end => 8899})
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
                                line => 356,
                                value => _assert_fail@2,
                                start => 8979,
                                'end' => 9107,
                                pattern_start => 8990,
                                pattern_end => 9097})
            end,
            {ok, {piece, Piece_index@3, Begin@3, Block@1}};

        Id ->
            {error, {unknown_message_id, Id}}
    end.

-file("src/peer_protocol.gleam", 319).
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
                                line => 323,
                                value => _assert_fail,
                                start => 8136,
                                'end' => 8197,
                                pattern_start => 8147,
                                pattern_end => 8190})
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

-file("src/peer_protocol.gleam", 299).
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

-file("src/peer_protocol.gleam", 194).
-spec continue(mug:socket(), peer_state(), piece_download()) -> {ok,
        {peer_state(), peer_outcome()}} |
    {error, protocol_error()}.
continue(Socket, State, Piece) ->
    gleam@result:'try'(
        receive_message(Socket),
        fun(Message) ->
            echo(log(Message), nil, 200),
            case Message of
                choke ->
                    peer_exchange(
                        Socket,
                        {peer_state,
                            erlang:element(2, State),
                            erlang:element(3, State),
                            true,
                            erlang:element(5, State),
                            erlang:element(6, State)},
                        Piece
                    );

                unchoke ->
                    peer_exchange(
                        Socket,
                        {peer_state,
                            erlang:element(2, State),
                            erlang:element(3, State),
                            false,
                            erlang:element(5, State),
                            erlang:element(6, State)},
                        Piece
                    );

                have ->
                    peer_exchange(Socket, State, Piece);

                {bit_field, Payload} ->
                    gleam@result:'try'(
                        handle_bit_field(Socket, Payload, State),
                        fun(State@1) ->
                            peer_exchange(Socket, State@1, Piece)
                        end
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
                                    peer_exchange(Socket, State, Piece@1);

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
                                            {ok,
                                                {State,
                                                    {piece_downloaded, Binary}}}
                                        end
                                    )
                            end
                        end
                    );

                Message@1 ->
                    {error, {unexpected_message, peer_message_id(Message@1)}}
            end
        end
    ).

-file("src/peer_protocol.gleam", 225).
-spec peer_exchange(mug:socket(), peer_state(), piece_download()) -> {ok,
        {peer_state(), peer_outcome()}} |
    {error, protocol_error()}.
peer_exchange(Socket, State, Piece) ->
    case State of
        {peer_state, _, _, _, false, none} ->
            continue(Socket, State, Piece);

        {peer_state, _, _, _, false, {some, _}} ->
            {ok, {State, peer_does_not_have_piece}};

        {peer_state, _, _, false, true, _} ->
            gleam@result:'try'(
                request_piece(Socket, Piece),
                fun(_) -> continue(Socket, State, Piece) end
            );

        {peer_state, _, _, true, true, _} ->
            continue(Socket, State, Piece)
    end.

-file("src/peer_protocol.gleam", 89).
-spec new_piece(integer(), integer(), bitstring()) -> piece_download().
new_piece(Piece_index, Length, Piece_hash) ->
    {piece_download, Piece_index, Length, Piece_hash, 0, []}.

-file("src/peer_protocol.gleam", 389).
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

-file("src/peer_protocol.gleam", 103).
-spec one_piece(
    mug:socket(),
    bencode:torrent(),
    peer_state(),
    list(bitstring()),
    integer()
) -> {ok, nil} | {error, protocol_error()}.
one_piece(Socket, Torrent, State, Pieces, Piece_index) ->
    case Pieces of
        [Piece_hash | Rest] ->
            Length = piece_length(
                Piece_index,
                erlang:element(4, Torrent),
                erlang:element(5, Torrent)
            ),
            Piece_downlaod = new_piece(Piece_index, Length, Piece_hash),
            gleam@result:'try'(
                peer_exchange(Socket, State, Piece_downlaod),
                fun(_use0) ->
                    {New_state, Outcome} = _use0,
                    case Outcome of
                        {piece_downloaded, Piece} ->
                            gleam@result:'try'(
                                begin
                                    _pipe = simplifile_erl:append_bits(
                                        erlang:element(3, New_state),
                                        Piece
                                    ),
                                    gleam@result:map_error(
                                        _pipe,
                                        fun(Field@0) -> {file_error, Field@0} end
                                    )
                                end,
                                fun(_) ->
                                    one_piece(
                                        Socket,
                                        Torrent,
                                        New_state,
                                        Rest,
                                        Piece_index + 1
                                    )
                                end
                            );

                        peer_does_not_have_piece ->
                            one_piece(
                                Socket,
                                Torrent,
                                New_state,
                                Rest,
                                Piece_index + 1
                            )
                    end
                end
            );

        [] ->
            {ok, nil}
    end.

-file("src/peer_protocol.gleam", 152).
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

-file("src/peer_protocol.gleam", 137).
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
                            line => 147})
            end end).

-file("src/peer_protocol.gleam", 401).
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

-file("src/peer_protocol.gleam", 74).
-spec fetch_pieces(bencode:torrent(), peer_state(), bitstring()) -> {ok, nil} |
    {error, protocol_error()}.
fetch_pieces(Torrent, State, Peer_id) ->
    gleam@result:'try'(
        begin
            _pipe = validate_endpoint(erlang:element(2, State)),
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
                            _pipe@1 = one_piece(
                                Socket,
                                Torrent,
                                State,
                                erlang:element(6, Torrent),
                                0
                            ),
                            gleam@result:replace(_pipe@1, nil)
                        end
                    )
                end
            )
        end
    ).

-file("src/peer_protocol.gleam", 411).
-spec handshake(binary(), bencode:torrent(), bitstring()) -> {ok,
        {mug:socket(), bitstring()}} |
    {error, protocol_error()}.
handshake(Endpoint, Torrent, Peer_id) ->
    gleam@result:'try'(
        begin
            _pipe = validate_endpoint(Endpoint),
            gleam@result:replace_error(_pipe, invalid_endpoint)
        end,
        fun(_use0) ->
            {Ip4_addr, Port} = _use0,
            echo(<<"coon"/utf8>>, nil, 419),
            gleam@result:'try'(
                connect(Ip4_addr, Port),
                fun(Socket) ->
                    gleam@result:'try'(
                        peer_handshake(
                            Socket,
                            erlang:element(7, Torrent),
                            Peer_id
                        ),
                        fun(Peer_peer_id) -> {ok, {Socket, Peer_peer_id}} end
                    )
                end
            )
        end
    ).

-file("src/peer_protocol.gleam", 425).
-spec describe_error(protocol_error()) -> binary().
describe_error(Error) ->
    case Error of
        invalid_endpoint ->
            <<"Invalid endpoint. Expected <ip>:<port>."/utf8>>;

        invalid_response ->
            <<"Received an invalid response from the peer"/utf8>>;

        info_hash_mismatch ->
            <<"Peer responded with a different info hash"/utf8>>;

        {file_error, Err} ->
            simplifile:describe_error(Err);

        {t_c_p_error, Err@1} ->
            mug:describe_error(Err@1);

        {protocol_error, Err@2} ->
            Err@2;

        {unknown_message_id, Msg_id} ->
            <<"Unknown Message Id "/utf8,
                (erlang:integer_to_binary(Msg_id))/binary>>;

        {unexpected_message, Msg_id@1} ->
            <<"Unexpected peer message: "/utf8,
                (erlang:integer_to_binary(Msg_id@1))/binary>>
    end.

-define(is_lowercase_char(X),
    (X > 96 andalso X < 123)).

-define(is_underscore_char(X),
    (X == 95)).

-define(is_digit_char(X),
    (X > 47 andalso X < 58)).

-define(is_ascii_character(X),
    (erlang:is_integer(X) andalso X >= 32 andalso X =< 126)).

-define(could_be_record(Tuple),
    erlang:is_tuple(Tuple) andalso
        erlang:is_atom(erlang:element(1, Tuple)) andalso
        erlang:element(1, Tuple) =/= false andalso
        erlang:element(1, Tuple) =/= true andalso
        erlang:element(1, Tuple) =/= nil
).
-define(is_atom_char(C),
    (?is_lowercase_char(C) orelse
        ?is_underscore_char(C) orelse
        ?is_digit_char(C))
).

-define(grey, "\e[90m").
-define(reset_color, "\e[39m").

echo(Value, Message, Line) ->
    StringLine = erlang:integer_to_list(Line),
    StringValue = echo@inspect(Value),
    StringMessage =
        case Message of
            nil -> "";
            M -> [" ", M]
        end,

    io:put_chars(
      standard_error,
      [
        ?grey, ?FILEPATH, $:, StringLine, ?reset_color, StringMessage, $\n,
        StringValue, $\n
      ]
    ),
    Value.

echo@inspect(Value) ->
    case Value of
        nil -> "Nil";
        true -> "True";
        false -> "False";
        Int when erlang:is_integer(Int) -> erlang:integer_to_list(Int);
        Float when erlang:is_float(Float) -> io_lib_format:fwrite_g(Float);
        Binary when erlang:is_binary(Binary) -> inspect@binary(Binary);
        Bits when erlang:is_bitstring(Bits) -> inspect@bit_array(Bits);
        Atom when erlang:is_atom(Atom) -> inspect@atom(Atom);
        List when erlang:is_list(List) -> inspect@list(List);
        Map when erlang:is_map(Map) -> inspect@map(Map);
        Record when ?could_be_record(Record) -> inspect@record(Record);
        Tuple when erlang:is_tuple(Tuple) -> inspect@tuple(Tuple);
        Function when erlang:is_function(Function) -> inspect@function(Function);
        Any -> ["//erl(", io_lib:format("~p", [Any]), ")"]
    end.

inspect@bit_array(Bits) ->
    Pieces = inspect@bit_array_pieces(Bits, []),
    Inner = lists:join(", ", lists:reverse(Pieces)),
    ["<<", Inner, ">>"].

inspect@bit_array_pieces(Bits, Acc) ->
    case Bits of
        <<>> ->
            Acc;
        <<Byte, Rest/bitstring>> ->
            inspect@bit_array_pieces(Rest, [erlang:integer_to_binary(Byte) | Acc]);
        _ ->
            Size = erlang:bit_size(Bits),
            <<RemainingBits:Size>> = Bits,
            SizeString = [":size(", erlang:integer_to_binary(Size), ")"],
            Piece = [erlang:integer_to_binary(RemainingBits), SizeString],
            [Piece | Acc]
    end.

inspect@binary(Binary) ->
    case inspect@maybe_utf8_string(Binary, <<>>) of
        {ok, InspectedUtf8String} ->
            InspectedUtf8String;
        {error, not_a_utf8_string} ->
            Segments = [erlang:integer_to_list(X) || <<X>> <= Binary],
            ["<<", lists:join(", ", Segments), ">>"]
    end.

inspect@atom(Atom) ->
    Binary = erlang:atom_to_binary(Atom),
    case inspect@maybe_gleam_atom(Binary, none, <<>>) of
        {ok, Inspected} -> Inspected;
        {error, _} -> ["atom.create(\"", Binary, "\")"]
    end.

inspect@list(List) ->
    case inspect@list_loop(List, true) of
        {charlist, _} -> ["charlist.from_string(\"", erlang:list_to_binary(List), "\")"];
        {proper, Elements} -> ["[", Elements, "]"];
        {improper, Elements} -> ["//erl([", Elements, "])"]
    end.

inspect@map(Map) ->
    Fields = [
        [<<"#(">>, echo@inspect(Key), <<", ">>, echo@inspect(Value), <<")">>]
        || {Key, Value} <- maps:to_list(Map)
    ],
    ["dict.from_list([", lists:join(", ", Fields), "])"].

inspect@record(Record) ->
    [Atom | ArgsList] = Tuple = erlang:tuple_to_list(Record),
    case inspect@maybe_gleam_atom(Atom, none, <<>>) of
        {ok, Tag} ->
            Args = lists:join(", ", lists:map(fun echo@inspect/1, ArgsList)),
            [Tag, "(", Args, ")"];
        _ ->
            inspect@tuple(Tuple)
    end.

inspect@tuple(Tuple) when erlang:is_tuple(Tuple) ->
    inspect@tuple(erlang:tuple_to_list(Tuple));
inspect@tuple(Tuple) ->
    Elements = lists:map(fun echo@inspect/1, Tuple),
    ["#(", lists:join(", ", Elements), ")"].

inspect@function(Function) ->
    {arity, Arity} = erlang:fun_info(Function, arity),
    ArgsAsciiCodes = lists:seq($a, $a + Arity - 1),
    Args = lists:join(", ", lists:map(fun(Arg) -> <<Arg>> end, ArgsAsciiCodes)),
    ["//fn(", Args, ") { ... }"].

inspect@maybe_utf8_string(Binary, Acc) ->
    case Binary of
        <<>> ->
            {ok, <<$", Acc/binary, $">>};
        <<First/utf8, Rest/binary>> ->
            Escaped = inspect@escape_grapheme(First),
            inspect@maybe_utf8_string(Rest, <<Acc/binary, Escaped/binary>>);
        _ ->
            {error, not_a_utf8_string}
    end.

inspect@escape_grapheme(Char) ->
    case Char of
        $" -> <<$\\, $">>;
        $\\ -> <<$\\, $\\>>;
        $\r -> <<$\\, $r>>;
        $\n -> <<$\\, $n>>;
        $\t -> <<$\\, $t>>;
        $\f -> <<$\\, $f>>;
        X when X > 126, X < 160 -> inspect@convert_to_u(X);
        X when X < 32 -> inspect@convert_to_u(X);
        Other -> <<Other/utf8>>
    end.

inspect@convert_to_u(Code) ->
    erlang:list_to_binary(io_lib:format("\\u{~4.16.0B}", [Code])).

inspect@list_loop(List, Ascii) ->
    case List of
        [] ->
            {proper, []};
        [First] when Ascii andalso ?is_ascii_character(First) ->
            {charlist, nil};
        [First] ->
            {proper, [echo@inspect(First)]};
        [First | Rest] when erlang:is_list(Rest) ->
            StillAscii = Ascii andalso ?is_ascii_character(First),
            {Kind, Inspected} = inspect@list_loop(Rest, StillAscii),
            {Kind, [echo@inspect(First), ", " | Inspected]};
        [First | ImproperRest] ->
            {improper, [echo@inspect(First), " | ", echo@inspect(ImproperRest)]}
    end.

inspect@maybe_gleam_atom(Atom, PrevChar, Acc) when erlang:is_atom(Atom) ->
    Binary = erlang:atom_to_binary(Atom),
    inspect@maybe_gleam_atom(Binary, PrevChar, Acc);
inspect@maybe_gleam_atom(Atom, PrevChar, Acc) ->
    case {Atom, PrevChar} of
        {<<>>, none} ->
            {error, nil};
        {<<First, _/binary>>, none} when ?is_digit_char(First) ->
            {error, nil};
        {<<"_", _/binary>>, none} ->
            {error, nil};
        {<<"_">>, _} ->
            {error, nil};
        {<<"_", _/binary>>, $_} ->
            {error, nil};
        {<<First, _/binary>>, _} when not ?is_atom_char(First) ->
            {error, nil};
        {<<First, Rest/binary>>, none} ->
            inspect@maybe_gleam_atom(Rest, First, <<Acc/binary, (inspect@uppercase(First))>>);
        {<<"_", Rest/binary>>, _} ->
            inspect@maybe_gleam_atom(Rest, $_, Acc);
        {<<First, Rest/binary>>, $_} ->
            inspect@maybe_gleam_atom(Rest, First, <<Acc/binary, (inspect@uppercase(First))>>);
        {<<First, Rest/binary>>, _} ->
            inspect@maybe_gleam_atom(Rest, First, <<Acc/binary, First>>);
        {<<>>, _} ->
            {ok, Acc};
        _ ->
            erlang:throw({gleam_error, echo, Atom, PrevChar, Acc})
    end.

inspect@uppercase(X) -> X - 32.

