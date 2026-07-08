-module(torrent@download).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/torrent/download.gleam").
-export([is_bit_set/2, describe_error/1, connect_with_peers/4, download_torrent/4, download_piece/5]).
-export_type([download_state/0, torrent_error/0]).

-type download_state() :: {download_state,
        torrent@torrent:torrent_info(),
        list(torrent@torrent:piece_info()),
        list(torrent@torrent:piece_info()),
        gleam@dict:dict(torrent@peer@protocol:peer_id(), bitstring())}.

-type torrent_error() :: no_peer_responding |
    {protocol_error, torrent@peer@protocol:protocol_error()} |
    {peer_error, torrent@peer@session:peer_error()} |
    {file_error, simplifile:file_error()}.

-file("src/torrent/download.gleam", 27).
-spec new_download(torrent@torrent:torrent_info()) -> download_state().
new_download(Torrent) ->
    Pieces = torrent@torrent:new_pieces(
        erlang:element(4, Torrent),
        erlang:element(5, Torrent),
        erlang:element(6, Torrent)
    ),
    {download_state, Torrent, Pieces, [], maps:new()}.

-file("src/torrent/download.gleam", 196).
-spec is_bit_set(bitstring(), integer()) -> boolean().
is_bit_set(Bits, Index) ->
    case Bits of
        <<_:Index, Target:1, _/bitstring>> ->
            Target =:= 1;

        _ ->
            false
    end.

-file("src/torrent/download.gleam", 174).
-spec lease_piece(download_state(), bitstring()) -> {ok,
        {torrent@torrent:piece_info(), list(torrent@torrent:piece_info())}} |
    {error, nil}.
lease_piece(State, Bitfield) ->
    gleam@result:'try'(
        begin
            _pipe = erlang:element(3, State),
            gleam@list:find(
                _pipe,
                fun(Piece) -> is_bit_set(Bitfield, erlang:element(2, Piece)) end
            )
        end,
        fun(Piece@1) ->
            Pendings = begin
                _pipe@1 = erlang:element(3, State),
                gleam@list:filter(
                    _pipe@1,
                    fun(Pending) ->
                        erlang:element(2, Pending) /= erlang:element(2, Piece@1)
                    end
                )
            end,
            _pipe@2 = {Piece@1, Pendings},
            {ok, _pipe@2}
        end
    ).

