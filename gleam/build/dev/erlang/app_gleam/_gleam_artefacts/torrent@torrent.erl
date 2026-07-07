-module(torrent@torrent).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/torrent/torrent.gleam").
-export([info_hash/1, split_piece_hashes/1, parse/1, new_pieces/3, piece_size/3]).
-export_type([torrent_info/0, piece_info/0, torrent/0]).

-type torrent_info() :: {torrent_info,
        binary(),
        binary(),
        integer(),
        integer(),
        list(bitstring()),
        bitstring()}.

-type piece_info() :: {piece_info, integer(), bitstring(), integer()}.

-type torrent() :: {torrent,
        torrent_info(),
        binary(),
        gleam@set:set(torrent@peer@protocol:peer_id()),
        list(piece_info())}.

-file("src/torrent/torrent.gleam", 48).
-spec info_hash(list({binary(), bencode:bencode()})) -> bitstring().
info_hash(Info_entries) ->
    Bits = begin
        _pipe = {b_dict, Info_entries},
        bencode:encode(_pipe)
    end,
    gleam@crypto:hash(sha1, Bits).

-file("src/torrent/torrent.gleam", 59).
-spec split_piece_hashes_loop(bitstring(), list(bitstring())) -> list(bitstring()).
split_piece_hashes_loop(Bits, Acc) ->
    case Bits of
        <<>> ->
            lists:reverse(Acc);

        <<Hash:20/binary, Rest/bitstring>> ->
            split_piece_hashes_loop(Rest, [Hash | Acc]);

        _ ->
            Acc
    end.

-file("src/torrent/torrent.gleam", 55).
-spec split_piece_hashes(bitstring()) -> list(bitstring()).
split_piece_hashes(Bits) ->
    split_piece_hashes_loop(Bits, []).

-file("src/torrent/torrent.gleam", 22).
-spec parse(bencode:bencode()) -> {ok, torrent_info()} |
    {error, bencode:bencode_error()}.
parse(Meta_info) ->
    gleam@result:'try'(
        bencode:dict(Meta_info),
        fun(Dict) ->
            Name = begin
                _pipe = bencode:get_string(Dict, <<"name"/utf8>>),
                gleam@result:unwrap(_pipe, <<"Unknown"/utf8>>)
            end,
            gleam@result:'try'(
                bencode:get_string(Dict, <<"announce"/utf8>>),
                fun(Announce) ->
                    gleam@result:'try'(
                        bencode:get_entries(Dict, <<"info"/utf8>>),
                        fun(Info_entries) ->
                            Info = maps:from_list(Info_entries),
                            Length = begin
                                _pipe@1 = bencode:get_int(
                                    Info,
                                    <<"length"/utf8>>
                                ),
                                gleam@result:unwrap(_pipe@1, 0)
                            end,
                            gleam@result:'try'(
                                bencode:get_int(Info, <<"piece length"/utf8>>),
                                fun(Piece_length) ->
                                    gleam@result:'try'(
                                        bencode:get_string_bits(
                                            Info,
                                            <<"pieces"/utf8>>
                                        ),
                                        fun(Pieces) ->
                                            {ok,
                                                {torrent_info,
                                                    Name,
                                                    Announce,
                                                    Length,
                                                    Piece_length,
                                                    split_piece_hashes(Pieces),
                                                    info_hash(Info_entries)}}
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

-file("src/torrent/torrent.gleam", 111).
-spec new_pieces_loop(
    list(bitstring()),
    integer(),
    integer(),
    integer(),
    list(piece_info())
) -> list(piece_info()).
new_pieces_loop(Hashes, File_length, Piece_length, Index, Acc) ->
    case Hashes of
        [] ->
            Acc;

        [Last_hash] ->
            Length = case case Piece_length of
                0 -> 0;
                Gleam@denominator -> File_length rem Gleam@denominator
            end of
                0 ->
                    Piece_length;

                Rem ->
                    Rem
            end,
            Piece = {piece_info, Index, Last_hash, Length},
            lists:reverse([Piece | Acc]);

        [Hash | Rest] ->
            Piece@1 = {piece_info, Index, Hash, Piece_length},
            new_pieces_loop(
                Rest,
                File_length,
                Piece_length,
                Index + 1,
                [Piece@1 | Acc]
            )
    end.

-file("src/torrent/torrent.gleam", 103).
-spec new_pieces(integer(), integer(), list(bitstring())) -> list(piece_info()).
new_pieces(File_length, Piece_length, Piece_hashes) ->
    new_pieces_loop(Piece_hashes, File_length, Piece_length, 0, []).

-file("src/torrent/torrent.gleam", 137).
-spec piece_size(integer(), integer(), integer()) -> integer().
piece_size(Index, File_length, Piece_length) ->
    Piece_count = case Piece_length of
        0 -> 0;
        Gleam@denominator -> ((File_length + Piece_length) - 1) div Gleam@denominator
    end,
    case (Piece_count - 1) =:= Index of
        true ->
            case case Piece_length of
                0 -> 0;
                Gleam@denominator@1 -> File_length rem Gleam@denominator@1
            end of
                0 ->
                    Piece_length;

                Rem ->
                    Rem
            end;

        false ->
            Piece_length
    end.
