-module(torrent@peer@session).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/torrent/peer/session.gleam").
-export([piece_block_requests/1, new_piece_download/1, new_session/2, describe_error/1, is_any_bit_set/1, start_session/3, download_piece/3]).
-export_type([piece_download/0, peer_session/0, block_request/0, piece_result/0, peer_error/0]).

-type piece_download() :: {piece_download,
        torrent@torrent:piece_info(),
        gleam@dict:dict(integer(), bitstring()),
        list(block_request()),
        gleam@dict:dict(integer(), block_request())}.

-type peer_session() :: {peer_session,
        mug:socket(),
        torrent@peer@protocol:peer_id(),
        bitstring(),
        gleam@option:option(piece_download()),
        boolean(),
        boolean()}.

-type block_request() :: {block_request, integer(), integer()}.

-type piece_result() :: {piece_result, peer_session(), bitstring()}.

-type peer_error() :: {peer_error, binary()} |
    {unexpected_message, integer()} |
    {protocol_error, torrent@peer@protocol:protocol_error()} |
    piece_hash_mismatch |
    invalid_block |
    duplicate_bitfield.

-file("src/torrent/peer/session.gleam", 308).
-spec piece_block_requests_loop(integer(), integer(), list(block_request())) -> list(block_request()).
piece_block_requests_loop(Length, Block, Requests) ->
    case Block < 0 of
        false ->
            Begin = Block * 16384,
            Block_length = gleam@int:min(16384, Length - Begin),
            Request = {block_request, Begin, Block_length},
            piece_block_requests_loop(Length, Block - 1, [Request | Requests]);

        true ->
            Requests
    end.

-file("src/torrent/peer/session.gleam", 302).
-spec piece_block_requests(integer()) -> list(block_request()).
piece_block_requests(Piece_length) ->
    Block_count = case 16384 of
        0 -> 0;
        Gleam@denominator -> ((Piece_length + 16384) - 1) div Gleam@denominator
    end,
    piece_block_requests_loop(Piece_length, Block_count - 1, []).

-file("src/torrent/peer/session.gleam", 26).
-spec new_piece_download(torrent@torrent:piece_info()) -> piece_download().
new_piece_download(Piece) ->
    {piece_download,
        Piece,
        maps:new(),
        piece_block_requests(erlang:element(4, Piece)),
        maps:new()}.

-file("src/torrent/peer/session.gleam", 46).
-spec new_session(mug:socket(), torrent@peer@protocol:peer_id()) -> peer_session().
new_session(Socket, Peer_id) ->
    {peer_session, Socket, Peer_id, <<>>, none, true, false}.

-file("src/torrent/peer/session.gleam", 346).
-spec describe_error(peer_error()) -> binary().
describe_error(Error) ->
    case Error of
        {peer_error, Reason} ->
            <<"Peer connection error: "/utf8, Reason/binary>>;

        {unexpected_message, Id} ->
            <<"Received an unexpected protocol message ID: "/utf8,
                (erlang:integer_to_binary(Id))/binary>>;

        {protocol_error, Protocol_err} ->
            <<"BitTorrent protocol validation failed: "/utf8,
                (torrent@peer@protocol:describe_error(Protocol_err))/binary>>;

        piece_hash_mismatch ->
            <<"Data integrity check failed: downloaded piece hash does not match the torrent file info-hash"/utf8>>;

        invalid_block ->
            <<"Received an invalid data block length, offset, or payload structural format"/utf8>>;

        duplicate_bitfield ->
            <<"Protocol violation: peer attempted to send a duplicate bitfield message after connection setup"/utf8>>
    end.

-file("src/torrent/peer/session.gleam", 287).
-spec verify_piece(bitstring(), bitstring()) -> {ok, nil} |
    {error, peer_error()}.
verify_piece(Binary, Hash) ->
    Calc = gleam@crypto:hash(sha1, Binary),
    case Calc =:= Hash of
        true ->
            {ok, nil};

        false ->
            {error, piece_hash_mismatch}
    end.

