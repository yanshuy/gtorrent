-module(bittorrent).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/bittorrent.gleam").
-export([stop/1, execute_cmd/1, execute/1, main/0]).
-export_type([cmd_error/0, application/0, start_error/0]).

-type cmd_error() :: {unknown_command, binary()} |
    invalid_arguments |
    {insufficient_arguments, binary()} |
    {invalid_piece_index, integer()} |
    invalid_endpoint |
    {file_error, simplifile:file_error()} |
    {decode_error, bencode:bencode_error()} |
    {tracker_error, tracker:tracker_error()} |
    {protocol_error, torrent@peer@protocol:protocol_error()} |
    {peer_error, torrent@peer@session:peer_error()} |
    {torrent_error, torrent@download:torrent_error()}.

-type application() :: inets | crypto | asn1 | public_key | ssl.

-type start_error() :: {start_error, binary()}.

-file("src/bittorrent.gleam", 266).
-spec stop(integer()) -> nil.
stop(Code) ->
    init:stop(Code).

-file("src/bittorrent.gleam", 248).
-spec describe_cmd_error(cmd_error()) -> binary().
describe_cmd_error(Error) ->
    case Error of
        {unknown_command, Command} ->
            <<"Unknown command: "/utf8, Command/binary>>;

        invalid_arguments ->
            <<"Usage: your_program.sh <command> <args>"/utf8>>;

        {insufficient_arguments, Command@1} ->
            <<<<"Insufficient arguments for `"/utf8, Command@1/binary>>/binary,
                "`"/utf8>>;

        invalid_endpoint ->
            <<"Invalid endpoint. Expected <ip>:<port>."/utf8>>;

        {invalid_piece_index, Index} ->
            <<"Invalid piece index: "/utf8,
                (erlang:integer_to_binary(Index))/binary>>;

        {file_error, Err} ->
            simplifile:describe_error(Err);

        {decode_error, Err@1} ->
            bencode:describe_error(Err@1);

        {tracker_error, Err@2} ->
            tracker:describe_error(Err@2);

        {peer_error, Err@3} ->
            torrent@peer@session:describe_error(Err@3);

        {protocol_error, Err@4} ->
            torrent@peer@protocol:describe_error(Err@4);

        {torrent_error, Err@5} ->
            torrent@download:describe_error(Err@5)
    end.

-file("src/bittorrent.gleam", 147).
-spec new_endpoint(binary()) -> {ok, torrent@peer@protocol:endpoint()} |
    {error, nil}.
new_endpoint(Endpoint) ->
    case gleam@string:split(Endpoint, <<":"/utf8>>) of
        [Ipv4, Port_str] ->
            gleam@result:'try'(
                gleam_stdlib:parse_int(Port_str),
                fun(Port) -> {ok, {endpoint, Ipv4, Port}} end
            );

        _ ->
            {error, nil}
    end.

-file("src/bittorrent.gleam", 106).
-spec info(binary()) -> {ok, torrent@torrent:torrent_info()} |
    {error, cmd_error()}.
info(Filename) ->
    gleam@result:'try'(
        begin
            _pipe = simplifile_erl:read_bits(Filename),
            gleam@result:map_error(
                _pipe,
                fun(Field@0) -> {file_error, Field@0} end
            )
        end,
        fun(Bits) ->
            gleam@result:'try'(
                begin
                    _pipe@1 = bencode:decode(Bits),
                    gleam@result:map_error(
                        _pipe@1,
                        fun(Field@0) -> {decode_error, Field@0} end
                    )
                end,
                fun(Data) -> _pipe@2 = torrent@torrent:parse(Data),
                    gleam@result:map_error(
                        _pipe@2,
                        fun(Field@0) -> {decode_error, Field@0} end
                    ) end
            )
        end
    ).

-file("src/bittorrent.gleam", 236).
-spec load_peer_id() -> {ok, torrent@peer@protocol:peer_id()} |
    {error, simplifile:file_error()}.
load_peer_id() ->
    case simplifile_erl:read_bits(<<".peer_id"/utf8>>) of
        {ok, Peer_id} ->
            {ok, {peer_id, Peer_id}};

        _ ->
            Peer_id@1 = crypto:strong_rand_bytes(20),
            gleam@result:'try'(
                simplifile_erl:write_bits(<<".peer_id"/utf8>>, Peer_id@1),
                fun(_) -> {ok, {peer_id, Peer_id@1}} end
            )
    end.

