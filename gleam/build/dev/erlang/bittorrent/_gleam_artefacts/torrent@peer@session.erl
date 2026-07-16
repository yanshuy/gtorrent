-module(torrent@peer@session).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/torrent/peer/session.gleam").
-export([piece_block_requests/1, new_piece_download/1, new_session/3, describe_error/1, is_any_bit_set/1, start_session/4, download_piece/3]).
-export_type([piece_download/0, state/0, peer_session/0, block_request/0, peer_error/0]).

-type piece_download() :: {piece_download,
        torrent@torrent:piece_info(),
        gleam@dict:dict(integer(), bitstring()),
        list(block_request()),
        gleam@dict:dict(integer(), block_request())}.

-type state() :: bitfield | ext_handshake | idle | {download, piece_download()}.

-type peer_session() :: {peer_session,
        mug:socket(),
        torrent@peer@protocol:peer_id(),
        boolean(),
        state(),
        bitstring(),
        boolean(),
        boolean()}.

-type block_request() :: {block_request, integer(), integer()}.

-type peer_error() :: {peer_error, binary()} |
    {unexpected_message, integer()} |
    {protocol_error, torrent@peer@protocol:protocol_error()} |
    piece_hash_mismatch |
    invalid_block |
    duplicate_bitfield.

-file("src/torrent/peer/session.gleam", 355).
-spec piece_block_requests_loop(integer(), integer(), list(block_request())) -> list(block_request()).
piece_block_requests_loop(Length, Block, Requests) ->
    case Block < 0 of
        false ->
            Begin = Block * 16384,
            Block_length = gleam@int:min(16384, Length - Begin),
            Request = {block_request, Begin, Block_length},
            piece_block_requests_loop(Length, Block - 1, [Request | Requests]);

        true ->
            Requests
    end.

-file("src/torrent/peer/session.gleam", 349).
-spec piece_block_requests(integer()) -> list(block_request()).
piece_block_requests(Piece_length) ->
    Block_count = case 16384 of
        0 -> 0;
        Gleam@denominator -> ((Piece_length + 16384) - 1) div Gleam@denominator
    end,
    piece_block_requests_loop(Piece_length, Block_count - 1, []).

-file("src/torrent/peer/session.gleam", 24).
-spec new_piece_download(torrent@torrent:piece_info()) -> piece_download().
new_piece_download(Piece) ->
    {piece_download,
        Piece,
        maps:new(),
        piece_block_requests(erlang:element(4, Piece)),
        maps:new()}.

-file("src/torrent/peer/session.gleam", 52).
-spec new_session(mug:socket(), torrent@peer@protocol:peer_id(), boolean()) -> peer_session().
new_session(Socket, Peer_id, Extension) ->
    {peer_session, Socket, Peer_id, Extension, bitfield, <<>>, true, false}.

-file("src/torrent/peer/session.gleam", 392).
-spec describe_error(peer_error()) -> binary().
describe_error(Error) ->
    case Error of
        {peer_error, Reason} ->
            <<"Peer connection error: "/utf8, Reason/binary>>;

        {unexpected_message, Id} ->
            <<"Unexpected message ID: "/utf8,
                (erlang:integer_to_binary(Id))/binary>>;

        {protocol_error, Protocol_err} ->
            torrent@peer@protocol:describe_error(Protocol_err);

        piece_hash_mismatch ->
            <<"downloaded piece hash does not match the torrent file info-hash"/utf8>>;

        invalid_block ->
            <<"Received an invalid data block length, offset, or payload"/utf8>>;

        duplicate_bitfield ->
            <<"Protocol violation: peer sent a second bitfield message"/utf8>>
    end.

-file("src/torrent/peer/session.gleam", 334).
-spec verify_piece(bitstring(), bitstring()) -> {ok, nil} |
    {error, peer_error()}.
verify_piece(Binary, Hash) ->
    Calc = gleam@crypto:hash(sha1, Binary),
    case Calc =:= Hash of
        true ->
            {ok, nil};

        false ->
            {error, piece_hash_mismatch}
    end.