-file("src/torrent/peer/session.gleam", 175).
-spec handle_piece_complete(piece_download()) -> {ok, bitstring()} |
    {error, peer_error()}.
handle_piece_complete(Piece) ->
    gleam@result:'try'(
        begin
            _pipe = piece_block_requests(
                erlang:element(4, erlang:element(2, Piece))
            ),
            gleam@list:try_map(
                _pipe,
                fun(Req) ->
                    _pipe@1 = gleam_stdlib:map_get(
                        erlang:element(3, Piece),
                        erlang:element(2, Req)
                    ),
                    gleam@result:replace_error(_pipe@1, invalid_block)
                end
            )
        end,
        fun(Blocks) ->
            Data = gleam_stdlib:bit_array_concat(Blocks),
            gleam@result:'try'(
                verify_piece(Data, erlang:element(3, erlang:element(2, Piece))),
                fun(_) -> {ok, Data} end
            )
        end
    ).

-file("src/torrent/peer/session.gleam", 244).
-spec handle_piece_block(peer_session(), torrent@peer@protocol:peer_message()) -> {ok,
        piece_download()} |
    {error, peer_error()}.
handle_piece_block(Session, Message) ->
    Piece@1 = case erlang:element(5, Session) of
        {some, Piece} -> Piece;
        _assert_fail ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"torrent/peer/session"/utf8>>,
                        function => <<"handle_piece_block"/utf8>>,
                        line => 248,
                        value => _assert_fail,
                        start => 6834,
                        'end' => 6872,
                        pattern_start => 6845,
                        pattern_end => 6856})
    end,
    {Peer_piece_index@1, Begin@1, Block@1} = case Message of
        {piece, Peer_piece_index, Begin, Block} -> {
        Peer_piece_index,
            Begin,
            Block};
        _assert_fail@1 ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"torrent/peer/session"/utf8>>,
                        function => <<"handle_piece_block"/utf8>>,
                        line => 249,
                        value => _assert_fail@1,
                        start => 6875,
                        'end' => 6933,
                        pattern_start => 6886,
                        pattern_end => 6923})
    end,
    gleam@bool:guard(
        Peer_piece_index@1 /= erlang:element(2, erlang:element(2, Piece@1)),
        {error, {peer_error, <<"piece index mismatch"/utf8>>}},
        fun() ->
            Outstanding = gleam_stdlib:map_get(
                erlang:element(5, Piece@1),
                Begin@1
            ),
            case Outstanding of
                {ok, Block_request} ->
                    gleam@bool:guard(
                        Begin@1 /= erlang:element(2, Block_request),
                        {error,
                            {peer_error, <<"piece block offset mismatch"/utf8>>}},
                        fun() ->
                            Rem = erlang:element(4, erlang:element(2, Piece@1))
                            - Begin@1,
                            Expected_block_size = case Rem > 16384 of
                                true ->
                                    16384;

                                false ->
                                    Rem
                            end,
                            Rx_block_size = erlang:byte_size(Block@1),
                            gleam@bool:guard(
                                Rx_block_size /= Expected_block_size,
                                {error,
                                    {peer_error, <<"incomplete block"/utf8>>}},
                                fun() ->
                                    Outstanding@1 = gleam@dict:delete(
                                        erlang:element(5, Piece@1),
                                        Begin@1
                                    ),
                                    New_blocks = gleam@dict:insert(
                                        erlang:element(3, Piece@1),
                                        Begin@1,
                                        Block@1
                                    ),
                                    _pipe = {piece_download,
                                        erlang:element(2, Piece@1),
                                        New_blocks,
                                        erlang:element(4, Piece@1),
                                        Outstanding@1},
                                    {ok, _pipe}
                                end
                            )
                        end
                    );

                {error, _} ->
                    {error, invalid_block}
            end
        end
    ).

