-module(bittorrent).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/bittorrent.gleam").
-export([stop/1, execute/1, main/0]).

-file("src/bittorrent.gleam", 32).
-spec stop(integer()) -> nil.
stop(Code) ->
    init:stop(Code).

-file("src/bittorrent.gleam", 11).
-spec execute(list(binary())) -> nil.
execute(Args) ->
    case Args of
        [<<"decode"/utf8>>, Encode_str | _] ->
            Res = begin
                _pipe = gleam_stdlib:identity(Encode_str),
                bencode:decode(_pipe)
            end,
            case Res of
                {ok, Value} ->
                    _pipe@1 = bencode:to_json(Value),
                    _pipe@2 = gleam@json:to_string(_pipe@1),
                    gleam_stdlib:println(_pipe@2);

                {error, Err} ->
                    gleam_stdlib:println_error(bencode:stringify_error(Err))
            end;

        [Command | _] ->
            gleam_stdlib:println(<<"Unknown command: "/utf8, Command/binary>>),
            init:stop(1);

        [] ->
            gleam_stdlib:println(
                <<"Usage: your_program.sh <command> <args>"/utf8>>
            ),
            init:stop(1)
    end.

-file("src/bittorrent.gleam", 7).
-spec main() -> nil.
main() ->
    execute(erlang:element(4, argv:load())).
