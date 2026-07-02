-module(bittorrent).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/bittorrent.gleam").
-export([stop/1, execute_cmd/1, execute/1, main/0]).
-export_type([cmd_error/0, application/0, start_error/0]).

-type cmd_error() :: {unknown_command, binary()} |
    invalid_arguments |
    invalid_endpoint |
    {insufficient_arguments, binary()} |
    {app_start_error, start_error()} |
    {file_error, simplifile:file_error()} |
    {decode_error, bencode:decode_error()} |
    {torrent_error, torrent:torrent_error()} |
    {tracker_error, tracker:tracker_error()} |
    {peer_error, peer_protocol:peer_error()}.

-type application() :: inets.

-type start_error() :: {start_error, binary()}.

-file("src/bittorrent.gleam", 164).
-spec stop(integer()) -> nil.
stop(Code) ->
    init:stop(Code).

-file("src/bittorrent.gleam", 147).
-spec describe_cmd_error(cmd_error()) -> binary().
describe_cmd_error(Error) ->
    case Error of
        {unknown_command, Command} ->
            <<"Unknown command: "/utf8, Command/binary>>;

        invalid_arguments ->
            <<"Usage: your_program.sh <command> <args>"/utf8>>;

        invalid_endpoint ->
            <<"Invalid endpoint. Expected <ip>:<port>."/utf8>>;

        {insufficient_arguments, Command@1} ->
            <<<<"Insufficient arguments for `"/utf8, Command@1/binary>>/binary,
                "`"/utf8>>;

        {app_start_error, {start_error, Reason}} ->
            Reason;

        {file_error, Err} ->
            simplifile:describe_error(Err);

        {decode_error, Err@1} ->
            bencode:describe_error(Err@1);

        {torrent_error, Err@2} ->
            torrent:describe_error(Err@2);

        {tracker_error, Err@3} ->
            tracker:describe_error(Err@3);

        {peer_error, Err@4} ->
            peer_protocol:describe_error(Err@4)
    end.

-file("src/bittorrent.gleam", 128).
-spec validate_endpoint(binary()) -> {ok, {binary(), binary()}} | {error, nil}.
validate_endpoint(Endpoint) ->
    case gleam@string:split(Endpoint, <<":"/utf8>>) of
        [Ipv4, Port] ->
            {ok, {Ipv4, Port}};

        _ ->
            {error, nil}
    end.

-file("src/bittorrent.gleam", 135).
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

-file("src/bittorrent.gleam", 107).
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
                            _pipe@2 = validate_endpoint(Endpoint),
                            gleam@result:replace_error(
                                _pipe@2,
                                invalid_endpoint
                            )
                        end,
                        fun(_use0) ->
                            {Ip_addr, Port_str} = _use0,
                            gleam@result:'try'(
                                begin
                                    _pipe@3 = gleam_stdlib:parse_int(Port_str),
                                    gleam@result:replace_error(
                                        _pipe@3,
                                        invalid_endpoint
                                    )
                                end,
                                fun(Port) ->
                                    gleam@result:'try'(
                                        begin
                                            _pipe@4 = simplifile_erl:read_bits(
                                                Filename
                                            ),
                                            gleam@result:map_error(
                                                _pipe@4,
                                                fun(Field@0) -> {file_error, Field@0} end
                                            )
                                        end,
                                        fun(Bits) ->
                                            gleam@result:'try'(
                                                begin
                                                    _pipe@5 = bencode:decode(
                                                        Bits
                                                    ),
                                                    gleam@result:map_error(
                                                        _pipe@5,
                                                        fun(Field@0) -> {decode_error, Field@0} end
                                                    )
                                                end,
                                                fun(Data) ->
                                                    gleam@result:'try'(
                                                        begin
                                                            _pipe@6 = peer_protocol:handshake(
                                                                Ip_addr,
                                                                Port,
                                                                Data,
                                                                Peer_id
                                                            ),
                                                            gleam@result:map_error(
                                                                _pipe@6,
                                                                fun(Field@0) -> {peer_error, Field@0} end
                                                            )
                                                        end,
                                                        fun(_) -> {ok, nil} end
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

-file("src/bittorrent.gleam", 93).
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
                                            _pipe@4 = tracker:get_peers(
                                                Data,
                                                Peer_id
                                            ),
                                            gleam@result:map_error(
                                                _pipe@4,
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
    ).

-file("src/bittorrent.gleam", 85).
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
                            _pipe@2 = torrent:print_info(Data),
                            gleam@result:map_error(
                                _pipe@2,
                                fun(Field@0) -> {torrent_error, Field@0} end
                            )
                        end,
                        fun(_) -> {ok, nil} end
                    )
                end
            )
        end
    ).

-file("src/bittorrent.gleam", 74).
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
                [Filename | _] ->
                    cmd_info(Filename);

                [] ->
                    {error, {insufficient_arguments, <<"info"/utf8>>}}
            end;

        [<<"peers"/utf8>> | Rest@2] ->
            case Rest@2 of
                [Filename@1 | _] ->
                    cmd_peers(Filename@1);

                [] ->
                    {error, {insufficient_arguments, <<"peers"/utf8>>}}
            end;

        [<<"handshake"/utf8>> | Rest@3] ->
            case Rest@3 of
                [Filename@2, Endpoint] ->
                    cmd_handshake(Filename@2, Endpoint);

                _ ->
                    {error, {insufficient_arguments, <<"handshake"/utf8>>}}
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
