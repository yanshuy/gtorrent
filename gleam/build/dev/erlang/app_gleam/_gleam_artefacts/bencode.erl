-module(bencode).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/bencode.gleam").
-export([decode/1, encode/1, to_json/1, digest_entries/1, split_piece_hashes/2, dict/1, get_value/2, get_string_bits/2, get_int/2, get_entries/2, get_string/2, parse_torrent/1, describe_error/1]).
-export_type([bencode/0, decode_error/0, torrent/0]).

-type bencode() :: {b_dict, list({binary(), bencode()})} |
    {b_list, list(bencode())} |
    {b_string, bitstring()} |
    {b_integer, integer()}.

-type decode_error() :: unexpected_eof |
    invalid_integer |
    invalid_string_length |
    invalid_utf8 |
    {invalid_prefix, integer()} |
    {missing_key, binary()} |
    {invalid_torrent, binary()} |
    no_colon.

-type torrent() :: {torrent,
        binary(),
        binary(),
        integer(),
        integer(),
        list(bitstring()),
        bitstring()}.

-file("src/bencode.gleam", 48).
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
            gleam@result:'try'(
                begin
                    _pipe@1 = gleam@bit_array:to_string(Bits@1),
                    gleam@result:replace_error(_pipe@1, invalid_utf8)
                end,
                fun(Num_str) ->
                    gleam@result:'try'(
                        begin
                            _pipe@2 = gleam_stdlib:parse_int(Num_str),
                            gleam@result:replace_error(
                                _pipe@2,
                                invalid_string_length
                            )
                        end,
                        fun(Str_length) ->
                            gleam@result:'try'(
                                begin
                                    _pipe@3 = gleam_stdlib:bit_array_slice(
                                        Rest,
                                        0,
                                        Str_length
                                    ),
                                    gleam@result:replace_error(
                                        _pipe@3,
                                        unexpected_eof
                                    )
                                end,
                                fun(String_bits) ->
                                    End = erlang:byte_size(Rest) - Str_length,
                                    gleam@result:'try'(
                                        begin
                                            _pipe@4 = gleam_stdlib:bit_array_slice(
                                                Rest,
                                                Str_length,
                                                End
                                            ),
                                            gleam@result:replace_error(
                                                _pipe@4,
                                                unexpected_eof
                                            )
                                        end,
                                        fun(Rem) ->
                                            {ok, {{b_string, String_bits}, Rem}}
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

-file("src/bencode.gleam", 76).
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
                                line => 82,
                                value => _assert_fail,
                                start => 1904,
                                'end' => 1950,
                                pattern_start => 1915,
                                pattern_end => 1922})
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

-file("src/bencode.gleam", 105).
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
                decode_string(Bits),
                fun(_use0) ->
                    {String, Rest@1} = _use0,
                    Key_bits@1 = case String of
                        {b_string, Key_bits} -> Key_bits;
                        _assert_fail ->
                            erlang:error(#{gleam_error => let_assert,
                                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                                        file => <<?FILEPATH/utf8>>,
                                        module => <<"bencode"/utf8>>,
                                        function => <<"decode_dictionary"/utf8>>,
                                        line => 117,
                                        value => _assert_fail,
                                        start => 2737,
                                        'end' => 2774,
                                        pattern_start => 2748,
                                        pattern_end => 2765})
                    end,
                    Key@1 = case gleam@bit_array:to_string(Key_bits@1) of
                        {ok, Key} -> Key;
                        _assert_fail@1 ->
                            erlang:error(#{gleam_error => let_assert,
                                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                                        file => <<?FILEPATH/utf8>>,
                                        module => <<"bencode"/utf8>>,
                                        function => <<"decode_dictionary"/utf8>>,
                                        line => 118,
                                        value => _assert_fail@1,
                                        start => 2781,
                                        'end' => 2831,
                                        pattern_start => 2792,
                                        pattern_end => 2799})
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

-file("src/bencode.gleam", 89).
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

-file("src/bencode.gleam", 33).
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

-file("src/bencode.gleam", 28).
-spec decode(bitstring()) -> {ok, bencode()} | {error, decode_error()}.
decode(Encoded_value) ->
    gleam@result:'try'(
        decode_loop(Encoded_value),
        fun(_use0) ->
            {Value, _} = _use0,
            {ok, Value}
        end
    ).

