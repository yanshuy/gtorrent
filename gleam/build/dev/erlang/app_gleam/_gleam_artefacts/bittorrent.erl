-module(bittorrent).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/bittorrent.gleam").
-export([stop/1, execute_cmd/1, execute/1, main/0]).
-export_type([cmd_error/0, application/0, start_error/0]).

-type cmd_error() :: {unknown_command, binary()} |
    invalid_arguments |
    {insufficient_arguments, binary()} |
    {invalid_piece_index, integer()} |
    {file_error, simplifile:file_error()} |
    {decode_error, bencode:decode_error()} |
    {tracker_error, tracker:tracker_error()} |
    {peer_error, peer_protocol:protocol_error()}.

-type application() :: inets.

-type start_error() :: {start_error, binary()}.

-file("src/bittorrent.gleam", 233).
-spec stop(integer()) -> nil.
stop(Code) ->
    init:stop(Code).

-file("src/bittorrent.gleam", 218).
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

        {file_error, Err} ->
            simplifile:describe_error(Err);

        {decode_error, Err@1} ->
            bencode:describe_error(Err@1);

        {tracker_error, Err@2} ->
            tracker:describe_error(Err@2);

        {peer_error, Err@3} ->
            peer_protocol:describe_error(Err@3)
    end.

-file("src/bittorrent.gleam", 99).
-spec info(binary()) -> {ok, bencode:torrent()} | {error, cmd_error()}.
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
                fun(Data) -> _pipe@2 = bencode:parse_torrent(Data),
                    gleam@result:map_error(
                        _pipe@2,
                        fun(Field@0) -> {decode_error, Field@0} end
                    ) end
            )
        end
    ).

-file("src/bittorrent.gleam", 206).
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

-file("src/bittorrent.gleam", 190).
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
                        fun(Peers) ->
                            Endpoint@1 = case Peers of
                                [Endpoint | _] -> Endpoint;
                                _assert_fail ->
                                    erlang:error(#{gleam_error => let_assert,
                                                message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                                                file => <<?FILEPATH/utf8>>,
                                                module => <<"bittorrent"/utf8>>,
                                                function => <<"cmd_download"/utf8>>,
                                                line => 200,
                                                value => _assert_fail,
                                                start => 5127,
                                                'end' => 5160,
                                                pattern_start => 5138,
                                                pattern_end => 5152})
                            end,
                            State = peer_protocol:new_peer(
                                Endpoint@1,
                                Download_path
                            ),
                            _pipe@2 = peer_protocol:fetch_pieces(
                                Torrent,
                                State,
                                Peer_id
                            ),
                            gleam@result:map_error(
                                _pipe@2,
                                fun(Field@0) -> {peer_error, Field@0} end
                            )
                        end
                    )
                end
            )
        end
    ).

-file("src/bittorrent.gleam", 158).
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
                                            _pipe@3 = erlang:element(6, Torrent),
                                            _pipe@4 = gleam@list:drop(
                                                _pipe@3,
                                                Piece_index
                                            ),
                                            _pipe@5 = gleam@list:first(_pipe@4),
                                            gleam@result:replace_error(
                                                _pipe@5,
                                                {invalid_piece_index,
                                                    Piece_index}
                                            )
                                        end,
                                        fun(Piece_hash) ->
                                            Endpoint@1 = case Peers of
                                                [Endpoint | _] -> Endpoint;
                                                _assert_fail ->
                                                    erlang:error(
                                                            #{gleam_error => let_assert,
                                                                message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                                                                file => <<?FILEPATH/utf8>>,
                                                                module => <<"bittorrent"/utf8>>,
                                                                function => <<"cmd_download_piece"/utf8>>,
                                                                line => 179,
                                                                value => _assert_fail,
                                                                start => 4516,
                                                                'end' => 4549,
                                                                pattern_start => 4527,
                                                                pattern_end => 4541}
                                                        )
                                            end,
                                            State = peer_protocol:new_peer(
                                                Endpoint@1,
                                                Download_path
                                            ),
                                            gleam@result:'try'(
                                                begin
                                                    _pipe@6 = peer_protocol:handshake(
                                                        Endpoint@1,
                                                        Torrent,
                                                        Peer_id
                                                    ),
                                                    gleam@result:map_error(
                                                        _pipe@6,
                                                        fun(Field@0) -> {peer_error, Field@0} end
                                                    )
                                                end,
                                                fun(_use0) ->
                                                    {Socket, _} = _use0,
                                                    _pipe@7 = peer_protocol:one_piece(
                                                        Socket,
                                                        Torrent,
                                                        State,
                                                        [Piece_hash],
                                                        Piece_index
                                                    ),
                                                    gleam@result:map_error(
                                                        _pipe@7,
                                                        fun(Field@0) -> {peer_error, Field@0} end
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

-file("src/bittorrent.gleam", 140).
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
                            _pipe@1 = peer_protocol:handshake(
                                Endpoint,
                                Torrent,
                                Peer_id
                            ),
                            gleam@result:map_error(
                                _pipe@1,
                                fun(Field@0) -> {peer_error, Field@0} end
                            )
                        end,
                        fun(_use0) ->
                            {_, Peer_peer_id} = _use0,
                            gleam_stdlib:println(
                                <<"Peer ID: "/utf8,
                                    (begin
                                        _pipe@2 = Peer_peer_id,
                                        _pipe@3 = gleam_stdlib:base16_encode(
                                            _pipe@2
                                        ),
                                        string:lowercase(_pipe@3)
                                    end)/binary>>
                            ),
                            {ok, nil}
                        end
                    )
                end
            )
        end
    ).

-file("src/bittorrent.gleam", 129).
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

-file("src/bittorrent.gleam", 106).
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

-file("src/bittorrent.gleam", 88).
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

-file("src/bittorrent.gleam", 30).
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

-file("src/bittorrent.gleam", 246).
-spec start(list(application())) -> nil.
start(Apps) ->
    gleam@list:each(Apps, fun(App) -> case bittorrent_ffi:start(App) of
                {error, Err} ->
                    gleam_stdlib:println_error(erlang:element(2, Err)),
                    init:stop(1);

                {ok, _} ->
                    nil
            end end).

-file("src/bittorrent.gleam", 19).
-spec execute(list(binary())) -> nil.
execute(Args) ->
    start([inets]),
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