-file("src/torrent/peer/session.gleam", 207).
-spec request_piece_blocks(peer_session()) -> {ok, peer_session()} |
    {error, peer_error()}.
request_piece_blocks(Session) ->
    Piece@1 = case erlang:element(5, Session) of
        {some, Piece} -> Piece;
        _assert_fail ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"torrent/peer/session"/utf8>>,
                        function => <<"request_piece_blocks"/utf8>>,
                        line => 210,
                        value => _assert_fail,
                        start => 5768,
                        'end' => 5806,
                        pattern_start => 5779,
                        pattern_end => 5790})
    end,
    Take = gleam@int:min(4, 4 - maps:size(erlang:element(5, Piece@1))),
    Remaining = gleam@list:drop(erlang:element(4, Piece@1), Take),
    Reqs = begin
        _pipe = erlang:element(4, Piece@1),
        gleam@list:take(_pipe, Take)
    end,
    gleam@result:'try'(
        gleam@list:try_each(
            Reqs,
            fun(Req) ->
                Id = 6,
                Request_message = <<13:4/big-unit:8,
                    Id/integer,
                    (erlang:element(2, erlang:element(2, Piece@1))):4/big-unit:8,
                    (erlang:element(2, Req)):4/big-unit:8,
                    (erlang:element(3, Req)):4/big-unit:8>>,
                _pipe@1 = torrent@peer@protocol:send_message(
                    erlang:element(2, Session),
                    Request_message
                ),
                gleam@result:map_error(
                    _pipe@1,
                    fun(Field@0) -> {protocol_error, Field@0} end
                )
            end
        ),
        fun(_) ->
            Outstanding@1 = gleam@list:fold(
                Reqs,
                erlang:element(5, Piece@1),
                fun(Outstanding, Req@1) ->
                    gleam@dict:insert(
                        Outstanding,
                        erlang:element(2, Req@1),
                        Req@1
                    )
                end
            ),
            New_piece = {piece_download,
                erlang:element(2, Piece@1),
                erlang:element(3, Piece@1),
                Remaining,
                Outstanding@1},
            {ok,
                {peer_session,
                    erlang:element(2, Session),
                    erlang:element(3, Session),
                    erlang:element(4, Session),
                    {some, New_piece},
                    erlang:element(6, Session),
                    erlang:element(7, Session)}}
        end
    ).

-file("src/torrent/peer/session.gleam", 147).
-spec peer_listen(peer_session()) -> {ok, piece_result()} |
    {error, peer_error()}.
peer_listen(Session) ->
    gleam@result:'try'(
        begin
            _pipe = torrent@peer@protocol:receive_message(
                erlang:element(2, Session)
            ),
            gleam@result:map_error(
                _pipe,
                fun(Field@0) -> {protocol_error, Field@0} end
            )
        end,
        fun(Message) -> case Message of
                choke ->
                    handle_piece(
                        {peer_session,
                            erlang:element(2, Session),
                            erlang:element(3, Session),
                            erlang:element(4, Session),
                            erlang:element(5, Session),
                            true,
                            erlang:element(7, Session)}
                    );

                unchoke ->
                    handle_piece(
                        {peer_session,
                            erlang:element(2, Session),
                            erlang:element(3, Session),
                            erlang:element(4, Session),
                            erlang:element(5, Session),
                            false,
                            erlang:element(7, Session)}
                    );

                have ->
                    handle_piece(Session);

                {bit_field, _} ->
                    {error, duplicate_bitfield};

                {piece, _, _, _} ->
                    gleam@result:'try'(
                        handle_piece_block(Session, Message),
                        fun(Piece) ->
                            case gleam@list:is_empty(erlang:element(4, Piece))
                            andalso gleam@dict:is_empty(
                                erlang:element(5, Piece)
                            ) of
                                true ->
                                    gleam@result:'try'(
                                        handle_piece_complete(Piece),
                                        fun(Piece@1) ->
                                            _pipe@1 = {piece_result,
                                                Session,
                                                Piece@1},
                                            {ok, _pipe@1}
                                        end
                                    );

                                false ->
                                    handle_piece(
                                        {peer_session,
                                            erlang:element(2, Session),
                                            erlang:element(3, Session),
                                            erlang:element(4, Session),
                                            {some, Piece},
                                            erlang:element(6, Session),
                                            erlang:element(7, Session)}
                                    )
                            end
                        end
                    );

                Message@1 ->
                    {error,
                        {unexpected_message,
                            torrent@peer@protocol:message_id(Message@1)}}
            end end
    ).

