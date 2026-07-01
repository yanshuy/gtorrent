-module(torrent).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/torrent.gleam").
-export([print_info/1, describe_error/1]).
-export_type([torrent_error/0]).

-type torrent_error() :: {invalid_torrent, binary()}.

-file("src/torrent.gleam", 34).
-spec get_value(gleam@dict:dict(binary(), bencode:bencode()), binary()) -> {ok,
        bencode:bencode()} |
    {error, torrent_error()}.
get_value(Torrent, Key) ->
    _pipe = gleam_stdlib:map_get(Torrent, Key),
    gleam@result:replace_error(
        _pipe,
        {invalid_torrent, <<"Missing key: "/utf8, Key/binary>>}
    ).

-file("src/torrent.gleam", 58).
-spec get_int(gleam@dict:dict(binary(), bencode:bencode()), binary()) -> {ok,
        integer()} |
    {error, torrent_error()}.
get_int(Torrent, Key) ->
    gleam@result:'try'(get_value(Torrent, Key), fun(Value) -> case Value of
                {b_integer, Integer} ->
                    {ok, Integer};

                _ ->
                    {error,
                        {invalid_torrent,
                            <<"Expected integer for key: "/utf8, Key/binary>>}}
            end end).

-file("src/torrent.gleam", 70).
-spec get_dict(gleam@dict:dict(binary(), bencode:bencode()), binary()) -> {ok,
        gleam@dict:dict(binary(), bencode:bencode())} |
    {error, torrent_error()}.
get_dict(Torrent, Key) ->
    gleam@result:'try'(get_value(Torrent, Key), fun(Value) -> case Value of
                {b_dict, Entries} ->
                    {ok, maps:from_list(Entries)};

                _ ->
                    {error,
                        {invalid_torrent,
                            <<"Expected dictionary for key: "/utf8, Key/binary>>}}
            end end).

-file("src/torrent.gleam", 42).
-spec get_string(gleam@dict:dict(binary(), bencode:bencode()), binary()) -> {ok,
        binary()} |
    {error, torrent_error()}.
get_string(Torrent, Key) ->
    gleam@result:'try'(
        get_value(Torrent, Key),
        fun(Value) ->
            Error = {invalid_torrent,
                <<"Expected string for key: "/utf8, Key/binary>>},
            case Value of
                {b_string, Bits} ->
                    _pipe = gleam@bit_array:to_string(Bits),
                    gleam@result:replace_error(_pipe, Error);

                _ ->
                    {error, Error}
            end
        end
    ).

-file("src/torrent.gleam", 8).
-spec print_info(bencode:bencode()) -> {ok, nil} | {error, torrent_error()}.
print_info(Meta_info) ->
    case Meta_info of
        {b_dict, Entries} ->
            Dict = maps:from_list(Entries),
            gleam@result:'try'(
                get_string(Dict, <<"announce"/utf8>>),
                fun(Tracker) ->
                    gleam@result:'try'(
                        get_dict(Dict, <<"info"/utf8>>),
                        fun(Info) ->
                            gleam@result:'try'(
                                get_int(Info, <<"length"/utf8>>),
                                fun(Length) ->
                                    gleam_stdlib:println(
                                        <<"Tracker URL: "/utf8, Tracker/binary>>
                                    ),
                                    gleam_stdlib:println(
                                        <<"Length: "/utf8,
                                            (erlang:integer_to_binary(Length))/binary>>
                                    ),
                                    {ok, nil}
                                end
                            )
                        end
                    )
                end
            );

        _ ->
            {error, {invalid_torrent, <<"Not a valid torrent"/utf8>>}}
    end.

-file("src/torrent.gleam", 28).
-spec describe_error(torrent_error()) -> binary().
describe_error(Error) ->
    case Error of
        {invalid_torrent, Message} ->
            Message
    end.
