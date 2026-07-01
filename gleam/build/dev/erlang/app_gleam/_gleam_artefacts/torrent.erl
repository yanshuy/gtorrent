-module(torrent).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/torrent.gleam").
-export([print_info/1, describe_error/1]).
-export_type([torrent_error/0, algorithm/0]).

-type torrent_error() :: {invalid_torrent, binary()}.

-type algorithm() :: sha.

-file("src/torrent.gleam", 30).
-spec digest(list({binary(), bencode:bencode()})) -> bitstring().
digest(Info_entries) ->
    Bits = begin
        _pipe = {b_dict, Info_entries},
        bencode:encode(_pipe)
    end,
    crypto:hash(sha, Bits).

-file("src/torrent.gleam", 39).
-spec get_value(gleam@dict:dict(binary(), bencode:bencode()), binary()) -> {ok,
        bencode:bencode()} |
    {error, torrent_error()}.
get_value(Torrent, Key) ->
    _pipe = gleam_stdlib:map_get(Torrent, Key),
    gleam@result:replace_error(
        _pipe,
        {invalid_torrent, <<"Missing key: "/utf8, Key/binary>>}
    ).

-file("src/torrent.gleam", 63).
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

-file("src/torrent.gleam", 75).
-spec get_entries(gleam@dict:dict(binary(), bencode:bencode()), binary()) -> {ok,
        list({binary(), bencode:bencode()})} |
    {error, torrent_error()}.
get_entries(Torrent, Key) ->
    gleam@result:'try'(get_value(Torrent, Key), fun(Value) -> case Value of
                {b_dict, Entries} ->
                    {ok, Entries};

                _ ->
                    {error,
                        {invalid_torrent,
                            <<"Expected dictionary for key: "/utf8, Key/binary>>}}
            end end).

-file("src/torrent.gleam", 47).
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

-file("src/torrent.gleam", 9).
-spec print_info(bencode:bencode()) -> {ok, nil} | {error, torrent_error()}.
print_info(Meta_info) ->
    case Meta_info of
        {b_dict, Entries} ->
            Dict = maps:from_list(Entries),
            gleam@result:'try'(
                get_string(Dict, <<"announce"/utf8>>),
                fun(Tracker) ->
                    gleam@result:'try'(
                        get_entries(Dict, <<"info"/utf8>>),
                        fun(Info_entries) ->
                            Info_dict = maps:from_list(Info_entries),
                            gleam@result:'try'(
                                get_int(Info_dict, <<"length"/utf8>>),
                                fun(Length) ->
                                    Encoded = begin
                                        _pipe = digest(Info_entries),
                                        _pipe@1 = gleam_stdlib:base16_encode(
                                            _pipe
                                        ),
                                        string:lowercase(_pipe@1)
                                    end,
                                    gleam_stdlib:println(
                                        <<"Tracker URL: "/utf8, Tracker/binary>>
                                    ),
                                    gleam_stdlib:println(
                                        <<"Length: "/utf8,
                                            (erlang:integer_to_binary(Length))/binary>>
                                    ),
                                    gleam_stdlib:println(
                                        <<"Info Hash: "/utf8, Encoded/binary>>
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

-file("src/torrent.gleam", 87).
-spec describe_error(torrent_error()) -> binary().
describe_error(Error) ->
    case Error of
        {invalid_torrent, Message} ->
            Message
    end.