-file("src/torrent/peer/session.gleam", 135).
-spec handle_piece(peer_session()) -> {ok, piece_result()} |
    {error, peer_error()}.
handle_piece(Session) ->
    case Session of
        {peer_session, _, _, _, none, _, _} ->
            erlang:error(#{gleam_error => panic,
                    message => <<"piece not set before start"/utf8>>,
                    file => <<?FILEPATH/utf8>>,
                    module => <<"torrent/peer/session"/utf8>>,
                    function => <<"handle_piece"/utf8>>,
                    line => 137});

        {peer_session, _, _, _, _, false, true} ->
            gleam@result:'try'(
                request_piece_blocks(Session),
                fun(Session@1) -> peer_listen(Session@1) end
            );

        {peer_session, _, _, _, _, _, false} ->
            peer_listen(Session);

        {peer_session, _, _, _, _, true, true} ->
            peer_listen(Session)
    end.

-file("src/torrent/peer/session.gleam", 82).
-spec handle_piece_download(
    gleam@erlang@process:subject(torrent@messages:peer_event()),
    peer_session()
) -> nil.
handle_piece_download(Parent_subject, Session) ->
    Piece@1 = case erlang:element(5, Session) of
        {some, Piece} -> Piece;
        _assert_fail ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"torrent/peer/session"/utf8>>,
                        function => <<"handle_piece_download"/utf8>>,
                        line => 86,
                        value => _assert_fail,
                        start => 1975,
                        'end' => 2013,
                        pattern_start => 1986,
                        pattern_end => 1997})
    end,
    Result = handle_piece(Session),
    case Result of
        {ok, {piece_result, Session@1, Data}} ->
            gleam@erlang@process:send(
                Parent_subject,
                {piece_completed,
                    erlang:element(2, erlang:element(2, Piece@1)),
                    Data}
            ),
            Next_piece = gleam@erlang@process:call_forever(
                Parent_subject,
                fun(Subject) ->
                    {lease_piece, erlang:element(3, Session@1), Subject}
                end
            ),
            echo(
                <<<<(gleam@string:inspect(erlang:element(3, Session@1)))/binary,
                        "GOT NEXT PIECE"/utf8>>/binary,
                    (gleam@string:inspect(Next_piece))/binary>>,
                nil,
                98
            ),
            Piece_dwnld = new_piece_download(Next_piece),
            New_session = {peer_session,
                erlang:element(2, Session@1),
                erlang:element(3, Session@1),
                erlang:element(4, Session@1),
                {some, Piece_dwnld},
                erlang:element(6, Session@1),
                erlang:element(7, Session@1)},
            handle_piece_download(Parent_subject, New_session);

        {error, Err} ->
            gleam@erlang@process:send(
                Parent_subject,
                {peer_disconnected,
                    erlang:element(3, Session),
                    describe_error(Err)}
            ),
            gleam@erlang@process:kill(erlang:self())
    end.

-file("src/torrent/peer/session.gleam", 295).
-spec is_any_bit_set(bitstring()) -> boolean().
is_any_bit_set(Bitfield) ->
    case Bitfield of
        <<Byte/integer, Rest/bitstring>> ->
            (Byte /= 0) orelse is_any_bit_set(Rest);

        <<>> ->
            false;

        _ ->
            false
    end.

-file("src/torrent/peer/session.gleam", 189).
-spec handle_bitfield(peer_session(), bitstring()) -> {ok, peer_session()} |
    {error, peer_error()}.
