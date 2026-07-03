-module(bittorrent).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/bittorrent.gleam").
-export([stop/1, execute_cmd/1, execute/1, main/0]).
-export_type([cmd_error/0, application/0, start_error/0]).

-type cmd_error() :: {unknown_command, binary()} |
    invalid_arguments |
    {insufficient_arguments, binary()} |
    {invalid_piece_index, integer()} |
    {app_start_error, start_error()} |
    {file_error, simplifile:file_error()} |
    {decode_error, bencode:decode_error()} |
    {tracker_error, tracker:tracker_error()} |
    {peer_error, peer_protocol:protocol_error()}.

-type application() :: inets.

-type start_error() :: {start_error, binary()}.

-file("src/bittorrent.gleam", 227).
-spec stop(integer()) -> nil.
stop(Code) ->
    init:stop(Code).

-file("src/bittorrent.gleam", 211).
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

        {invalid_piece_index, Index} ->
            <<"Invalid piece index: "/utf8,
                (erlang:integer_to_binary(Index))/binary>>;

        {app_start_error, {start_error, Reason}} ->
            Reason;

        {file_error, Err} ->
            simplifile:describe_error(Err);

        {decode_error, Err@1} ->
            bencode:describe_error(Err@1);

        {tracker_error, Err@2} ->
            tracker:describe_error(Err@2);

        {peer_error, Err@3} ->
            peer_protocol:describe_error(Err@3)
    end.

-file("src/bittorrent.gleam", 199).
-spec load_peer_id() -> {ok, bitstring()} | {error, simplifile:file_error()}.
load_peer_id() ->
    case simplifile_erl:read_bits(<<".peer_id"/utf8>>) of
        {ok, Peer_id} ->
            {ok, Peer_id};

        _ ->
            Peer_id@1 = crypto:strong_rand_bytes(20),
            gleam@result:'try'(
                simplifile_erl:write_bits(<<".peer_id"/utf8>>, Peer_id@1),
                fun(_) -> {ok, Peer_id@1} end
            )
    end.