-file("src/bittorrent.gleam", 213).
-spec cmd_download(binary(), binary()) -> {ok, nil} | {error, cmd_error()}.
cmd_download(Download_path, Torrent_file) ->
    gleam@result:'try'(
        begin
            _pipe = load_peer_id(),
            gleam@result:map_error(
                _pipe,
                fun(Field@0) -> {file_error, Field@0} end
            )
        end,
        fun(Peer_id) ->
            gleam@result:'try'(
                info(Torrent_file),
                fun(Torrent) ->
                    gleam@result:'try'(
                        begin
                            _pipe@1 = tracker:get_peers(Torrent, Peer_id),
                            gleam@result:map_error(
                                _pipe@1,
                                fun(Field@0) -> {tracker_error, Field@0} end
                            )
                        end,
                        fun(Peer_endpoints) ->
                            gleam@result:'try'(
                                begin
                                    _pipe@2 = Peer_endpoints,
                                    gleam@list:try_map(
                                        _pipe@2,
                                        fun(Endpoint) ->
                                            _pipe@3 = new_endpoint(Endpoint),
                                            gleam@result:replace_error(
                                                _pipe@3,
                                                invalid_endpoint
                                            )
                                        end
                                    )
                                end,
                                fun(Endpoints) ->
                                    State = begin
                                        _pipe@4 = torrent@download:download_torrent(
                                            Download_path,
                                            Endpoints,
                                            Torrent,
                                            Peer_id
                                        ),
                                        gleam@result:map_error(
                                            _pipe@4,
                                            fun(Field@0) -> {torrent_error, Field@0} end
                                        )
                                    end,
                                    echo(State, nil, 232),
                                    _pipe@5 = gleam_stdlib:println(
                                        <<"download complete"/utf8>>
                                    ),
                                    {ok, _pipe@5}
                                end
                            )
                        end
                    )
                end
            )
        end
    ).

-file("src/bittorrent.gleam", 176).
-spec cmd_download_piece(binary(), binary(), binary()) -> {ok, nil} |
    {error, cmd_error()}.
