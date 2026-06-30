-module(bencode).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/bencode.gleam").
-export([decode/1]).

-file("src/bencode.gleam", 4).
-spec decode(bitstring()) -> binary().
decode(Encoded_value) ->
    case Encoded_value of
        <<58, Rest/bitstring>> ->
            case gleam@bit_array:to_string(Rest) of
                {ok, Str} ->
                    Str;

                {error, _} ->
                    <<"Invalid UTF-8 data after colon"/utf8>>
            end;

        <<_, Rest@1/bitstring>> ->
            decode(Rest@1);

        <<_:1, Rest@1/bitstring>> ->
            decode(Rest@1);

        <<>> ->
            gleam_stdlib:println(
                <<"The ':' character is not found in the binary"/utf8>>
            ),
            <<""/utf8>>;

        _ ->
            <<""/utf8>>
    end.
