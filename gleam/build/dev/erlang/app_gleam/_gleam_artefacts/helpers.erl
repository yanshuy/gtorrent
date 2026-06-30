-module(helpers).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/helpers.gleam").
-export([find_byte_index_loop/3, find_byte_index/2, take_until_byte/2, take_until/2]).

-file("src/helpers.gleam", 30).
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

-file("src/helpers.gleam", 26).
-spec find_byte_index(bitstring(), integer()) -> {ok, integer()} | {error, nil}.
find_byte_index(Bits, Target) ->
    find_byte_index_loop(Bits, Target, 0).

-file("src/helpers.gleam", 14).
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
                                line => 20,
                                value => _assert_fail,
                                start => 450,
                                'end' => 515,
                                pattern_start => 461,
                                pattern_end => 471})
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
                                line => 22,
                                value => _assert_fail@1,
                                start => 568,
                                'end' => 638,
                                pattern_start => 579,
                                pattern_end => 588})
            end,
            {ok, {Before@1, After@1}}
        end
    ).

-file("src/helpers.gleam", 4).
-spec take_until(bitstring(), binary()) -> {ok, {bitstring(), bitstring()}} |
    {error, nil}.
take_until(Bits, Delimiter) ->
    case gleam_stdlib:identity(Delimiter) of
        <<Delim/integer, _/bitstring>> when Delim < 128 ->
            take_until_byte(Bits, Delim);

        _ ->
            {error, nil}
    end.