handle_bitfield(Session, Bitfield) ->
    case is_any_bit_set(Bitfield) of
        true ->
            Id = torrent@peer@protocol:message_id(interested),
            Message = <<1:4/big-unit:8, Id/integer>>,
            gleam@result:'try'(
                begin
                    _pipe = torrent@peer@protocol:send_message(
                        erlang:element(2, Session),
                        Message
                    ),
                    gleam@result:map_error(
                        _pipe,
                        fun(Field@0) -> {protocol_error, Field@0} end
                    )
                end,
                fun(_) ->
                    {ok,
                        {peer_session,
                            erlang:element(2, Session),
                            erlang:element(3, Session),
                            erlang:element(4, Session),
                            erlang:element(5, Session),
                            erlang:element(6, Session),
                            true}}
                end
            );

        false ->
            {error, {peer_error, <<"they have nothing"/utf8>>}}
    end.

-file("src/torrent/peer/session.gleam", 115).
-spec receive_bitfield(peer_session()) -> {ok, peer_session()} |
    {error, peer_error()}.
receive_bitfield(Session) ->
    gleam@result:'try'(
        begin
            _pipe = torrent@peer@protocol:receive_message(
                erlang:element(2, Session)
            ),
            gleam@result:map_error(
                _pipe,
                fun(Field@0) -> {protocol_error, Field@0} end
            )
        end,
        fun(Message) -> case Message of
                {bit_field, Bits} ->
                    handle_bitfield(
                        {peer_session,
                            erlang:element(2, Session),
                            erlang:element(3, Session),
                            Bits,
                            erlang:element(5, Session),
                            erlang:element(6, Session),
                            erlang:element(7, Session)},
                        Bits
                    );

                _ ->
                    {error, {peer_error, <<"no bitfield"/utf8>>}}
            end end
    ).

-file("src/torrent/peer/session.gleam", 60).
-spec start_session(
    gleam@erlang@process:subject(torrent@messages:peer_event()),
    mug:socket(),
    torrent@peer@protocol:peer_id()
) -> {ok, nil} | {error, peer_error()}.
start_session(Parent_subject, Socket, Peer_id) ->
    Session = new_session(Socket, Peer_id),
    gleam@result:'try'(
        receive_bitfield(Session),
        fun(Session@1) ->
            Piece = gleam@erlang@process:call(
                Parent_subject,
                1000,
                fun(Subject) ->
                    {ready,
                        erlang:element(3, Session@1),
                        erlang:element(4, Session@1),
                        Subject}
                end
            ),
            Piece_dwnld = new_piece_download(Piece),
            New_session = {peer_session,
                erlang:element(2, Session@1),
                erlang:element(3, Session@1),
                erlang:element(4, Session@1),
                {some, Piece_dwnld},
                erlang:element(6, Session@1),
                erlang:element(7, Session@1)},
            handle_piece_download(Parent_subject, New_session),
            {ok, nil}
        end
    ).

-file("src/torrent/peer/session.gleam", 324).
-spec download_piece(
    mug:socket(),
    torrent@peer@protocol:peer_id(),
    torrent@torrent:piece_info()
) -> {ok, bitstring()} | {error, peer_error()}.
download_piece(Socket, Peer_id, Piece) ->
    Session = new_session(Socket, Peer_id),
    gleam@result:'try'(
        receive_bitfield(Session),
        fun(Session@1) ->
            Piece@1 = new_piece_download(Piece),
            Session@2 = {peer_session,
                erlang:element(2, Session@1),
                erlang:element(3, Session@1),
                erlang:element(4, Session@1),
                {some, Piece@1},
                erlang:element(6, Session@1),
                erlang:element(7, Session@1)},
            gleam@result:'try'(
                handle_piece(Session@2),
                fun(Result) -> _pipe = erlang:element(3, Result),
                    {ok, _pipe} end
            )
        end
    ).

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