-file("src/bittorrent.gleam", 157).
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
                    _pipe@1 = bittorrent_ffi:start(inets),
                    gleam@result:map_error(
                        _pipe@1,
                        fun(Field@0) -> {app_start_error, Field@0} end
                    )
                end,
                fun(_) ->
                    gleam@result:'try'(
                        begin
                            _pipe@2 = load_peer_id(),
                            gleam@result:map_error(
                                _pipe@2,
                                fun(Field@0) -> {file_error, Field@0} end
                            )
                        end,
                        fun(Peer_id) ->
                            gleam@result:'try'(
                                begin
                                    _pipe@3 = simplifile_erl:read_bits(
                                        Torrent_file
                                    ),
                                    gleam@result:map_error(
                                        _pipe@3,
                                        fun(Field@0) -> {file_error, Field@0} end
                                    )
                                end,
                                fun(Bits) ->
                                    gleam@result:'try'(
                                        begin
                                            _pipe@4 = bencode:decode(Bits),
                                            gleam@result:map_error(
                                                _pipe@4,
                                                fun(Field@0) -> {decode_error, Field@0} end
                                            )
                                        end,
                                        fun(Data) ->
                                            gleam@result:'try'(
                                                begin
                                                    _pipe@5 = bencode:parse_torrent(
                                                        Data
                                                    ),
                                                    gleam@result:map_error(
                                                        _pipe@5,
                                                        fun(Field@0) -> {decode_error, Field@0} end
                                                    )
                                                end,
                                                fun(Torrent) ->
                                                    gleam@result:'try'(
                                                        begin
                                                            _pipe@6 = tracker:get_peers(
                                                                Torrent,
                                                                Peer_id
                                                            ),
                                                            gleam@result:map_error(
                                                                _pipe@6,
                                                                fun(Field@0) -> {tracker_error, Field@0} end
                                                            )
                                                        end,
                                                        fun(Peers) ->
                                                            Endpoint@1 = case Peers of
                                                                [Endpoint | _] -> Endpoint;
                                                                _assert_fail ->
                                                                    erlang:error(
                                                                            #{gleam_error => let_assert,
                                                                                message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                                                                                file => <<?FILEPATH/utf8>>,
                                                                                module => <<"bittorrent"/utf8>>,
                                                                                function => <<"cmd_download_piece"/utf8>>,
                                                                                line => 176,
                                                                                value => _assert_fail,
                                                                                start => 4821,
                                                                                'end' => 4854,
                                                                                pattern_start => 4832,
                                                                                pattern_end => 4846}
                                                                        )
                                                            end,
                                                            gleam@result:'try'(
                                                                begin
                                                                    _pipe@7 = erlang:element(
                                                                        6,
                                                                        Torrent
                                                                    ),
                                                                    _pipe@8 = gleam@list:drop(
                                                                        _pipe@7,
                                                                        Piece_index
                                                                    ),
                                                                    _pipe@9 = gleam@list:first(
                                                                        _pipe@8
                                                                    ),
                                                                    gleam@result:replace_error(
                                                                        _pipe@9,
                                                                        {invalid_piece_index,
                                                                            Piece_index}
                                                                    )
                                                                end,
                                                                fun(Piece_hash) ->
                                                                    gleam@result:'try'(
                                                                        begin
                                                                            _pipe@10 = peer_protocol:one_piece(
                                                                                Torrent,
                                                                                Endpoint@1,
                                                                                Piece_index,
                                                                                Piece_hash,
                                                                                Peer_id
                                                                            ),
                                                                            gleam@result:map_error(
                                                                                _pipe@10,
                                                                                fun(Field@0) -> {peer_error, Field@0} end
                                                                            )
                                                                        end,
                                                                        fun(
                                                                            Piece
                                                                        ) ->
                                                                            _pipe@11 = simplifile_erl:write_bits(
                                                                                Download_path,
                                                                                Piece
                                                                            ),
                                                                            gleam@result:map_error(
                                                                                _pipe@11,
                                                                                fun(Field@0) -> {file_error, Field@0} end
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
                    )
                end
            )
        end
    ).

-file("src/bittorrent.gleam", 134).
-spec cmd_handshake(binary(), binary()) -> {ok, nil} | {error, cmd_error()}.
cmd_handshake(Filename, Endpoint) ->
    gleam@result:'try'(
        begin
            _pipe = bittorrent_ffi:start(inets),
            gleam@result:map_error(
                _pipe,
                fun(Field@0) -> {app_start_error, Field@0} end
            )
        end,
        fun(_) ->
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
                        begin
                            _pipe@2 = simplifile_erl:read_bits(Filename),
                            gleam@result:map_error(
                                _pipe@2,
                                fun(Field@0) -> {file_error, Field@0} end
                            )
                        end,
                        fun(Bits) ->
                            gleam@result:'try'(
                                begin
                                    _pipe@3 = bencode:decode(Bits),
                                    gleam@result:map_error(
                                        _pipe@3,
                                        fun(Field@0) -> {decode_error, Field@0} end
                                    )
                                end,
                                fun(Data) ->
                                    gleam@result:'try'(
                                        begin
                                            _pipe@4 = bencode:parse_torrent(
                                                Data
                                            ),
                                            gleam@result:map_error(
                                                _pipe@4,
                                                fun(Field@0) -> {decode_error, Field@0} end
                                            )
                                        end,
                                        fun(Torrent) ->
                                            gleam@result:'try'(
                                                begin
                                                    _pipe@5 = peer_protocol:handshake(
                                                        Endpoint,
                                                        Torrent,
                                                        Peer_id
                                                    ),
                                                    gleam@result:map_error(
                                                        _pipe@5,
                                                        fun(Field@0) -> {peer_error, Field@0} end
                                                    )
                                                end,
                                                fun(Peer_peer_id) ->
                                                    gleam_stdlib:println(
                                                        <<"Peer ID: "/utf8,
                                                            (begin
                                                                _pipe@6 = Peer_peer_id,
                                                                _pipe@7 = gleam_stdlib:base16_encode(
                                                                    _pipe@6
                                                                ),
                                                                string:lowercase(
                                                                    _pipe@7
                                                                )
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
                    )
                end
            )
        end
    ).

-file("src/bittorrent.gleam", 117).
-spec cmd_peers(binary()) -> {ok, nil} | {error, cmd_error()}.
cmd_peers(Filename) ->
    gleam@result:'try'(
        begin
            _pipe = bittorrent_ffi:start(inets),
            gleam@result:map_error(
                _pipe,
                fun(Field@0) -> {app_start_error, Field@0} end
            )
        end,
        fun(_) ->
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
                        begin
                            _pipe@2 = simplifile_erl:read_bits(Filename),
                            gleam@result:map_error(
                                _pipe@2,
                                fun(Field@0) -> {file_error, Field@0} end
                            )
                        end,
                        fun(Bits) ->
                            gleam@result:'try'(
                                begin
                                    _pipe@3 = bencode:decode(Bits),
                                    gleam@result:map_error(
                                        _pipe@3,
                                        fun(Field@0) -> {decode_error, Field@0} end
                                    )
                                end,
                                fun(Data) ->
                                    gleam@result:'try'(
                                        begin
                                            _pipe@4 = bencode:parse_torrent(
                                                Data
                                            ),
                                            gleam@result:map_error(
                                                _pipe@4,
                                                fun(Field@0) -> {decode_error, Field@0} end
                                            )
                                        end,
                                        fun(Torrent) ->
                                            gleam@result:'try'(
                                                begin
                                                    _pipe@5 = tracker:get_peers(
                                                        Torrent,
                                                        Peer_id
                                                    ),
                                                    gleam@result:map_error(
                                                        _pipe@5,
                                                        fun(Field@0) -> {tracker_error, Field@0} end
                                                    )
                                                end,
                                                fun(Peers) ->
                                                    gleam_stdlib:println(
                                                        gleam@string:join(
                                                            Peers,
                                                            <<"\n"/utf8>>
                                                        )
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

-file("src/bittorrent.gleam", 91).
-spec cmd_info(binary()) -> {ok, nil} | {error, cmd_error()}.
cmd_info(Filename) ->
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
                fun(Data) ->
                    gleam@result:'try'(
                        begin
                            _pipe@2 = bencode:parse_torrent(Data),
                            gleam@result:map_error(
                                _pipe@2,
                                fun(Field@0) -> {decode_error, Field@0} end
                            )
                        end,
                        fun(Torrent) ->
                            gleam_stdlib:println(
                                <<"Tracker URL: "/utf8,
                                    (erlang:element(3, Torrent))/binary>>
                            ),
                            gleam_stdlib:println(
                                <<"Length: "/utf8,
                                    (erlang:integer_to_binary(
                                        erlang:element(4, Torrent)
                                    ))/binary>>
                            ),
                            Encoded = begin
                                _pipe@3 = erlang:element(7, Torrent),
                                _pipe@4 = gleam_stdlib:base16_encode(_pipe@3),
                                string:lowercase(_pipe@4)
                            end,
                            gleam_stdlib:println(
                                <<"Info Hash: "/utf8, Encoded/binary>>
                            ),
                            gleam_stdlib:println(
                                <<"Piece Length: "/utf8,
                                    (erlang:integer_to_binary(
                                        erlang:element(5, Torrent)
                                    ))/binary>>
                            ),
                            Hashes = begin
                                _pipe@5 = erlang:element(6, Torrent),
                                _pipe@6 = gleam@list:map(
                                    _pipe@5,
                                    fun gleam_stdlib:base16_encode/1
                                ),
                                _pipe@7 = gleam@list:map(
                                    _pipe@6,
                                    fun string:lowercase/1
                                ),
                                gleam@string:join(_pipe@7, <<"\n"/utf8>>)
                            end,
                            gleam_stdlib:println(
                                <<"Piece Hashes: \n"/utf8, Hashes/binary>>
                            ),
                            {ok, nil}
                        end
                    )
                end
            )
        end
    ).

-file("src/bittorrent.gleam", 80).
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

-file("src/bittorrent.gleam", 29).
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

        [Command | _] ->
            {error, {unknown_command, Command}}
    end.

-file("src/bittorrent.gleam", 19).
-spec execute(list(binary())) -> nil.
execute(Args) ->
    case execute_cmd(Args) of
        {ok, _} ->
            nil;

        {error, Err} ->
            gleam_stdlib:println_error(describe_cmd_error(Err)),
            init:stop(1)
    end.

-file("src/bittorrent.gleam", 15).
-spec main() -> nil.
main() ->
    execute(erlang:element(4, argv:load())).
