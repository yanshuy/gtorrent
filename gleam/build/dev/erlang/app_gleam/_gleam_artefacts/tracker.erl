-module(tracker).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/tracker.gleam").
-export([split_peers/2, get_peers/2, describe_error/1]).
-export_type([tracker_error/0]).

-type tracker_error() :: {http_error, gleam@httpc:http_error()} |
    {torrent_error, torrent:torrent_error()} |
    {decode_error, bencode:decode_error()} |
    invalid_url |
    {invalid_response, binary()}.

-file("src/tracker.gleam", 77).
-spec split_peers(bitstring(), list(binary())) -> {ok, list(binary())} |
    {error, nil}.
split_peers(Peers, Acc) ->
    case Peers of
        <<>> ->
            {ok, lists:reverse(Acc)};

        <<Peer:6/binary-unit:8, Rest/bitstring>> ->
            {Ip4@1, Port@1} = case Peer of
                <<Ip4:4/binary-unit:8, Port:16>> -> {Ip4, Port};
                _assert_fail ->
                    erlang:error(#{gleam_error => let_assert,
                                message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                                file => <<?FILEPATH/utf8>>,
                                module => <<"tracker"/utf8>>,
                                function => <<"split_peers"/utf8>>,
                                line => 84,
                                value => _assert_fail,
                                start => 2281,
                                'end' => 2343,
                                pattern_start => 2292,
                                pattern_end => 2336})
            end,
            {One@1, Two@1, Three@1, Four@1} = case Ip4@1 of
                <<One:8/unsigned,
                    Two:8/unsigned,
                    Three:8/unsigned,
                    Four:8/unsigned>> -> {One, Two, Three, Four};
                _assert_fail@1 ->
                    erlang:error(#{gleam_error => let_assert,
                                message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                                file => <<?FILEPATH/utf8>>,
                                module => <<"tracker"/utf8>>,
                                function => <<"split_peers"/utf8>>,
                                line => 86,
                                value => _assert_fail@1,
                                start => 2351,
                                'end' => 2502,
                                pattern_start => 2362,
                                pattern_end => 2496})
            end,
            Ip_addr = <<<<<<<<<<<<(erlang:integer_to_binary(One@1))/binary,
                                    "."/utf8>>/binary,
                                (erlang:integer_to_binary(Two@1))/binary>>/binary,
                            "."/utf8>>/binary,
                        (erlang:integer_to_binary(Three@1))/binary>>/binary,
                    "."/utf8>>/binary,
                (erlang:integer_to_binary(Four@1))/binary>>,
            End_point = <<<<Ip_addr/binary, ":"/utf8>>/binary,
                (erlang:integer_to_binary(Port@1))/binary>>,
            split_peers(Rest, [End_point | Acc]);

        _ ->
            {error, nil}
    end.

-file("src/tracker.gleam", 46).
-spec construct_query_string(
    gleam@dict:dict(binary(), bencode:bencode()),
    bitstring()
) -> {ok, binary()} | {error, tracker_error()}.
construct_query_string(Torrent, Peer_id) ->
    gleam@result:'try'(
        begin
            _pipe = torrent:get_entries(Torrent, <<"info"/utf8>>),
            gleam@result:map_error(
                _pipe,
                fun(Field@0) -> {torrent_error, Field@0} end
            )
        end,
        fun(Info_entries) ->
            Info_hash = begin
                _pipe@1 = torrent:digest_entries(Info_entries),
                helpers:percent_encode(_pipe@1)
            end,
            Peer_id@1 = begin
                _pipe@2 = Peer_id,
                helpers:percent_encode(_pipe@2)
            end,
            Info_dict = maps:from_list(Info_entries),
            gleam@result:'try'(
                begin
                    _pipe@3 = torrent:get_int(Info_dict, <<"length"/utf8>>),
                    gleam@result:map_error(
                        _pipe@3,
                        fun(Field@0) -> {torrent_error, Field@0} end
                    )
                end,
                fun(Length) ->
                    Left = Length,
                    {ok,
                        begin
                            _pipe@4 = [<<"info_hash="/utf8, Info_hash/binary>>,
                                <<"peer_id="/utf8, Peer_id@1/binary>>,
                                <<"port=6881"/utf8>>,
                                <<"uploaded=0"/utf8>>,
                                <<"downloaded=0"/utf8>>,
                                <<"left="/utf8,
                                    (erlang:integer_to_binary(Left))/binary>>,
                                <<"compact=1"/utf8>>],
                            gleam@string:join(_pipe@4, <<"&"/utf8>>)
                        end}
                end
            )
        end
    ).

-file("src/tracker.gleam", 21).
-spec get_peers(bencode:bencode(), bitstring()) -> {ok, list(binary())} |
    {error, tracker_error()}.