-file("src/torrent/peer/session.gleam", 223).
-spec handle_piece_complete(piece_download()) -> {ok, bitstring()} |
    {error, peer_error()}.
handle_piece_complete(Piece) ->
    gleam@result:'try'(
        begin
            _pipe = piece_block_requests(
                erlang:element(4, erlang:element(2, Piece))
            ),
            gleam@list:try_map(
                _pipe,
                fun(Req) ->
                    _pipe@1 = gleam_stdlib:map_get(
                        erlang:element(3, Piece),
                        erlang:element(2, Req)
                    ),
                    gleam@result:replace_error(_pipe@1, invalid_block)
                end
            )
        end,
        fun(Blocks) ->
            Data = gleam_stdlib:bit_array_concat(Blocks),
            gleam@result:'try'(
                verify_piece(Data, erlang:element(3, erlang:element(2, Piece))),
                fun(_) -> {ok, Data} end
            )
        end
    ).

-file("src/torrent/peer/session.gleam", 292).
-spec handle_piece_block(torrent@peer@protocol:peer_message(), piece_download()) -> {ok,
        piece_download()} |
    {error, peer_error()}.
handle_piece_block(Message, Piece) ->
    {Peer_piece_index@1, Begin@1, Block@1} = case Message of
        {piece, Peer_piece_index, Begin, Block} -> {
        Peer_piece_index,
            Begin,
            Block};
        _assert_fail ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"torrent/peer/session"/utf8>>,
                        function => <<"handle_piece_block"/utf8>>,
                        line => 296,
                        value => _assert_fail,
                        start => 7642,
                        'end' => 7700,
                        pattern_start => 7653,
                        pattern_end => 7690})
    end,
    gleam@bool:guard(
        Peer_piece_index@1 /= erlang:element(2, erlang:element(2, Piece)),
        {error, {peer_error, <<"piece index mismatch"/utf8>>}},
        fun() ->
            Outstanding = gleam_stdlib:map_get(
                erlang:element(5, Piece),
                Begin@1
            ),
            case Outstanding of
                {ok, Block_request} ->
                    gleam@bool:guard(
                        Begin@1 /= erlang:element(2, Block_request),
                        {error,
                            {peer_error, <<"piece block offset mismatch"/utf8>>}},
                        fun() ->
                            Rem = erlang:element(4, erlang:element(2, Piece)) - Begin@1,
                            Expected_block_size = case Rem > 16384 of
                                true ->
                                    16384;

                                false ->
                                    Rem
                            end,
                            Rx_block_size = erlang:byte_size(Block@1),
                            gleam@bool:guard(
                                Rx_block_size /= Expected_block_size,
                                {error,
                                    {peer_error, <<"incomplete block"/utf8>>}},
                                fun() ->
                                    Outstanding@1 = gleam@dict:delete(
                                        erlang:element(5, Piece),
                                        Begin@1
                                    ),
                                    New_blocks = gleam@dict:insert(
                                        erlang:element(3, Piece),
                                        Begin@1,
                                        Block@1
                                    ),
                                    _pipe = {piece_download,
                                        erlang:element(2, Piece),
                                        New_blocks,
                                        erlang:element(4, Piece),
                                        Outstanding@1},
                                    {ok, _pipe}
                                end
                            )
                        end
                    );

                {error, _} ->
                    {error, invalid_block}
            end
        end
    ).

-file("src/torrent/peer/session.gleam", 255).
-spec request_piece_blocks(peer_session(), piece_download()) -> {ok,
        piece_download()} |
    {error, peer_error()}.
