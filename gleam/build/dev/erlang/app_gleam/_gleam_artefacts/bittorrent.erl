-module(bittorrent).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/bittorrent.gleam").
-export([execute/1, main/0]).

-file("src/bittorrent.gleam", 11).
-spec execute(list(binary())) -> nil.
execute(Args) ->
    case Args of
        [<<"decode"/utf8>>, Encode_str | _] ->
            Decoded_str = begin
                _pipe = gleam_stdlib:identity(Encode_str),
                bencode:decode(_pipe)
            end,
            Json_string = begin
                _pipe@1 = gleam@json:string(Decoded_str),
                gleam@json:to_string(_pipe@1)
            end,
            gleam_stdlib:println(Json_string);

        [Command | _] ->
            gleam_stdlib:println(<<"Unknown command: "/utf8, Command/binary>>),
            erlang:error(#{gleam_error => panic,
                    message => <<"`panic` expression evaluated."/utf8>>,
                    file => <<?FILEPATH/utf8>>,
                    module => <<"bittorrent"/utf8>>,
                    function => <<"execute"/utf8>>,
                    line => 22});

        [] ->
            gleam_stdlib:println(
                <<"Usage: your_program.sh <command> <args>"/utf8>>
            ),
            erlang:error(#{gleam_error => panic,
                    message => <<"`panic` expression evaluated."/utf8>>,
                    file => <<?FILEPATH/utf8>>,
                    module => <<"bittorrent"/utf8>>,
                    function => <<"execute"/utf8>>,
                    line => 26})
    end.

-file("src/bittorrent.gleam", 7).
-spec main() -> nil.
main() ->
    execute(erlang:element(4, argv:load())).
