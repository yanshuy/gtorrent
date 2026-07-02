-module(helpers).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/helpers.gleam").
-export([find_byte_index_loop/3, find_byte_index/2, take_until_byte/2, take_until/2, percent_encode/1]).

-file("src/helpers.gleam", 32).
-spec find_byte_index_loop(bitstring(), integer(), integer()) -> {ok, integer()} |
    {error, nil}.
find_byte_index_loop(Bits, Target, Idx) ->
    case Bits of
        <<Byte, Rest/bitstring>> ->
            case Byte =:= Target of
                true ->
                    {ok, Idx};

                false ->
                    find_byte_index_loop(Rest, Target, Idx + 1)
            end;

        <<>> ->
            {error, nil};

        <<_:1, _/bitstring>> ->
            {error, nil};

        _ ->
            {error, nil}
    end.

-file("src/helpers.gleam", 28).
-spec find_byte_index(bitstring(), integer()) -> {ok, integer()} | {error, nil}.
find_byte_index(Bits, Target) ->
    find_byte_index_loop(Bits, Target, 0).

-file("src/helpers.gleam", 16).
-spec take_until_byte(bitstring(), integer()) -> {ok,
        {bitstring(), bitstring()}} |
    {error, nil}.
take_until_byte(Bits, Delimiter) ->
    gleam@result:'try'(
        find_byte_index(Bits, Delimiter),
        fun(Index) ->
            Before@1 = case gleam_stdlib:bit_array_slice(Bits, 0, Index) of
                {ok, Before} -> Before;
                _assert_fail ->
                    erlang:error(#{gleam_error => let_assert,
                                message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                                file => <<?FILEPATH/utf8>>,
                                module => <<"helpers"/utf8>>,
                                function => <<"take_until_byte"/utf8>>,
                                line => 22,
                                value => _assert_fail,
                                start => 488,
                                'end' => 553,
                                pattern_start => 499,
                                pattern_end => 509})
            end,
            End = (erlang:byte_size(Bits) - Index) - 1,
            After@1 = case gleam_stdlib:bit_array_slice(Bits, Index + 1, End) of
                {ok, After} -> After;
                _assert_fail@1 ->
                    erlang:error(#{gleam_error => let_assert,
                                message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                                file => <<?FILEPATH/utf8>>,
                                module => <<"helpers"/utf8>>,
                                function => <<"take_until_byte"/utf8>>,
                                line => 24,
                                value => _assert_fail@1,
                                start => 606,
                                'end' => 676,
                                pattern_start => 617,
                                pattern_end => 626})
            end,
            {ok, {Before@1, After@1}}
        end
    ).

-file("src/helpers.gleam", 6).
-spec take_until(bitstring(), binary()) -> {ok, {bitstring(), bitstring()}} |
    {error, nil}.
take_until(Bits, Delimiter) ->
    case gleam_stdlib:identity(Delimiter) of
        <<Delim/integer, _/bitstring>> when Delim < 128 ->
            take_until_byte(Bits, Delim);

        _ ->
            {error, nil}
    end.

-file("src/helpers.gleam", 79).
-spec ascii(integer()) -> binary().
ascii(Byte) ->
    String@1 = case begin
        _pipe = <<Byte>>,
        gleam@bit_array:to_string(_pipe)
    end of
        {ok, String} -> String;
        _assert_fail ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"helpers"/utf8>>,
                        function => <<"ascii"/utf8>>,
                        line => 80,
                        value => _assert_fail,
                        start => 1881,
                        'end' => 1936,
                        pattern_start => 1892,
                        pattern_end => 1902})
    end,
    String@1.

-file("src/helpers.gleam", 69).
-spec is_unreserved(integer()) -> boolean().
is_unreserved(Byte) ->
    case Byte of
        _ when (Byte >= 65) andalso (Byte =< 90) ->
            true;

        _ when (Byte >= 97) andalso (Byte =< 122) ->
            true;

        _ when (Byte >= 48) andalso (Byte =< 57) ->
            true;

        45 ->
            true;

        46 ->
            true;

        95 ->
            true;

        126 ->
            true;

        _ ->
            false
    end.

-file("src/helpers.gleam", 52).
-spec percent_encode_loop(bitstring(), list(binary())) -> binary().
percent_encode_loop(Bits, Acc) ->
    case Bits of
        <<>> ->
            _pipe = lists:reverse(Acc),
            erlang:list_to_binary(_pipe);

        <<Byte, Rest/bitstring>> ->
            Part = case is_unreserved(Byte) of
                true ->
                    ascii(Byte);

                false ->
                    <<"%"/utf8,
                        (gleam_stdlib:base16_encode(<<Byte:8>>))/binary>>
            end,
            percent_encode_loop(Rest, [Part | Acc]);

        _ ->
            erlang:error(#{gleam_error => panic,
                    message => <<"`panic` expression evaluated."/utf8>>,
                    file => <<?FILEPATH/utf8>>,
                    module => <<"helpers"/utf8>>,
                    function => <<"percent_encode_loop"/utf8>>,
                    line => 65})
    end.

-file("src/helpers.gleam", 48).
-spec percent_encode(bitstring()) -> binary().
percent_encode(Bits) ->
    percent_encode_loop(Bits, []).