request_piece_blocks(Session, Piece) ->
    Take = gleam@int:min(4, 4 - maps:size(erlang:element(5, Piece))),
    Remaining = gleam@list:drop(erlang:element(4, Piece), Take),
    Reqs = begin
        _pipe = erlang:element(4, Piece),
        gleam@list:take(_pipe, Take)
    end,
    gleam@result:'try'(
        gleam@list:try_each(
            Reqs,
            fun(Req) ->
                Id = 6,
                Request_message = <<13:4/big-unit:8,
                    Id/integer,
                    (erlang:element(2, erlang:element(2, Piece))):4/big-unit:8,
                    (erlang:element(2, Req)):4/big-unit:8,
                    (erlang:element(3, Req)):4/big-unit:8>>,
                _pipe@1 = torrent@peer@protocol:send_message(
                    erlang:element(2, Session),
                    Request_message
                ),
                gleam@result:map_error(
                    _pipe@1,
                    fun(Field@0) -> {protocol_error, Field@0} end
                )
            end
        ),
        fun(_) ->
            Outstanding@1 = gleam@list:fold(
                Reqs,
                erlang:element(5, Piece),
                fun(Outstanding, Req@1) ->
                    gleam@dict:insert(
                        Outstanding,
                        erlang:element(2, Req@1),
                        Req@1
                    )
                end
            ),
            _pipe@2 = {piece_download,
                erlang:element(2, Piece),
                erlang:element(3, Piece),
                Remaining,
                Outstanding@1},
            {ok, _pipe@2}
        end
    ).

-file("src/torrent/peer/session.gleam", 192).
-spec peer_listen(peer_session(), piece_download()) -> {ok,
        {peer_session(), bitstring()}} |
    {error, peer_error()}.
peer_listen(Session, Piece) ->
    gleam@result:'try'(
        begin
            _pipe = torrent@peer@protocol:receive_message(
                erlang:element(2, Session)
            ),
            gleam@result:map_error(
                _pipe,
                fun(Field@0) -> {protocol_error, Field@0} end
            )
        end,
        fun(Message) -> case Message of
                choke ->
                    request_piece(
                        {peer_session,
                            erlang:element(2, Session),
                            erlang:element(3, Session),
                            erlang:element(4, Session),
                            erlang:element(5, Session),
                            erlang:element(6, Session),
                            true,
                            erlang:element(8, Session)},
                        Piece
                    );

                unchoke ->
                    request_piece(
                        {peer_session,
                            erlang:element(2, Session),
                            erlang:element(3, Session),
                            erlang:element(4, Session),
                            erlang:element(5, Session),
                            erlang:element(6, Session),
                            false,
                            erlang:element(8, Session)},
                        Piece
                    );

                have ->
                    request_piece(Session, Piece);

                {bit_field, _} ->
                    {error, duplicate_bitfield};

                {piece, _, _, _} ->
                    gleam@result:'try'(
                        handle_piece_block(Message, Piece),
                        fun(Piece@1) ->
                            case gleam@list:is_empty(erlang:element(4, Piece@1))
                            andalso gleam@dict:is_empty(
                                erlang:element(5, Piece@1)
                            ) of
                                true ->
                                    gleam@result:'try'(
                                        handle_piece_complete(Piece@1),
                                        fun(Piece@2) ->
                                            _pipe@1 = {Session, Piece@2},
                                            {ok, _pipe@1}
                                        end
                                    );

                                false ->
                                    request_piece(Session, Piece@1)
                            end
                        end
                    );

                Message@1 ->
                    {error,
                        {unexpected_message,
                            torrent@peer@protocol:message_id(Message@1)}}
            end end
    ).

-file("src/torrent/peer/session.gleam", 177).
-spec request_piece(peer_session(), piece_download()) -> {ok,
        {peer_session(), bitstring()}} |
    {error, peer_error()}.
request_piece(Session, Piece) ->
    case Session of
        {peer_session, _, _, _, _, _, false, true} ->
            gleam@result:'try'(
                request_piece_blocks(Session, Piece),
                fun(New_piece) -> peer_listen(Session, New_piece) end
            );

        {peer_session, _, _, _, _, _, _, false} ->
            peer_listen(Session, Piece);

        {peer_session, _, _, _, _, _, true, true} ->
            peer_listen(Session, Piece)
    end.