-file("src/bencode.gleam", 161).
-spec encode_entries(list({binary(), bencode()}), list(bitstring())) -> bitstring().
encode_entries(Entries, Acc) ->
    case Entries of
        [] ->
            _pipe = lists:reverse(Acc),
            gleam_stdlib:bit_array_concat(_pipe);

        [{Key, Value} | Rest] ->
            Key@1 = encode({b_string, gleam_stdlib:identity(Key)}),
            Value@1 = encode(Value),
            encode_entries(Rest, [<<Key@1/bitstring, Value@1/bitstring>> | Acc])
    end.

-file("src/bencode.gleam", 148).
-spec encode_list(list(bencode()), list(bitstring())) -> bitstring().
encode_list(Values, Acc) ->
    case Values of
        [] ->
            _pipe = lists:reverse(Acc),
            gleam_stdlib:bit_array_concat(_pipe);

        [Head | Rest] ->
            First = encode(Head),
            encode_list(Rest, [First | Acc])
    end.

-file("src/bencode.gleam", 127).
-spec encode(bencode()) -> bitstring().
encode(Value) ->
    case Value of
        {b_integer, Integer} ->
            <<"i"/utf8, (erlang:integer_to_binary(Integer))/binary, "e"/utf8>>;

        {b_string, Bits} ->
            Length = begin
                _pipe = erlang:byte_size(Bits),
                erlang:integer_to_binary(_pipe)
            end,
            <<Length/binary, ":"/utf8, Bits/bitstring>>;

        {b_list, Values} ->
            List = encode_list(Values, []),
            <<"l"/utf8, List/bitstring, "e"/utf8>>;

        {b_dict, Entries} ->
            Entries@1 = encode_entries(Entries, []),
            <<"d"/utf8, Entries@1/bitstring, "e"/utf8>>
    end.

-file("src/bencode.gleam", 178).
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

        {b_string, Bits} ->
            String@1 = case gleam@bit_array:to_string(Bits) of
                {ok, String} -> String;
                _assert_fail ->
                    erlang:error(#{gleam_error => let_assert,
                                message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                                file => <<?FILEPATH/utf8>>,
                                module => <<"bencode"/utf8>>,
                                function => <<"to_json"/utf8>>,
                                line => 184,
                                value => _assert_fail,
                                start => 4336,
                                'end' => 4385,
                                pattern_start => 4347,
                                pattern_end => 4357})
            end,
            gleam@json:string(String@1);

        {b_integer, Integer} ->
            gleam@json:int(Integer)
    end.

-file("src/bencode.gleam", 240).
-spec digest_entries(list({binary(), bencode()})) -> bitstring().
digest_entries(Info_entries) ->
    Bits = begin
        _pipe = {b_dict, Info_entries},
        encode(_pipe)
    end,
    gleam@crypto:hash(sha1, Bits).

-file("src/bencode.gleam", 245).
-spec split_piece_hashes(bitstring(), list(bitstring())) -> list(bitstring()).
split_piece_hashes(Bits, Acc) ->
    case Bits of
        <<>> ->
            lists:reverse(Acc);

        <<First:20/binary, Rest/bitstring>> ->
            split_piece_hashes(Rest, [First | Acc]);

        _ ->
            Acc
    end.

-file("src/bencode.gleam", 228).
-spec dict(bencode()) -> {ok, gleam@dict:dict(binary(), bencode())} |
    {error, decode_error()}.
dict(Meta_info) ->
    case Meta_info of
        {b_dict, Entries} ->
            Dict = maps:from_list(Entries),
            {ok, Dict};

        _ ->
            {error, {invalid_torrent, <<"Not valid"/utf8>>}}
    end.

-file("src/bencode.gleam", 259).
-spec get_value(gleam@dict:dict(binary(), bencode()), binary()) -> {ok,
        bencode()} |
    {error, decode_error()}.
get_value(Torrent, Key) ->
    _pipe = gleam_stdlib:map_get(Torrent, Key),
    gleam@result:replace_error(_pipe, {missing_key, Key}).