get_peers(Torrent, Peer_id) ->
    gleam@result:'try'(
        begin
            _pipe = torrent:dict(Torrent),
            gleam@result:map_error(
                _pipe,
                fun(Field@0) -> {torrent_error, Field@0} end
            )
        end,
        fun(Dict) ->
            gleam@result:'try'(
                begin
                    _pipe@1 = torrent:get_string(Dict, <<"announce"/utf8>>),
                    gleam@result:map_error(
                        _pipe@1,
                        fun(Field@0) -> {torrent_error, Field@0} end
                    )
                end,
                fun(Tracker_url) ->
                    gleam@result:'try'(
                        begin
                            _pipe@2 = gleam@http@request:to(Tracker_url),
                            gleam@result:replace_error(_pipe@2, invalid_url)
                        end,
                        fun(Req) ->
                            Req@1 = gleam@http@request:set_body(Req, <<>>),
                            gleam@result:'try'(
                                construct_query_string(Dict, Peer_id),
                                fun(Query_string) ->
                                    Req@2 = {request,
                                        erlang:element(2, Req@1),
                                        erlang:element(3, Req@1),
                                        erlang:element(4, Req@1),
                                        erlang:element(5, Req@1),
                                        erlang:element(6, Req@1),
                                        erlang:element(7, Req@1),
                                        erlang:element(8, Req@1),
                                        {some, Query_string}},
                                    gleam@result:'try'(
                                        begin
                                            _pipe@3 = gleam@httpc:send_bits(
                                                Req@2
                                            ),
                                            gleam@result:map_error(
                                                _pipe@3,
                                                fun(Field@0) -> {http_error, Field@0} end
                                            )
                                        end,
                                        fun(Resp) ->
                                            gleam@result:'try'(
                                                begin
                                                    _pipe@4 = bencode:decode(
                                                        erlang:element(4, Resp)
                                                    ),
                                                    gleam@result:map_error(
                                                        _pipe@4,
                                                        fun(Field@0) -> {decode_error, Field@0} end
                                                    )
                                                end,
                                                fun(Resp_bencode) ->
                                                    gleam@result:'try'(
                                                        begin
                                                            _pipe@5 = torrent:dict(
                                                                Resp_bencode
                                                            ),
                                                            gleam@result:map_error(
                                                                _pipe@5,
                                                                fun(Field@0) -> {torrent_error, Field@0} end
                                                            )
                                                        end,
                                                        fun(Dict@1) ->
                                                            gleam@result:'try'(
                                                                begin
                                                                    _pipe@6 = torrent:get_string_bits(
                                                                        Dict@1,
                                                                        <<"peers"/utf8>>
                                                                    ),
                                                                    gleam@result:map_error(
                                                                        _pipe@6,
                                                                        fun(Field@0) -> {torrent_error, Field@0} end
                                                                    )
                                                                end,
                                                                fun(Peers) ->
                                                                    _pipe@7 = split_peers(
                                                                        Peers,
                                                                        []
                                                                    ),
                                                                    gleam@result:replace_error(
                                                                        _pipe@7,
                                                                        {invalid_response,
                                                                            <<"malformed peers list"/utf8>>}
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

-file("src/tracker.gleam", 134).
-spec describe_connect_error(gleam@httpc:connect_error()) -> binary().
describe_connect_error(Error) ->
    case Error of
        {posix, Code} ->
            <<"POSIX error: "/utf8, Code/binary>>;

        {tls_alert, Code@1, Detail} ->
            <<<<<<<<"TLS alert: "/utf8, Code@1/binary>>/binary, " ("/utf8>>/binary,
                    Detail/binary>>/binary,
                ")"/utf8>>
    end.

-file("src/tracker.gleam", 108).
-spec describe_error(tracker_error()) -> binary().
describe_error(Error) ->
    case Error of
        {http_error, Err} ->
            case Err of
                invalid_utf8_response ->
                    erlang:error(#{gleam_error => panic,
                            message => <<"using utf8 for req/resp"/utf8>>,
                            file => <<?FILEPATH/utf8>>,
                            module => <<"tracker"/utf8>>,
                            function => <<"describe_error"/utf8>>,
                            line => 112});

                {failed_to_connect, Ip4, Ip6} ->
                    <<<<<<<<"Failed to connect to tracker.\n"/utf8,
                                    "IPv4: "/utf8>>/binary,
                                (describe_connect_error(Ip4))/binary>>/binary,
                            "\nIPv6: "/utf8>>/binary,
                        (describe_connect_error(Ip6))/binary>>;

                response_timeout ->
                    <<"Tracker request timed out"/utf8>>
            end;

        {torrent_error, Err@1} ->
            <<"Response Torrent: "/utf8,
                (torrent:describe_error(Err@1))/binary>>;

        {decode_error, Err@2} ->
            <<"Decoding: "/utf8, (bencode:describe_error(Err@2))/binary>>;

        {invalid_response, Msg} ->
            Msg;

        invalid_url ->
            <<"Invalid tracker URL"/utf8>>
    end.