-file("src/torrent/download.gleam", 52).
-spec handle_downlaod(
    file_io:writer(),
    download_state(),
    gleam@erlang@process:subject(torrent@messages:peer_event())
) -> {ok, nil} | {error, torrent_error()}.
handle_downlaod(Writer, State, Mailbox) ->
    gleam@bool:guard(
        (begin
            _pipe = erlang:element(3, State),
            erlang:length(_pipe)
        end
        =:= 0)
        andalso (begin
            _pipe@1 = erlang:element(4, State),
            erlang:length(_pipe@1)
        end
        =:= 0),
        {ok, nil},
        fun() -> case gleam@erlang@process:'receive'(Mailbox, 10000) of
                {ok, Event} ->
                    case Event of
                        {ready, Peer_id, Bitfield, Reply} ->
                            Peers = gleam@dict:insert(
                                erlang:element(5, State),
                                Peer_id,
                                Bitfield
                            ),
                            State@1 = {download_state,
                                erlang:element(2, State),
                                erlang:element(3, State),
                                erlang:element(4, State),
                                Peers},
                            Res = lease_piece(State@1, Bitfield),
                            case Res of
                                {ok, {Piece, New_pending}} ->
                                    gleam@erlang@process:send(Reply, Piece),
                                    New_state = {download_state,
                                        erlang:element(2, State@1),
                                        New_pending,
                                        [Piece | erlang:element(4, State@1)],
                                        erlang:element(5, State@1)},
                                    handle_downlaod(Writer, New_state, Mailbox);

                                {error, _} ->
                                    handle_downlaod(Writer, State@1, Mailbox)
                            end;

                        {lease_piece, Peer_id@1, Reply@1} ->
                            Bitfield@2 = case gleam_stdlib:map_get(
                                erlang:element(5, State),
                                Peer_id@1
                            ) of
                                {ok, Bitfield@1} -> Bitfield@1;
                                _assert_fail ->
                                    erlang:error(#{gleam_error => let_assert,
                                                message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                                                file => <<?FILEPATH/utf8>>,
                                                module => <<"torrent/download"/utf8>>,
                                                function => <<"handle_downlaod"/utf8>>,
                                                line => 85,
                                                value => _assert_fail,
                                                start => 2462,
                                                'end' => 2518,
                                                pattern_start => 2473,
                                                pattern_end => 2485})
                            end,
                            Res@1 = lease_piece(State, Bitfield@2),
                            case Res@1 of
                                {ok, {Piece@1, New_pendings}} ->
                                    gleam@erlang@process:send(Reply@1, Piece@1),
                                    New_state@1 = {download_state,
                                        erlang:element(2, State),
                                        New_pendings,
                                        [Piece@1 | erlang:element(4, State)],
                                        erlang:element(5, State)},
                                    handle_downlaod(
                                        Writer,
                                        New_state@1,
                                        Mailbox
                                    );

                                {error, _} ->
                                    handle_downlaod(Writer, State, Mailbox)
                            end;

                        {piece_completed, Index, Data} ->
                            gleam_stdlib:println(
                                <<"[COMPLETE EVENT] index="/utf8,
                                    (erlang:integer_to_binary(Index))/binary>>
                            ),
                            echo(
                                gleam@list:map(
                                    erlang:element(4, State),
                                    fun(P) -> erlang:element(2, P) end
                                ),
                                nil,
                                103
                            ),
                            proc_lib:spawn_link(
                                fun() ->
                                    Offset = Index * erlang:element(
                                        5,
                                        erlang:element(2, State)
                                    ),
                                    Res@2 = (erlang:element(3, Writer))(
                                        Writer,
                                        Offset,
                                        Data
                                    ),
                                    case Res@2 of
                                        {ok, _} ->
                                            nil;

                                        {error, _} ->
                                            erlang:error(#{gleam_error => panic,
                                                    message => <<"write failed"/utf8>>,
                                                    file => <<?FILEPATH/utf8>>,
                                                    module => <<"torrent/download"/utf8>>,
                                                    function => <<"handle_downlaod"/utf8>>,
                                                    line => 109})
                                    end
                                end
                            ),
                            New_leased = begin
                                _pipe@2 = erlang:element(4, State),
                                gleam@list:filter(
                                    _pipe@2,
                                    fun(Piece@2) ->
                                        erlang:element(2, Piece@2) /= Index
                                    end
                                )
                            end,
                            echo(
                                gleam@list:map(
                                    New_leased,
                                    fun(P@1) -> erlang:element(2, P@1) end
                                ),
                                nil,
                                115
                            ),
                            New_state@2 = {download_state,
                                erlang:element(2, State),
                                erlang:element(3, State),
                                New_leased,
                                erlang:element(5, State)},
                            handle_downlaod(Writer, New_state@2, Mailbox);

                        {peer_disconnected, Peer_id@2, Reason} ->
                            Id@1 = begin
                                {peer_id, Id} = Peer_id@2,
                                _pipe@3 = Id,
                                gleam_stdlib:base16_encode(_pipe@3)
                            end,
                            gleam_stdlib:print_error(
                                <<<<<<"Stopping peer session with peer "/utf8,
                                            Id@1/binary>>/binary,
                                        "\nReason: "/utf8>>/binary,
                                    Reason/binary>>
                            ),
                            Peers@1 = gleam@dict:delete(
                                erlang:element(5, State),
                                Peer_id@2
                            ),
                            New_state@3 = {download_state,
                                erlang:element(2, State),
                                erlang:element(3, State),
                                erlang:element(4, State),
                                Peers@1},
                            handle_downlaod(Writer, New_state@3, Mailbox)
                    end;

                {error, _} ->
                    {error, no_peer_responding}
            end end
    ).

-file("src/torrent/download.gleam", 232).
-spec describe_error(torrent_error()) -> binary().
describe_error(Error) ->
    case Error of
        no_peer_responding ->
            <<"Torrent download stalled: No connected peers are currently responding to download requests"/utf8>>;

        {protocol_error, Err} ->
            <<"Torrent protocol error: "/utf8,
                (torrent@peer@protocol:describe_error(Err))/binary>>;

        {peer_error, Err@1} ->
            torrent@peer@session:describe_error(Err@1);

        {file_error, File_err} ->
            <<"Disk I/O error: "/utf8,
                (simplifile:describe_error(File_err))/binary>>
    end.