-file("src/torrent/peer/session.gleam", 136).
-spec handle_piece_download(
    gleam@erlang@process:subject(torrent@messages:peer_event()),
    peer_session(),
    piece_download()
) -> peer_session().
handle_piece_download(Parent_subject, Session, Piece_download) ->
    Result = request_piece(Session, Piece_download),
    case Result of
        {ok, {Session@1, Piece}} ->
            gleam@erlang@process:send(
                Parent_subject,
                {piece_completed,
                    erlang:element(2, erlang:element(2, Piece_download)),
                    Piece}
            ),
            Session@1;

        {error, Err} ->
            gleam@erlang@process:send(
                Parent_subject,
                {peer_disconnected,
                    erlang:element(3, Session),
                    describe_error(Err)}
            ),
            gleam@erlang@process:kill(erlang:self()),
            Session
    end.

-file("src/torrent/peer/session.gleam", 110).
-spec wait_for_lease(
    gleam@erlang@process:subject(torrent@messages:peer_event()),
    peer_session()
) -> piece_download().
wait_for_lease(Parent_subject, Session) ->
    Piece = gleam@erlang@process:call_forever(
        Parent_subject,
        fun(Subject) -> {lease_piece, erlang:element(3, Session), Subject} end
    ),
    new_piece_download(Piece).

-file("src/torrent/peer/session.gleam", 342).
-spec is_any_bit_set(bitstring()) -> boolean().
is_any_bit_set(Bitfield) ->
    case Bitfield of
        <<Byte/integer, Rest/bitstring>> ->
            (Byte /= 0) orelse is_any_bit_set(Rest);

        <<>> ->
            false;

        _ ->
            false
    end.

-file("src/torrent/peer/session.gleam", 237).
-spec handle_bitfield(peer_session(), bitstring()) -> {ok, peer_session()} |
    {error, peer_error()}.
handle_bitfield(Session, Bitfield) ->
    case is_any_bit_set(Bitfield) of
        true ->
            Id = torrent@peer@protocol:message_id(interested),
            Message = <<1:4/big-unit:8, Id/integer>>,
            gleam@result:'try'(
                begin
                    _pipe = torrent@peer@protocol:send_message(
                        erlang:element(2, Session),
                        Message
                    ),
                    gleam@result:map_error(
                        _pipe,
                        fun(Field@0) -> {protocol_error, Field@0} end
                    )
                end,
                fun(_) ->
                    {ok,
                        {peer_session,
                            erlang:element(2, Session),
                            erlang:element(3, Session),
                            erlang:element(4, Session),
                            erlang:element(5, Session),
                            erlang:element(6, Session),
                            erlang:element(7, Session),
                            true}}
                end
            );

        false ->
            {error, {peer_error, <<"peer has nothing"/utf8>>}}
    end.

-file("src/torrent/peer/session.gleam", 161).
-spec receive_bitfield(peer_session()) -> {ok, peer_session()} |
    {error, peer_error()}.
receive_bitfield(Session) ->
    gleam@result:'try'(
        begin
            _pipe = torrent@peer@protocol:receive_message(
                erlang:element(2, Session)
            ),
            gleam@result:map_error(
                _pipe,
                fun(Field@0) -> {protocol_error, Field@0} end
            )
        end,
        fun(Message) -> case Message of
                {bit_field, Bits} ->
                    handle_bitfield(
                        {peer_session,
                            erlang:element(2, Session),
                            erlang:element(3, Session),
                            erlang:element(4, Session),
                            erlang:element(5, Session),
                            Bits,
                            erlang:element(7, Session),
                            erlang:element(8, Session)},
                        Bits
                    );

                _ ->
                    {error, {peer_error, <<"no bitfield"/utf8>>}}
            end end
    ).