-file("src/bencode.gleam", 282).
-spec get_string_bits(gleam@dict:dict(binary(), bencode()), binary()) -> {ok,
        bitstring()} |
    {error, decode_error()}.
get_string_bits(Torrent, Key) ->
    gleam@result:'try'(
        get_value(Torrent, Key),
        fun(Value) ->
            Error = {invalid_torrent,
                <<"Expected string for key: "/utf8, Key/binary>>},
            case Value of
                {b_string, Bits} ->
                    {ok, Bits};

                _ ->
                    {error, Error}
            end
        end
    ).

-file("src/bencode.gleam", 295).
-spec get_int(gleam@dict:dict(binary(), bencode()), binary()) -> {ok, integer()} |
    {error, decode_error()}.
get_int(Torrent, Key) ->
    gleam@result:'try'(get_value(Torrent, Key), fun(Value) -> case Value of
                {b_integer, Integer} ->
                    {ok, Integer};

                _ ->
                    {error,
                        {invalid_torrent,
                            <<"Expected integer for key: "/utf8, Key/binary>>}}
            end end).

-file("src/bencode.gleam", 307).
-spec get_entries(gleam@dict:dict(binary(), bencode()), binary()) -> {ok,
        list({binary(), bencode()})} |
    {error, decode_error()}.
get_entries(Torrent, Key) ->
    gleam@result:'try'(get_value(Torrent, Key), fun(Value) -> case Value of
                {b_dict, Entries} ->
                    {ok, Entries};

                _ ->
                    {error,
                        {invalid_torrent,
                            <<"Expected dictionary for key: "/utf8, Key/binary>>}}
            end end).

-file("src/bencode.gleam", 267).
-spec get_string(gleam@dict:dict(binary(), bencode()), binary()) -> {ok,
        binary()} |
    {error, decode_error()}.
get_string(Torrent, Key) ->
    gleam@result:'try'(
        get_value(Torrent, Key),
        fun(Value) ->
            Error = {invalid_torrent,
                <<"Expected utf8 string for key: "/utf8, Key/binary>>},
            case Value of
                {b_string, Bits} ->
                    _pipe = gleam@bit_array:to_string(Bits),
                    gleam@result:replace_error(_pipe, Error);

                _ ->
                    {error, Error}
            end
        end
    ).

-file("src/bencode.gleam", 202).
-spec parse_torrent(bencode()) -> {ok, torrent()} | {error, decode_error()}.
parse_torrent(Torrent) ->
    gleam@result:'try'(
        dict(Torrent),
        fun(Dict) ->
            Name = begin
                _pipe = get_string(Dict, <<"name"/utf8>>),
                gleam@result:unwrap(_pipe, <<"Unknown"/utf8>>)
            end,
            gleam@result:'try'(
                get_string(Dict, <<"announce"/utf8>>),
                fun(Tracker) ->
                    gleam@result:'try'(
                        get_entries(Dict, <<"info"/utf8>>),
                        fun(Info_entries) ->
                            Info_dict = maps:from_list(Info_entries),
                            Length = begin
                                _pipe@1 = get_int(Info_dict, <<"length"/utf8>>),
                                gleam@result:unwrap(_pipe@1, 0)
                            end,
                            gleam@result:'try'(
                                get_int(Info_dict, <<"piece length"/utf8>>),
                                fun(Piece_length) ->
                                    gleam@result:'try'(
                                        get_string_bits(
                                            Info_dict,
                                            <<"pieces"/utf8>>
                                        ),
                                        fun(Pieces) ->
                                            Piece_hashes = split_piece_hashes(
                                                Pieces,
                                                []
                                            ),
                                            {ok,
                                                {torrent,
                                                    Name,
                                                    Tracker,
                                                    Length,
                                                    Piece_length,
                                                    Piece_hashes,
                                                    digest_entries(Info_entries)}}
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

-file("src/bencode.gleam", 319).
-spec describe_error(decode_error()) -> binary().
describe_error(Error) ->
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

        {missing_key, Key} ->
            <<"Missing Key: "/utf8, Key/binary>>;

        {invalid_torrent, Err} ->
            Err
    end.