-file("src/torrent/download.gleam", 157).
-spec peer_worker(
    gleam@erlang@process:subject(torrent@messages:peer_event()),
    torrent@peer@protocol:endpoint(),
    bitstring(),
    torrent@peer@protocol:peer_id()
) -> {ok, nil} | {error, torrent_error()}.
peer_worker(Parent_subject, Endpoint, Info_hash, Peer_id) ->
    gleam@result:'try'(
        begin
            _pipe = torrent@peer@protocol:handshake(
                Endpoint,
                Info_hash,
                Peer_id
            ),
            gleam@result:map_error(
                _pipe,
                fun(Field@0) -> {protocol_error, Field@0} end
            )
        end,
        fun(_use0) ->
            {Socket, Peer_peer_id} = _use0,
            gleam@result:'try'(
                begin
                    _pipe@1 = torrent@peer@session:start_session(
                        Parent_subject,
                        Socket,
                        Peer_peer_id
                    ),
                    gleam@result:map_error(
                        _pipe@1,
                        fun(Field@0) -> {peer_error, Field@0} end
                    )
                end,
                fun(_) -> {ok, nil} end
            )
        end
    ).

-file("src/torrent/download.gleam", 137).
-spec connect_with_peers(
    gleam@erlang@process:subject(torrent@messages:peer_event()),
    list(torrent@peer@protocol:endpoint()),
    torrent@torrent:torrent_info(),
    torrent@peer@protocol:peer_id()
) -> nil.
connect_with_peers(Main_subject, Endpoints, Torrent, Peer_id) ->
    echo(
        begin
            _pipe = Endpoints,
            erlang:length(_pipe)
        end,
        nil,
        143
    ),
    _pipe@1 = Endpoints,
    _pipe@2 = gleam@list:take(_pipe@1, 6),
    gleam@list:each(
        _pipe@2,
        fun(Endpoint) ->
            proc_lib:spawn_link(
                fun() ->
                    case peer_worker(
                        Main_subject,
                        Endpoint,
                        erlang:element(7, Torrent),
                        Peer_id
                    ) of
                        {ok, _} ->
                            nil;

                        {error, Err} ->
                            gleam_stdlib:println(
                                <<<<(erlang:element(2, Endpoint))/binary,
                                        "is malicious"/utf8>>/binary,
                                    (describe_error(Err))/binary>>
                            )
                    end
                end
            )
        end
    ).

-file("src/torrent/download.gleam", 38).
-spec download_torrent(
    binary(),
    list(torrent@peer@protocol:endpoint()),
    torrent@torrent:torrent_info(),
    torrent@peer@protocol:peer_id()
) -> {ok, nil} | {error, torrent_error()}.
download_torrent(Download_path, Endpoints, Torrent, Peer_id) ->
    Main_subject = gleam@erlang@process:new_subject(),
    Writer = file_io:new_file_writer(Download_path, erlang:element(4, Torrent)),
    connect_with_peers(Main_subject, Endpoints, Torrent, Peer_id),
    handle_downlaod(Writer, new_download(Torrent), Main_subject).

-file("src/torrent/download.gleam", 203).
-spec download_piece(
    binary(),
    torrent@peer@protocol:endpoint(),
    torrent@torrent:torrent_info(),
    torrent@peer@protocol:peer_id(),
    torrent@torrent:piece_info()
) -> {ok, nil} | {error, torrent_error()}.
download_piece(Download_path, Endpoint, Torrent, Peer_id, Piece) ->
    gleam@result:'try'(
        begin
            _pipe = torrent@peer@protocol:handshake(
                Endpoint,
                erlang:element(7, Torrent),
                Peer_id
            ),
            gleam@result:map_error(
                _pipe,
                fun(Field@0) -> {protocol_error, Field@0} end
            )
        end,
        fun(_use0) ->
            {Socket, Peer_peer_id} = _use0,
            gleam@result:'try'(
                begin
                    _pipe@1 = torrent@peer@session:download_piece(
                        Socket,
                        Peer_peer_id,
                        Piece
                    ),
                    gleam@result:map_error(
                        _pipe@1,
                        fun(Field@0) -> {peer_error, Field@0} end
                    )
                end,
                fun(Data) ->
                    Writer = file_io:new_file_writer(
                        Download_path,
                        erlang:element(4, Piece)
                    ),
                    _pipe@2 = (erlang:element(3, Writer))(Writer, 0, Data),
                    gleam@result:replace_error(_pipe@2, {file_error, efault})
                end
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

