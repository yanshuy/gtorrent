-module(bencode).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/bencode.gleam").
-export([decode/1, to_json/1, stringify_error/1]).
-export_type([bencode/0, decode_error/0]).

-type bencode() :: {b_list, list(bencode())} |
    {b_string, binary()} |
    {b_integer, integer()}.

-type decode_error() :: unexpected_eof |
    invalid_integer |
    invalid_string_length |
    invalid_utf8 |
    {invalid_prefix, integer()} |
    no_colon.

-file("src/bencode.gleam", 41).
-spec decode_string(bitstring()) -> {ok, {bencode(), bitstring()}} |
    {error, decode_error()}.
decode_string(Bits) ->
    gleam@result:'try'(
        begin
            _pipe = helpers:take_until(Bits, <<":"/utf8>>),
            gleam@result:replace_error(_pipe, no_colon)
        end,
        fun(_use0) ->
            {Bits@1, Rest} = _use0,
            Num_str@1 = case gleam@bit_array:to_string(Bits@1) of
                {ok, Num_str} -> Num_str;
                _assert_fail ->
                    erlang:error(#{gleam_error => let_assert,
                                message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                                file => <<?FILEPATH/utf8>>,
                                module => <<"bencode"/utf8>>,
                                function => <<"decode_string"/utf8>>,
                                line => 46,
                                value => _assert_fail,
                                start => 1018,
                                'end' => 1068,
                                pattern_start => 1029,
                                pattern_end => 1040})
            end,
            gleam@result:'try'(
                begin
                    _pipe@1 = gleam_stdlib:parse_int(Num_str@1),
                    gleam@result:replace_error(_pipe@1, invalid_string_length)
                end,
                fun(Str_length) ->
                    gleam@result:'try'(
                        begin
                            _pipe@2 = gleam_stdlib:bit_array_slice(
                                Rest,
                                0,
                                Str_length
                            ),
                            gleam@result:replace_error(_pipe@2, unexpected_eof)
                        end,
                        fun(String_bits) ->
                            String@1 = case gleam@bit_array:to_string(
                                String_bits
                            ) of
                                {ok, String} -> String;
                                _assert_fail@1 ->
                                    erlang:error(#{gleam_error => let_assert,
                                                message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                                                file => <<?FILEPATH/utf8>>,
                                                module => <<"bencode"/utf8>>,
                                                function => <<"decode_string"/utf8>>,
                                                line => 56,
                                                value => _assert_fail@1,
                                                start => 1283,
                                                'end' => 1339,
                                                pattern_start => 1294,
                                                pattern_end => 1304})
                            end,
                            {ok, {{b_string, String@1}, Rest}}
                        end
                    )
                end
            )
        end
    ).

-file("src/bencode.gleam", 61).
-spec decode_integer(bitstring()) -> {ok, {bencode(), bitstring()}} |
    {error, decode_error()}.
decode_integer(Bits) ->
    gleam@result:'try'(
        begin
            _pipe = helpers:take_until(Bits, <<"e"/utf8>>),
            gleam@result:replace_error(_pipe, invalid_integer)
        end,
        fun(_use0) ->
            {Bits@1, Rest} = _use0,
            Str@1 = case gleam@bit_array:to_string(Bits@1) of
                {ok, Str} -> Str;
                _assert_fail ->
                    erlang:error(#{gleam_error => let_assert,
                                message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                                file => <<?FILEPATH/utf8>>,
                                module => <<"bencode"/utf8>>,
                                function => <<"decode_integer"/utf8>>,
                                line => 67,
                                value => _assert_fail,
                                start => 1570,
                                'end' => 1616,
                                pattern_start => 1581,
                                pattern_end => 1588})
            end,
            gleam@result:'try'(
                begin
                    _pipe@1 = gleam_stdlib:parse_int(Str@1),
                    gleam@result:replace_error(_pipe@1, invalid_integer)
                end,
                fun(Integer) -> {ok, {{b_integer, Integer}, Rest}} end
            )
        end
    ).

-file("src/bencode.gleam", 74).
-spec decode_list(bitstring(), list(bencode())) -> {ok,
        {bencode(), bitstring()}} |
    {error, decode_error()}.
decode_list(Bits, List) ->
    case Bits of
        <<"e"/utf8, Rest/bitstring>> ->
            Blist = {b_list, lists:reverse(List)},
            {ok, {Blist, Rest}};

        _ ->
            gleam@result:'try'(
                decode_loop(Bits),
                fun(_use0) ->
                    {Decoded, Rest@1} = _use0,
                    decode_list(Rest@1, [Decoded | List])
                end
            )
    end.

-file("src/bencode.gleam", 28).
-spec decode_loop(bitstring()) -> {ok, {bencode(), bitstring()}} |
    {error, decode_error()}.
decode_loop(Bits) ->
    case Bits of
        <<"i"/utf8, Rest/bitstring>> ->
            decode_integer(Rest);

        <<"l"/utf8, Rest@1/bitstring>> ->
            decode_list(Rest@1, []);

        <<Byte, _/bitstring>> when (Byte >= 48) andalso (Byte =< 57) ->
            decode_string(Bits);

        <<_:1, _/bitstring>> ->
            {error, invalid_utf8};

        <<>> ->
            {error, unexpected_eof};

        _ ->
            {error, unexpected_eof}
    end.

-file("src/bencode.gleam", 23).
-spec decode(bitstring()) -> {ok, bencode()} | {error, decode_error()}.
decode(Encoded_value) ->
    gleam@result:'try'(
        decode_loop(Encoded_value),
        fun(_use0) ->
            {Value, _} = _use0,
            {ok, Value}
        end
    ).

-file("src/bencode.gleam", 90).
-spec to_json(bencode()) -> gleam@json:json().
to_json(Value) ->
    case Value of
        {b_list, List} ->
            gleam@json:array(List, fun to_json/1);

        {b_string, String} ->
            gleam@json:string(String);

        {b_integer, Integer} ->
            gleam@json:int(Integer)
    end.

-file("src/bencode.gleam", 98).
-spec stringify_error(decode_error()) -> binary().
stringify_error(Error) ->
    case Error of
        unexpected_eof ->
            <<"Unexpected end of input"/utf8>>;

        invalid_integer ->
            <<"Invalid integer"/utf8>>;

        invalid_string_length ->
            <<"Invalid string length"/utf8>>;

        invalid_utf8 ->
            <<"Invalid UTF-8"/utf8>>;

        {invalid_prefix, Byte} ->
            <<"Invalid prefix: "/utf8, (erlang:integer_to_binary(Byte))/binary>>;

        no_colon ->
            <<"The ':' character is not found in the binary"/utf8>>
    end.
