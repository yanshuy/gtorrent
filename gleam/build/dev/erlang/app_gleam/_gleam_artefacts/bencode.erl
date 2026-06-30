-module(bencode).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/bencode.gleam").
-export([decode/1, to_json/1, stringify_error/1]).
-export_type([bencode/0, decode_error/0]).

-type bencode() :: {b_string, binary()} | {b_integer, integer()}.

-type decode_error() :: unexpected_eof |
    invalid_integer |
    invalid_string_length |
    invalid_utf8 |
    {invalid_prefix, integer()} |
    no_colon.

-file("src/bencode.gleam", 44).
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
                                line => 50,
                                value => _assert_fail,
                                start => 999,
                                'end' => 1045,
                                pattern_start => 1010,
                                pattern_end => 1017})
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

-file("src/bencode.gleam", 21).
-spec decode(bitstring()) -> {ok, bencode()} | {error, decode_error()}.
decode(Encoded_value) ->
    case Encoded_value of
        <<":"/utf8, Rest/bitstring>> ->
            case gleam@bit_array:to_string(Rest) of
                {ok, Str} ->
                    {ok, {b_string, Str}};

                {error, _} ->
                    {error, invalid_utf8}
            end;

        <<"i"/utf8, Rest@1/bitstring>> ->
            _pipe = decode_integer(Rest@1),
            gleam@result:map(
                _pipe,
                fun(Result) ->
                    {Integer, _} = Result,
                    Integer
                end
            );

        <<_, Rest@2/bitstring>> ->
            decode(Rest@2);

        <<>> ->
            {error, no_colon};

        <<_:1, _/bitstring>> ->
            {error, no_colon};

        _ ->
            {error, no_colon}
    end.

-file("src/bencode.gleam", 57).
-spec to_json(bencode()) -> gleam@json:json().
to_json(Value) ->
    case Value of
        {b_string, String} ->
            gleam@json:string(String);

        {b_integer, Integer} ->
            gleam@json:int(Integer)
    end.

-file("src/bencode.gleam", 64).
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
