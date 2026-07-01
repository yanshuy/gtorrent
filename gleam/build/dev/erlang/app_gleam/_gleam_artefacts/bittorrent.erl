-module(bittorrent).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/bittorrent.gleam").
-export([stop/1, execute/1, main/0]).
-export_type([cmd_error/0]).

-type cmd_error() :: {unknown_command, binary()} |
    invalid_arguments |
    {file_error, simplifile:file_error()} |
    {decode_error, bencode:decode_error()} |
    {torrent_error, torrent:torrent_error()}.

-file("src/bittorrent.gleam", 70).
-spec stop(integer()) -> nil.
stop(Code) ->
    init:stop(Code).

-file("src/bittorrent.gleam", 59).
-spec describe_cmd_error(cmd_error()) -> binary().
describe_cmd_error(Error) ->
    case Error of
        {unknown_command, Command} ->
            <<"Unknown command: "/utf8, Command/binary>>;

        invalid_arguments ->
            <<"Usage: your_program.sh <command> <args>"/utf8>>;

        {file_error, Err} ->
            simplifile:describe_error(Err);

        {decode_error, Err@1} ->
            bencode:stringify_error(Err@1);

        {torrent_error, Err@2} ->
            torrent:describe_error(Err@2)
    end.

-file("src/bittorrent.gleam", 51).
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

-file("src/bittorrent.gleam", 40).
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

-file("src/bittorrent.gleam", 20).
-spec execute(list(binary())) -> {ok, nil} | {error, cmd_error()}.
execute(Args) ->
    case Args of
        [<<"decode"/utf8>>, Encode_str | _] ->
            cmd_decode(Encode_str);

        [<<"info"/utf8>>, Filename | _] ->
            cmd_info(Filename);

        [Command | _] ->
            {error, {unknown_command, Command}};

        [] ->
            {error, invalid_arguments}
    end.

-file("src/bittorrent.gleam", 10).
-spec main() -> nil.
main() ->
    case execute(erlang:element(4, argv:load())) of
        {ok, _} ->
            nil;

        {error, Err} ->
            gleam_stdlib:print_error(describe_cmd_error(Err)),
            init:stop(1)
    end.