cmd_download_piece(Download_path, Torrent_file, Piece_index_str) ->
    gleam@result:'try'(
        begin
            _pipe = gleam_stdlib:parse_int(Piece_index_str),
            gleam@result:replace_error(_pipe, invalid_arguments)
        end,
        fun(Piece_index) ->
            gleam@result:'try'(
                begin
                    _pipe@1 = load_peer_id(),
                    gleam@result:map_error(
                        _pipe@1,
                        fun(Field@0) -> {file_error, Field@0} end
                    )
                end,
                fun(Peer_id) ->
                    gleam@result:'try'(
                        info(Torrent_file),
                        fun(Torrent) ->
                            gleam@result:'try'(
                                begin
                                    _pipe@2 = tracker:get_peers(
                                        Torrent,
                                        Peer_id
                                    ),
                                    gleam@result:map_error(
                                        _pipe@2,
                                        fun(Field@0) -> {tracker_error, Field@0} end
                                    )
                                end,
                                fun(Peers) ->
                                    gleam@result:'try'(
                                        begin
                                            _pipe@3 = Peers,
                                            _pipe@4 = gleam@list:first(_pipe@3),
                                            gleam@result:replace_error(
                                                _pipe@4,
                                                invalid_arguments
                                            )
                                        end,
                                        fun(Endpoint) ->
                                            gleam@result:'try'(
                                                begin
                                                    _pipe@5 = new_endpoint(
                                                        Endpoint
                                                    ),
                                                    gleam@result:replace_error(
                                                        _pipe@5,
                                                        invalid_endpoint
                                                    )
                                                end,
                                                fun(Endpoint@1) ->
                                                    gleam@result:'try'(
                                                        begin
                                                            _pipe@6 = torrent@torrent:new_pieces(
                                                                erlang:element(
                                                                    4,
                                                                    Torrent
                                                                ),
                                                                erlang:element(
                                                                    5,
                                                                    Torrent
                                                                ),
                                                                erlang:element(
                                                                    6,
                                                                    Torrent
                                                                )
                                                            ),
                                                            _pipe@7 = gleam@list:drop(
                                                                _pipe@6,
                                                                Piece_index
                                                            ),
                                                            _pipe@8 = gleam@list:first(
                                                                _pipe@7
                                                            ),
                                                            gleam@result:replace_error(
                                                                _pipe@8,
                                                                {invalid_piece_index,
                                                                    Piece_index}
                                                            )
                                                        end,
                                                        fun(Piece) ->
                                                            _pipe@9 = torrent@download:download_piece(
                                                                Download_path,
                                                                Endpoint@1,
                                                                Torrent,
                                                                Peer_id,
                                                                Piece
                                                            ),
                                                            gleam@result:map_error(
                                                                _pipe@9,
                                                                fun(Field@0) -> {torrent_error, Field@0} end
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

-file("src/bittorrent.gleam", 157).
-spec cmd_handshake(binary(), binary()) -> {ok, nil} | {error, cmd_error()}.
cmd_handshake(Filename, Endpoint) ->
    gleam@result:'try'(
        begin
            _pipe = load_peer_id(),
            gleam@result:map_error(
                _pipe,
                fun(Field@0) -> {file_error, Field@0} end
            )
        end,
        fun(Peer_id) ->
            gleam@result:'try'(
                info(Filename),
                fun(Torrent) ->
                    gleam@result:'try'(
                        begin
                            _pipe@1 = new_endpoint(Endpoint),
                            gleam@result:replace_error(
                                _pipe@1,
                                invalid_endpoint
                            )
                        end,
                        fun(Endpoint@1) ->
                            gleam@result:'try'(
                                begin
                                    _pipe@2 = torrent@peer@protocol:handshake(
                                        Endpoint@1,
                                        erlang:element(7, Torrent),
                                        Peer_id
                                    ),
                                    gleam@result:map_error(
                                        _pipe@2,
                                        fun(Field@0) -> {protocol_error, Field@0} end
                                    )
                                end,
                                fun(_use0) ->
                                    {_, Peer_peer_id} = _use0,
                                    {peer_id, Id} = Peer_peer_id,
                                    gleam_stdlib:println(
                                        <<"Peer ID: "/utf8,
                                            (begin
                                                _pipe@3 = Id,
                                                _pipe@4 = gleam_stdlib:base16_encode(
                                                    _pipe@3
                                                ),
                                                string:lowercase(_pipe@4)
                                            end)/binary>>
                                    ),
                                    {ok, nil}
                                end
                            )
                        end
                    )
                end
            )
        end
    ).

-file("src/bittorrent.gleam", 136).
-spec cmd_peers(binary()) -> {ok, nil} | {error, cmd_error()}.
cmd_peers(Filename) ->
    gleam@result:'try'(
        begin
            _pipe = load_peer_id(),
            gleam@result:map_error(
                _pipe,
                fun(Field@0) -> {file_error, Field@0} end
            )
        end,
        fun(Peer_id) ->
            gleam@result:'try'(
                info(Filename),
                fun(Torrent) ->
                    gleam@result:'try'(
                        begin
                            _pipe@1 = tracker:get_peers(Torrent, Peer_id),
                            gleam@result:map_error(
                                _pipe@1,
                                fun(Field@0) -> {tracker_error, Field@0} end
                            )
                        end,
                        fun(Peers) ->
                            gleam_stdlib:println(
                                gleam@string:join(Peers, <<"\n"/utf8>>)
                            ),
                            {ok, nil}
                        end
                    )
                end
            )
        end
    ).

-file("src/bittorrent.gleam", 113).
-spec cmd_info(binary()) -> {ok, nil} | {error, cmd_error()}.
cmd_info(Filename) ->
    gleam@result:'try'(
        info(Filename),
        fun(Torrent) ->
            gleam_stdlib:println(
                <<"Tracker URL: "/utf8, (erlang:element(3, Torrent))/binary>>
            ),
            gleam_stdlib:println(
                <<"Length: "/utf8,
                    (erlang:integer_to_binary(erlang:element(4, Torrent)))/binary>>
            ),
            Encoded = begin
                _pipe = erlang:element(7, Torrent),
                _pipe@1 = gleam_stdlib:base16_encode(_pipe),
                string:lowercase(_pipe@1)
            end,
            gleam_stdlib:println(<<"Info Hash: "/utf8, Encoded/binary>>),
            gleam_stdlib:println(
                <<"Piece Length: "/utf8,
                    (erlang:integer_to_binary(erlang:element(5, Torrent)))/binary>>
            ),
            Hashes = begin
                _pipe@2 = erlang:element(6, Torrent),
                _pipe@3 = gleam@list:map(
                    _pipe@2,
                    fun gleam_stdlib:base16_encode/1
                ),
                _pipe@4 = gleam@list:map(_pipe@3, fun string:lowercase/1),
                gleam@string:join(_pipe@4, <<"\n"/utf8>>)
            end,
            gleam_stdlib:println(<<"Piece Hashes: \n"/utf8, Hashes/binary>>),
            {ok, nil}
        end
    ).

-file("src/bittorrent.gleam", 95).
-spec cmd_decode(binary()) -> {ok, nil} | {error, cmd_error()}.
cmd_decode(Encode_str) ->
    gleam@result:'try'(
        begin
            _pipe = gleam_stdlib:identity(Encode_str),
            _pipe@1 = bencode:decode(_pipe),
            gleam@result:map_error(
                _pipe@1,
                fun(Field@0) -> {decode_error, Field@0} end
            )
        end,
        fun(Value) ->
            Json_str = begin
                _pipe@2 = bencode:to_json(Value),
                gleam@json:to_string(_pipe@2)
            end,
            gleam_stdlib:println(Json_str),
            {ok, nil}
        end
    ).

-file("src/bittorrent.gleam", 34).
-spec execute_cmd(list(binary())) -> {ok, nil} | {error, cmd_error()}.
execute_cmd(Args) ->
    case Args of
        [] ->
            {error, invalid_arguments};

        [<<"decode"/utf8>> | Rest] ->
            case Rest of
                [Encoded | _] ->
                    cmd_decode(Encoded);

                [] ->
                    {error, {insufficient_arguments, <<"decode"/utf8>>}}
            end;

        [<<"info"/utf8>> | Rest@1] ->
            case Rest@1 of
                [Torrent_file | _] ->
                    cmd_info(Torrent_file);

                [] ->
                    {error, {insufficient_arguments, <<"info"/utf8>>}}
            end;

        [<<"peers"/utf8>> | Rest@2] ->
            case Rest@2 of
                [Torrent_file@1 | _] ->
                    cmd_peers(Torrent_file@1);

                [] ->
                    {error, {insufficient_arguments, <<"peers"/utf8>>}}
            end;

        [<<"handshake"/utf8>> | Rest@3] ->
            case Rest@3 of
                [Torrent_file@2, Endpoint] ->
                    cmd_handshake(Torrent_file@2, Endpoint);

                _ ->
                    {error, {insufficient_arguments, <<"handshake"/utf8>>}}
            end;

        [<<"download_piece"/utf8>> | Rest@4] ->
            case Rest@4 of
                [<<"-o"/utf8>>, Download_path, Torrent_file@3, Piece_index] ->
                    cmd_download_piece(
                        Download_path,
                        Torrent_file@3,
                        Piece_index
                    );

                _ ->
                    {error, {insufficient_arguments, <<"download_piece"/utf8>>}}
            end;

        [<<"download"/utf8>> | Rest@5] ->
            case Rest@5 of
                [<<"-o"/utf8>>, Download_path@1, Torrent_file@4] ->
                    cmd_download(Download_path@1, Torrent_file@4);

                _ ->
                    {error, {insufficient_arguments, <<"download_piece"/utf8>>}}
            end;

        [Command | _] ->
            {error, {unknown_command, Command}}
    end.

-file("src/bittorrent.gleam", 283).
-spec start(list(application())) -> nil.
start(Apps) ->
    gleam@list:each(Apps, fun(App) -> case bittorrent_ffi:start(App) of
                {error, Err} ->
                    gleam_stdlib:println_error(erlang:element(2, Err)),
                    init:stop(1);

                {ok, _} ->
                    nil
            end end).

-file("src/bittorrent.gleam", 23).
-spec execute(list(binary())) -> nil.
execute(Args) ->
    start([inets, crypto, asn1, public_key, ssl]),
    case execute_cmd(Args) of
        {ok, _} ->
            nil;

        {error, Err} ->
            gleam_stdlib:println_error(describe_cmd_error(Err)),
            init:stop(1)
    end.

-file("src/bittorrent.gleam", 19).
-spec main() -> nil.
main() ->
    execute(erlang:element(4, argv:load())).

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