-file("src/torrent/peer/session.gleam", 68).
-spec run(
    gleam@erlang@process:subject(torrent@messages:peer_event()),
    peer_session(),
    boolean()
) -> {ok, any()} | {error, peer_error()}.
run(Parent_subject, Session, Need_meta) ->
    case erlang:element(5, Session) of
        bitfield ->
            gleam@result:'try'(
                receive_bitfield(Session),
                fun(Session@1) ->
                    gleam@erlang@process:send(
                        Parent_subject,
                        {ready,
                            erlang:element(3, Session@1),
                            erlang:element(6, Session@1)}
                    ),
                    case Need_meta of
                        true ->
                            Session@2 = {peer_session,
                                erlang:element(2, Session@1),
                                erlang:element(3, Session@1),
                                erlang:element(4, Session@1),
                                ext_handshake,
                                erlang:element(6, Session@1),
                                erlang:element(7, Session@1),
                                erlang:element(8, Session@1)},
                            run(Parent_subject, Session@2, Need_meta);

                        false ->
                            run(
                                Parent_subject,
                                {peer_session,
                                    erlang:element(2, Session@1),
                                    erlang:element(3, Session@1),
                                    erlang:element(4, Session@1),
                                    idle,
                                    erlang:element(6, Session@1),
                                    erlang:element(7, Session@1),
                                    erlang:element(8, Session@1)},
                                Need_meta
                            )
                    end
                end
            );

        ext_handshake ->
            gleam@result:'try'(
                begin
                    _pipe = torrent@peer@protocol:extension_handshake(
                        erlang:element(2, Session)
                    ),
                    gleam@result:map_error(
                        _pipe,
                        fun(Field@0) -> {protocol_error, Field@0} end
                    )
                end,
                fun(_) ->
                    run(
                        Parent_subject,
                        {peer_session,
                            erlang:element(2, Session),
                            erlang:element(3, Session),
                            erlang:element(4, Session),
                            idle,
                            erlang:element(6, Session),
                            erlang:element(7, Session),
                            erlang:element(8, Session)},
                        Need_meta
                    )
                end
            );

        idle ->
            Piece_dwnld = wait_for_lease(Parent_subject, Session),
            Session@3 = {peer_session,
                erlang:element(2, Session),
                erlang:element(3, Session),
                erlang:element(4, Session),
                {download, Piece_dwnld},
                erlang:element(6, Session),
                erlang:element(7, Session),
                erlang:element(8, Session)},
            run(Parent_subject, Session@3, Need_meta);

        {download, Piece} ->
            Session@4 = handle_piece_download(Parent_subject, Session, Piece),
            run(
                Parent_subject,
                {peer_session,
                    erlang:element(2, Session@4),
                    erlang:element(3, Session@4),
                    erlang:element(4, Session@4),
                    idle,
                    erlang:element(6, Session@4),
                    erlang:element(7, Session@4),
                    erlang:element(8, Session@4)},
                Need_meta
            )
    end.

-file("src/torrent/peer/session.gleam", 121).
-spec start_session(
    gleam@erlang@process:subject(torrent@messages:peer_event()),
    torrent@peer@protocol:endpoint(),
    bitstring(),
    torrent@peer@protocol:peer_id()
) -> {ok, nil} | {error, peer_error()}.
start_session(Parent_subject, Endpoint, Info_hash, Peer_id) ->
    gleam@result:'try'(
        begin
            _pipe = torrent@peer@protocol:handshake(
                Endpoint,
                Info_hash,
                Peer_id
            ),
            gleam@result:map_error(
                _pipe,
                fun(Field@0) -> {protocol_error, Field@0} end
            )
        end,
        fun(_use0) ->
            {Socket, Peer_peer_id, Extension} = _use0,
            Session = new_session(Socket, Peer_peer_id, Extension),
            _ = run(Parent_subject, Session, false),
            {ok, nil}
        end
    ).

-file("src/torrent/peer/session.gleam", 371).
-spec download_piece(
    mug:socket(),
    torrent@peer@protocol:peer_id(),
    torrent@torrent:piece_info()
) -> {ok, bitstring()} | {error, peer_error()}.
download_piece(Socket, Peer_id, Piece) ->
    Session = new_session(Socket, Peer_id, false),
    gleam@result:'try'(
        receive_bitfield(Session),
        fun(Session@1) ->
            Piece@1 = new_piece_download(Piece),
            gleam@result:'try'(
                request_piece(Session@1, Piece@1),
                fun(Result) -> _pipe = erlang:element(2, Result),
                    {ok, _pipe} end
            )
        end
    ).
