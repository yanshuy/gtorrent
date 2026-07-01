-module(bencode).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/bencode.gleam").
-export([decode/1, to_json/1, stringify_error/1]).
-export_type([bencode/0, decode_error/0]).

-type bencode() :: {b_dict, list({binary(), bencode()})} |
    {b_list, list(bencode())} |
    {b_string, binary()} |
    {b_integer, integer()}.

-type decode_error() :: unexpected_eof |
    invalid_integer |
    invalid_string_length |
    invalid_dictionary_key |
    invalid_utf8 |
    {invalid_prefix, integer()} |
    no_colon.

-file("src/bencode.gleam", 45).
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
                                line => 50,
                                value => _assert_fail,
                                start => 1135,
                                'end' => 1185,
                                pattern_start => 1146,
                                pattern_end => 1157})
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
                                                line => 60,
                                                value => _assert_fail@1,
                                                start => 1403,
                                                'end' => 1459,
                                                pattern_start => 1414,
                                                pattern_end => 1424})
                            end,
                            End = erlang:byte_size(Rest) - Str_length,
                            gleam@result:'try'(
                                begin
                                    _pipe@3 = gleam_stdlib:bit_array_slice(
                                        Rest,
                                        Str_length,
                                        End
                                    ),
                                    gleam@result:replace_error(
                                        _pipe@3,
                                        unexpected_eof
                                    )
                                end,
                                fun(Rem) ->
                                    {ok, {{b_string, String@1}, Rem}}
                                end
                            )
                        end
                    )
                end
            )
        end
    ).

-file("src/bencode.gleam", 71).
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
                                line => 77,
                                value => _assert_fail,
                                start => 1850,
                                'end' => 1896,
                                pattern_start => 1861,
                                pattern_end => 1868})
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

-file("src/bencode.gleam", 100).
-spec decode_dictionary(bitstring(), list({binary(), bencode()})) -> {ok,
        {bencode(), bitstring()}} |
    {error, decode_error()}.
decode_dictionary(Bits, Entries) ->
    case Bits of
        <<"e"/utf8, Rest/bitstring>> ->
            Bdict = {b_dict, lists:reverse(Entries)},
            {ok, {Bdict, Rest}};

        _ ->
            gleam@result:'try'(
                begin
                    _pipe = decode_string(Bits),
                    gleam@result:replace_error(_pipe, invalid_dictionary_key)
                end,
                fun(_use0) ->
                    {String, Rest@1} = _use0,
                    Key@1 = case String of
                        {b_string, Key} -> Key;
                        _assert_fail ->
                            erlang:error(#{gleam_error => let_assert,
                                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                                        file => <<?FILEPATH/utf8>>,
                                        module => <<"bencode"/utf8>>,
                                        function => <<"decode_dictionary"/utf8>>,
                                        line => 114,
                                        value => _assert_fail,
                                        start => 2746,
                                        'end' => 2778,
                                        pattern_start => 2757,
                                        pattern_end => 2769})
                    end,
                    gleam@result:'try'(
                        decode_loop(Rest@1),
                        fun(_use0@1) ->
                            {Value, Rest@2} = _use0@1,
                            decode_dictionary(
                                Rest@2,
                                [{Key@1, Value} | Entries]
                            )
                        end
                    )
                end
            )
    end.

-file("src/bencode.gleam", 84).
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

-file("src/bencode.gleam", 30).
-spec decode_loop(bitstring()) -> {ok, {bencode(), bitstring()}} |
    {error, decode_error()}.
decode_loop(Bits) ->
    case Bits of
        <<"i"/utf8, Rest/bitstring>> ->
            decode_integer(Rest);

        <<"l"/utf8, Rest@1/bitstring>> ->
            decode_list(Rest@1, []);

        <<"d"/utf8, Rest@2/bitstring>> ->
            decode_dictionary(Rest@2, []);

        <<Byte, _/bitstring>> when (Byte >= 48) andalso (Byte =< 57) ->
            decode_string(Bits);

        <<_:1, _/bitstring>> ->
            {error, invalid_utf8};

        <<>> ->
            {error, unexpected_eof};

        _ ->
            {error, unexpected_eof}
    end.

-file("src/bencode.gleam", 25).
-spec decode(bitstring()) -> {ok, bencode()} | {error, decode_error()}.
decode(Encoded_value) ->
    gleam@result:'try'(
        decode_loop(Encoded_value),
        fun(_use0) ->
            {Value, _} = _use0,
            {ok, Value}
        end
    ).

-file("src/bencode.gleam", 123).
-spec to_json(bencode()) -> gleam@json:json().
to_json(Value) ->
    case Value of
        {b_dict, Entries} ->
            gleam@json:object(
                gleam@list:map(
                    Entries,
                    fun(Entry) ->
                        {erlang:element(1, Entry),
                            to_json(erlang:element(2, Entry))}
                    end
                )
            );

        {b_list, List} ->
            gleam@json:array(List, fun to_json/1);

        {b_string, String} ->
            gleam@json:string(String);

        {b_integer, Integer} ->
            gleam@json:int(Integer)
    end.

-file("src/bencode.gleam", 133).
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
            <<"The ':' character is not found in the binary"/utf8>>;

        invalid_dictionary_key ->
            <<"Invalid dict key"/utf8>>
    end.
