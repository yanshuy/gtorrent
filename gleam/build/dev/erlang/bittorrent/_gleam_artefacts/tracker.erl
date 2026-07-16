-module(tracker).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/tracker.gleam").
-export([split_peers/2, get_peers/4, describe_error/1]).
-export_type([tracker_error/0]).

-type tracker_error() :: invalid_url |
    {http_error, gleam@httpc:http_error()} |
    {decode_error, bencode:bencode_error()} |
    {invalid_response, binary()}.

-file("src/tracker.gleam", 143).
-spec parse_uncompact_peers(list(bencode:bencode()), list(binary())) -> {ok,
        list(binary())} |
    {error, nil}.
parse_uncompact_peers(List, Acc) ->
    case List of
        [] ->
            {ok, lists:reverse(Acc)};

        [Head | Rest] ->
            case Head of
                {b_dict, Entries} ->
                    Peer_dict = maps:from_list(Entries),
                    case {bencode:get_string(Peer_dict, <<"ip"/utf8>>),
                        bencode:get_int(Peer_dict, <<"port"/utf8>>)} of
                        {{ok, Ip}, {ok, Port}} ->
                            End_point = <<<<Ip/binary, ":"/utf8>>/binary,
                                (erlang:integer_to_binary(Port))/binary>>,
                            parse_uncompact_peers(Rest, [End_point | Acc]);

                        {_, _} ->
                            parse_uncompact_peers(Rest, Acc)
                    end;

                _ ->
                    parse_uncompact_peers(Rest, Acc)
            end
    end.

-file("src/tracker.gleam", 83).
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
                                line => 90,
                                value => _assert_fail,
                                start => 2314,
                                'end' => 2376,
                                pattern_start => 2325,
                                pattern_end => 2369})
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
                                line => 92,
                                value => _assert_fail@1,
                                start => 2384,
                                'end' => 2535,
                                pattern_start => 2395,
                                pattern_end => 2529})
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

-file("src/tracker.gleam", 41).
-spec decode_peers(bencode:bencode()) -> {ok, list(binary())} |
    {error, tracker_error()}.
decode_peers(Peers_value) ->
    case Peers_value of
        {b_string, Peers} ->
            _pipe = split_peers(Peers, []),
            gleam@result:replace_error(
                _pipe,
                {invalid_response, <<"malformed compact peers string"/utf8>>}
            );

        {b_list, Peer_list} ->
            _pipe@1 = parse_uncompact_peers(Peer_list, []),
            gleam@result:replace_error(
                _pipe@1,
                {invalid_response, <<"malformed legacy peers list"/utf8>>}
            );

        _ ->
            {error,
                {invalid_response,
                    <<"expected peers to be a string or a list"/utf8>>}}
    end.

-file("src/tracker.gleam", 59).
-spec construct_query_string(
    bitstring(),
    integer(),
    torrent@peer@protocol:peer_id()
) -> {ok, binary()} | {error, tracker_error()}.
construct_query_string(Info_hash, Length, Peer_id) ->
    Encoded = begin
        _pipe = Info_hash,
        helpers:percent_encode(_pipe)
    end,
    {peer_id, Id} = Peer_id,
    Peer_id@1 = begin
        _pipe@1 = Id,
        helpers:percent_encode(_pipe@1)
    end,
    Left = begin
        _pipe@2 = Length,
        erlang:integer_to_binary(_pipe@2)
    end,
    {ok,
        begin
            _pipe@3 = [<<"info_hash="/utf8, Encoded/binary>>,
                <<"peer_id="/utf8, Peer_id@1/binary>>,
                <<"port=6881"/utf8>>,
                <<"uploaded=0"/utf8>>,
                <<"downloaded=0"/utf8>>,
                <<"left="/utf8, Left/binary>>,
                <<"compact=1"/utf8>>],
            gleam@string:join(_pipe@3, <<"&"/utf8>>)
        end}.

-file("src/tracker.gleam", 20).
-spec get_peers(
    binary(),
    bitstring(),
    integer(),
    torrent@peer@protocol:peer_id()
) -> {ok, list(binary())} | {error, tracker_error()}.
get_peers(Tracker_url, Info_hash, Length, Peer_id) ->
    gleam@result:'try'(
        begin
            _pipe = gleam@http@request:to(Tracker_url),
            gleam@result:replace_error(_pipe, invalid_url)
        end,
        fun(Req) ->
            Req@1 = gleam@http@request:set_body(Req, <<>>),
            gleam@result:'try'(
                construct_query_string(Info_hash, Length, Peer_id),
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
                            _pipe@1 = gleam@httpc:send_bits(Req@2),
                            gleam@result:map_error(
                                _pipe@1,
                                fun(Field@0) -> {http_error, Field@0} end
                            )
                        end,
                        fun(Resp) ->
                            gleam@result:'try'(
                                begin
                                    _pipe@2 = bencode:decode(
                                        erlang:element(4, Resp)
                                    ),
                                    gleam@result:map_error(
                                        _pipe@2,
                                        fun(Field@0) -> {decode_error, Field@0} end
                                    )
                                end,
                                fun(Resp_bencode) ->
                                    gleam@result:'try'(
                                        begin
                                            _pipe@3 = bencode:dict(Resp_bencode),
                                            gleam@result:map_error(
                                                _pipe@3,
                                                fun(Field@0) -> {decode_error, Field@0} end
                                            )
                                        end,
                                        fun(Dict) ->
                                            gleam@result:'try'(
                                                begin
                                                    _pipe@4 = bencode:get_value(
                                                        Dict,
                                                        <<"peers"/utf8>>
                                                    ),
                                                    gleam@result:map_error(
                                                        _pipe@4,
                                                        fun(Field@0) -> {decode_error, Field@0} end
                                                    )
                                                end,
                                                fun(Peers) ->
                                                    decode_peers(Peers)
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

-file("src/tracker.gleam", 135).
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

-file("src/tracker.gleam", 114).
-spec describe_error(tracker_error()) -> binary().
describe_error(Error) ->
    case Error of
        invalid_url ->
            <<"Invalid tracker URL"/utf8>>;

        {http_error, Err} ->
            case Err of
                invalid_utf8_response ->
                    erlang:error(#{gleam_error => panic,
                            message => <<"using utf8 for req/resp"/utf8>>,
                            file => <<?FILEPATH/utf8>>,
                            module => <<"tracker"/utf8>>,
                            function => <<"describe_error"/utf8>>,
                            line => 119});

                {failed_to_connect, Ip4, Ip6} ->
                    <<<<<<<<"Failed to connect to tracker.\n"/utf8,
                                    "IPv4: "/utf8>>/binary,
                                (describe_connect_error(Ip4))/binary>>/binary,
                            "\nIPv6: "/utf8>>/binary,
                        (describe_connect_error(Ip6))/binary>>;

                response_timeout ->
                    <<"Tracker request timed out"/utf8>>
            end;

        {decode_error, Err@1} ->
            <<"Decoding: "/utf8, (bencode:describe_error(Err@1))/binary>>;

        {invalid_response, Msg} ->
            Msg
    end.
