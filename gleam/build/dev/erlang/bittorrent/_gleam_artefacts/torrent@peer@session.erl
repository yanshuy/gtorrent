-module(torrent@peer@session).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/torrent/peer/session.gleam").
-export([piece_block_requests/1, new_piece_download/1, new_session/2, describe_error/1, is_any_bit_set/1, start_session/4, receive_until/2, wait_unchoke/1, receive_bitfield/1, download_piece/3]).
-export_type([piece_download/0, state/0, peer_session/0, reader_message/0, session_message/0, block_request/0, peer_error/0]).

-type piece_download() :: {piece_download,
        integer(),
        integer(),
        gleam@dict:dict(integer(), bitstring()),
        list(block_request()),
        gleam@dict:dict(integer(), block_request())}.

-type state() :: no_piece | await_lease | {download, piece_download()}.

-type peer_session() :: {peer_session,
        mug:socket(),
        torrent@peer@protocol:peer_id(),
        gleam@option:option(bitstring()),
        gleam@option:option(gleam@dict:dict(binary(), integer())),
        state(),
        boolean(),
        boolean()}.

-type reader_message() :: {message, torrent@peer@protocol:peer_message()} |
    {read_error, peer_error()}.

-type session_message() :: {piece_lease, torrent@torrent:piece_info()} |
    {reader_message, reader_message()}.

-type block_request() :: {block_request, integer(), integer()}.

-type peer_error() :: {peer_error, binary()} |
    {unexpected_message, integer()} |
    {protocol_error, torrent@peer@protocol:protocol_error()} |
    invalid_block |
    duplicate_bitfield.

-file("src/torrent/peer/session.gleam", 491).
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

-file("src/torrent/peer/session.gleam", 485).
-spec piece_block_requests(integer()) -> list(block_request()).
piece_block_requests(Piece_length) ->
    Block_count = case 16384 of
        0 -> 0;
        Gleam@denominator -> ((Piece_length + 16384) - 1) div Gleam@denominator
    end,
    piece_block_requests_loop(Piece_length, Block_count - 1, []).

-file("src/torrent/peer/session.gleam", 27).
-spec new_piece_download(torrent@torrent:piece_info()) -> piece_download().
new_piece_download(Piece) ->
    {piece_download,
        erlang:element(2, Piece),
        erlang:element(4, Piece),
        maps:new(),
        piece_block_requests(erlang:element(4, Piece)),
        maps:new()}.

-file("src/torrent/peer/session.gleam", 55).
-spec new_session(mug:socket(), torrent@peer@protocol:peer_id()) -> peer_session().
new_session(Socket, Peer_id) ->
    {peer_session, Socket, Peer_id, none, none, no_piece, true, false}.

-file("src/torrent/peer/session.gleam", 70).
-spec extended_handshake(mug:socket(), boolean()) -> {ok, nil} |
    {error, peer_error()}.
extended_handshake(Socket, Supported) ->
    case Supported of
        true ->
            _pipe = torrent@peer@protocol:send_extended_handshake(Socket),
            gleam@result:map_error(
                _pipe,
                fun(Field@0) -> {protocol_error, Field@0} end
            );

        false ->
            {ok, nil}
    end.

-file("src/torrent/peer/session.gleam", 515).
-spec describe_error(peer_error()) -> binary().
describe_error(Error) ->
    case Error of
        {peer_error, Reason} ->
            <<"Peer error: "/utf8, Reason/binary>>;

        {unexpected_message, Id} ->
            <<"Unexpected message ID: "/utf8,
                (erlang:integer_to_binary(Id))/binary>>;

        {protocol_error, Protocol_err} ->
            torrent@peer@protocol:describe_error(Protocol_err);

        invalid_block ->
            <<"Received an invalid data block length, offset, or payload"/utf8>>;

        duplicate_bitfield ->
            <<"Protocol violation: peer sent a second bitfield message"/utf8>>
    end.

-file("src/torrent/peer/session.gleam", 170).
-spec disconnect(
    gleam@erlang@process:subject(torrent@messages:peer_event()),
    torrent@peer@protocol:peer_id(),
    peer_error()
) -> nil.
disconnect(Parent_subject, Peer_id, Err) ->
    gleam@erlang@process:send(
        Parent_subject,
        {peer_disconnected, Peer_id, describe_error(Err)}
    ),
    gleam@erlang@process:kill(erlang:self()).

-file("src/torrent/peer/session.gleam", 322).
-spec request_piece_blocks(peer_session(), piece_download()) -> {ok,
        piece_download()} |
    {error, peer_error()}.
request_piece_blocks(Session, Piece) ->
    Take = gleam@int:min(4, 4 - maps:size(erlang:element(6, Piece))),
    Remaining = gleam@list:drop(erlang:element(5, Piece), Take),
    Reqs = begin
        _pipe = erlang:element(5, Piece),
        gleam@list:take(_pipe, Take)
    end,
    gleam@result:'try'(
        gleam@list:try_each(
            Reqs,
            fun(Req) ->
                Id = 6,
                Request_message = <<13:4/big-unit:8,
                    Id/integer,
                    (erlang:element(2, Piece)):4/big-unit:8,
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
                erlang:element(6, Piece),
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
                erlang:element(4, Piece),
                Remaining,
                Outstanding@1},
            {ok, _pipe@2}
        end
    ).

-file("src/torrent/peer/session.gleam", 207).
-spec ask_lease(
    gleam@erlang@process:subject(torrent@messages:peer_event()),
    peer_session()
) -> nil.
ask_lease(Parent_subject, Session) ->
    Bitfield@1 = case erlang:element(4, Session) of
        {some, Bitfield} -> Bitfield;
        _assert_fail ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"idle state before bitfield is set"/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"torrent/peer/session"/utf8>>,
                        function => <<"ask_lease"/utf8>>,
                        line => 211,
                        value => _assert_fail,
                        start => 5295,
                        'end' => 5339,
                        pattern_start => 5306,
                        pattern_end => 5320})
    end,
    gleam@erlang@process:send(
        Parent_subject,
        {lease_piece, erlang:element(3, Session), Bitfield@1}
    ).

-file("src/torrent/peer/session.gleam", 238).
-spec handle_piece_complete(
    gleam@erlang@process:subject(torrent@messages:peer_event()),
    torrent@peer@protocol:peer_id(),
    piece_download()
) -> nil.
handle_piece_complete(Parent_subject, Peer_id, Piece) ->
    Blocks = begin
        _pipe = maps:to_list(erlang:element(4, Piece)),
        _pipe@1 = gleam@list:sort(
            _pipe,
            fun(A, B) ->
                gleam@int:compare(erlang:element(1, A), erlang:element(1, B))
            end
        ),
        gleam@list:map(_pipe@1, fun gleam@pair:second/1)
    end,
    Bin = gleam_stdlib:bit_array_concat(Blocks),
    Message = {piece_completed, Peer_id, erlang:element(2, Piece), Bin},
    gleam@erlang@process:send(Parent_subject, Message).

-file("src/torrent/peer/session.gleam", 216).
-spec notify_or_progress(
    gleam@erlang@process:subject(torrent@messages:peer_event()),
    peer_session(),
    piece_download()
) -> {ok, peer_session()} | {error, peer_error()}.
notify_or_progress(Parent_subject, Session, Piece) ->
    case {gleam@list:is_empty(erlang:element(5, Piece)),
        gleam@dict:is_empty(erlang:element(6, Piece))} of
        {true, true} ->
            handle_piece_complete(
                Parent_subject,
                erlang:element(3, Session),
                Piece
            ),
            ask_lease(Parent_subject, Session),
            _pipe = {peer_session,
                erlang:element(2, Session),
                erlang:element(3, Session),
                erlang:element(4, Session),
                erlang:element(5, Session),
                no_piece,
                erlang:element(7, Session),
                erlang:element(8, Session)},
            {ok, _pipe};

        {true, false} ->
            {ok, Session};

        {false, _} ->
            gleam@result:'try'(
                request_piece_blocks(Session, Piece),
                fun(Piece@1) ->
                    _pipe@1 = {peer_session,
                        erlang:element(2, Session),
                        erlang:element(3, Session),
                        erlang:element(4, Session),
                        erlang:element(5, Session),
                        {download, Piece@1},
                        erlang:element(7, Session),
                        erlang:element(8, Session)},
                    {ok, _pipe@1}
                end
            )
    end.

-file("src/torrent/peer/session.gleam", 397).
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

-file("src/torrent/peer/session.gleam", 302).
-spec send_interested(peer_session()) -> {ok, peer_session()} |
    {error, peer_error()}.
send_interested(Session) ->
    Bitfield@1 = case erlang:element(4, Session) of
        {some, Bitfield} -> Bitfield;
        _assert_fail ->
            erlang:error(#{gleam_error => let_assert,
                        message => <<"Bitfield not set"/utf8>>,
                        file => <<?FILEPATH/utf8>>,
                        module => <<"torrent/peer/session"/utf8>>,
                        function => <<"send_interested"/utf8>>,
                        line => 303,
                        value => _assert_fail,
                        start => 7971,
                        'end' => 8015,
                        pattern_start => 7982,
                        pattern_end => 7996})
    end,
    case is_any_bit_set(Bitfield@1) of
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

-file("src/torrent/peer/session.gleam", 183).
-spec act(
    gleam@erlang@process:subject(torrent@messages:peer_event()),
    peer_session()
) -> {ok, peer_session()} | {error, peer_error()}.
act(Parent_subject, Session) ->
    case Session of
        {peer_session, _, _, none, _, _, _, _} ->
            {ok, Session};

        {peer_session, _, _, _, _, _, _, false} ->
            send_interested(Session);

        {peer_session, _, _, _, _, _, true, _} ->
            {ok, Session};

        {peer_session, _, _, _, _, no_piece, _, _} ->
            ask_lease(Parent_subject, Session),
            _pipe = {peer_session,
                erlang:element(2, Session),
                erlang:element(3, Session),
                erlang:element(4, Session),
                erlang:element(5, Session),
                await_lease,
                erlang:element(7, Session),
                erlang:element(8, Session)},
            {ok, _pipe};

        {peer_session, _, _, _, _, await_lease, _, _} ->
            {ok, Session};

        {peer_session, _, _, _, _, {download, Piece}, _, _} ->
            notify_or_progress(Parent_subject, Session, Piece)
    end.

-file("src/torrent/peer/session.gleam", 359).
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
                        line => 363,
                        value => _assert_fail,
                        start => 9551,
                        'end' => 9609,
                        pattern_start => 9562,
                        pattern_end => 9599})
    end,
    gleam@bool:guard(
        Peer_piece_index@1 /= erlang:element(2, Piece),
        {error, {peer_error, <<"piece index mismatch"/utf8>>}},
        fun() ->
            Outstanding = gleam_stdlib:map_get(
                erlang:element(6, Piece),
                Begin@1
            ),
            case Outstanding of
                {ok, _} ->
                    Rem = erlang:element(3, Piece) - Begin@1,
                    Expected_block_size = case Rem > 16384 of
                        true ->
                            16384;

                        false ->
                            Rem
                    end,
                    Rx_block_size = erlang:byte_size(Block@1),
                    gleam@bool:guard(
                        Rx_block_size /= Expected_block_size,
                        {error, {peer_error, <<"incomplete block"/utf8>>}},
                        fun() ->
                            Outstanding@1 = gleam@dict:delete(
                                erlang:element(6, Piece),
                                Begin@1
                            ),
                            New_blocks = gleam@dict:insert(
                                erlang:element(4, Piece),
                                Begin@1,
                                Block@1
                            ),
                            _pipe = {piece_download,
                                erlang:element(2, Piece),
                                erlang:element(3, Piece),
                                New_blocks,
                                erlang:element(5, Piece),
                                Outstanding@1},
                            {ok, _pipe}
                        end
                    );

                {error, _} ->
                    {ok, Piece}
            end
        end
    ).

-file("src/torrent/peer/session.gleam", 293).
-spec handle_extension_message(
    peer_session(),
    torrent@peer@protocol:extension_message()
) -> peer_session().
handle_extension_message(Session, Message) ->
    case Message of
        {handshake, Extensions} ->
            Extensions@1 = maps:from_list(Extensions),
            {peer_session,
                erlang:element(2, Session),
                erlang:element(3, Session),
                erlang:element(4, Session),
                {some, Extensions@1},
                erlang:element(6, Session),
                erlang:element(7, Session),
                erlang:element(8, Session)}
    end.

-file("src/torrent/peer/session.gleam", 261).
-spec handle_message(peer_session(), torrent@peer@protocol:peer_message()) -> {ok,
        peer_session()} |
    {error, peer_error()}.
handle_message(Session, Message) ->
    case Message of
        choke ->
            _pipe = {peer_session,
                erlang:element(2, Session),
                erlang:element(3, Session),
                erlang:element(4, Session),
                erlang:element(5, Session),
                erlang:element(6, Session),
                true,
                erlang:element(8, Session)},
            {ok, _pipe};

        unchoke ->
            _pipe@1 = {peer_session,
                erlang:element(2, Session),
                erlang:element(3, Session),
                erlang:element(4, Session),
                erlang:element(5, Session),
                erlang:element(6, Session),
                false,
                erlang:element(8, Session)},
            {ok, _pipe@1};

        have ->
            {ok, Session};

        {bit_field, Bitfield} ->
            case erlang:element(4, Session) of
                {some, _} ->
                    {error, duplicate_bitfield};

                none ->
                    _pipe@2 = {peer_session,
                        erlang:element(2, Session),
                        erlang:element(3, Session),
                        {some, Bitfield},
                        erlang:element(5, Session),
                        erlang:element(6, Session),
                        erlang:element(7, Session),
                        erlang:element(8, Session)},
                    {ok, _pipe@2}
            end;

        {extension, Message@1} ->
            _pipe@3 = handle_extension_message(Session, Message@1),
            {ok, _pipe@3};

        {piece, _, _, _} ->
            case erlang:element(6, Session) of
                {download, Piece} ->
                    gleam@result:'try'(
                        handle_piece_block(Message, Piece),
                        fun(Piece@1) ->
                            _pipe@4 = {peer_session,
                                erlang:element(2, Session),
                                erlang:element(3, Session),
                                erlang:element(4, Session),
                                erlang:element(5, Session),
                                {download, Piece@1},
                                erlang:element(7, Session),
                                erlang:element(8, Session)},
                            {ok, _pipe@4}
                        end
                    );

                _ ->
                    {error,
                        {unexpected_message,
                            torrent@peer@protocol:message_id(Message)}}
            end;

        _ ->
            {error,
                {unexpected_message, torrent@peer@protocol:message_id(Message)}}
    end.

-file("src/torrent/peer/session.gleam", 123).
-spec run(
    gleam@erlang@process:subject(torrent@messages:peer_event()),
    gleam@erlang@process:subject(reader_message()),
    peer_session()
) -> peer_error().
run(Parent_subject, Message_subject, Session) ->
    Piece_subject = gleam@erlang@process:new_subject(),
    Selector = begin
        _pipe = gleam_erlang_ffi:new_selector(),
        _pipe@1 = gleam@erlang@process:select_map(
            _pipe,
            Piece_subject,
            fun(Field@0) -> {piece_lease, Field@0} end
        ),
        gleam@erlang@process:select_map(
            _pipe@1,
            Message_subject,
            fun(Field@0) -> {reader_message, Field@0} end
        )
    end,
    case gleam_erlang_ffi:select(Selector, 10000) of
        {ok, Event} ->
            case Event of
                {piece_lease, Info} ->
                    Piece = new_piece_download(Info),
                    New_session = {peer_session,
                        erlang:element(2, Session),
                        erlang:element(3, Session),
                        erlang:element(4, Session),
                        erlang:element(5, Session),
                        {download, Piece},
                        erlang:element(7, Session),
                        erlang:element(8, Session)},
                    run(Parent_subject, Message_subject, New_session);

                {reader_message, {message, Message}} ->
                    Result = begin
                        gleam@result:'try'(
                            handle_message(Session, Message),
                            fun(Session@1) ->
                                _ = case Message of
                                    {bit_field, _} ->
                                        gleam@erlang@process:send(
                                            Parent_subject,
                                            {ready,
                                                erlang:element(3, Session@1),
                                                Piece_subject}
                                        );

                                    _ ->
                                        nil
                                end,
                                act(Parent_subject, Session@1)
                            end
                        )
                    end,
                    case Result of
                        {ok, Session@2} ->
                            run(Parent_subject, Message_subject, Session@2);

                        {error, Err} ->
                            Err
                    end;

                {reader_message, {read_error, Err@1}} ->
                    Err@1
            end;

        {error, _} ->
            {peer_error, <<"taking too long"/utf8>>}
    end.

-file("src/torrent/peer/session.gleam", 107).
-spec peer_reader(gleam@erlang@process:subject(reader_message()), mug:socket()) -> nil.
peer_reader(Message_subject, Socket) ->
    Result = begin
        _pipe = torrent@peer@protocol:receive_message(Socket),
        gleam@result:map_error(
            _pipe,
            fun(Field@0) -> {protocol_error, Field@0} end
        )
    end,
    case Result of
        {ok, Message} ->
            gleam@erlang@process:send(Message_subject, {message, Message}),
            peer_reader(Message_subject, Socket);

        {error, Err} ->
            gleam@erlang@process:send(Message_subject, {read_error, Err})
    end.

-file("src/torrent/peer/session.gleam", 79).
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
            {Socket, Peer_peer_id, Extension_supported} = _use0,
            Session = new_session(Socket, Peer_peer_id),
            gleam@result:'try'(
                extended_handshake(
                    erlang:element(2, Session),
                    Extension_supported
                ),
                fun(_) ->
                    Message_subject = gleam@erlang@process:new_subject(),
                    proc_lib:spawn_link(
                        fun() ->
                            peer_reader(
                                Message_subject,
                                erlang:element(2, Session)
                            )
                        end
                    ),
                    Err = run(Parent_subject, Message_subject, Session),
                    disconnect(Parent_subject, Peer_peer_id, Err),
                    {ok, nil}
                end
            )
        end
    ).

-file("src/torrent/peer/session.gleam", 448).
-spec receive_all_blocks(peer_session(), piece_download()) -> {ok,
        piece_download()} |
    {error, peer_error()}.
receive_all_blocks(Session, Piece) ->
    case {gleam@list:is_empty(erlang:element(5, Piece)),
        gleam@dict:is_empty(erlang:element(6, Piece))} of
        {true, true} ->
            {ok, Piece};

        {_, _} ->
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
                        {piece, _, _, _} ->
                            gleam@result:'try'(
                                handle_piece_block(Message, Piece),
                                fun(Piece@1) ->
                                    receive_all_blocks(Session, Piece@1)
                                end
                            );

                        _ ->
                            receive_all_blocks(Session, Piece)
                    end end
            )
    end.

-file("src/torrent/peer/session.gleam", 472).
-spec receive_until(
    mug:socket(),
    fun((torrent@peer@protocol:peer_message()) -> {ok, BBG} | {error, nil})
) -> {ok, BBG} | {error, peer_error()}.
receive_until(Socket, Done) ->
    gleam@result:'try'(
        begin
            _pipe = torrent@peer@protocol:receive_message(Socket),
            gleam@result:map_error(
                _pipe,
                fun(Field@0) -> {protocol_error, Field@0} end
            )
        end,
        fun(Message) -> case Done(Message) of
                {ok, Result} ->
                    {ok, Result};

                {error, _} ->
                    receive_until(Socket, Done)
            end end
    ).

-file("src/torrent/peer/session.gleam", 439).
-spec wait_unchoke(peer_session()) -> {ok, peer_session()} |
    {error, peer_error()}.
wait_unchoke(Session) ->
    receive_until(erlang:element(2, Session), fun(Message) -> case Message of
                unchoke ->
                    _pipe = {peer_session,
                        erlang:element(2, Session),
                        erlang:element(3, Session),
                        erlang:element(4, Session),
                        erlang:element(5, Session),
                        erlang:element(6, Session),
                        false,
                        erlang:element(8, Session)},
                    {ok, _pipe};

                _ ->
                    {error, nil}
            end end).

-file("src/torrent/peer/session.gleam", 426).
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
                    _pipe@1 = {peer_session,
                        erlang:element(2, Session),
                        erlang:element(3, Session),
                        {some, Bits},
                        erlang:element(5, Session),
                        erlang:element(6, Session),
                        erlang:element(7, Session),
                        erlang:element(8, Session)},
                    {ok, _pipe@1};

                _ ->
                    {error, {peer_error, <<"no bitfield"/utf8>>}}
            end end
    ).

-file("src/torrent/peer/session.gleam", 404).
-spec download_piece(
    mug:socket(),
    torrent@peer@protocol:peer_id(),
    torrent@torrent:piece_info()
) -> {ok, bitstring()} | {error, peer_error()}.
download_piece(Socket, Peer_id, Piece) ->
    Session = new_session(Socket, Peer_id),
    gleam@result:'try'(
        receive_bitfield(Session),
        fun(Session@1) ->
            gleam@result:'try'(
                send_interested(Session@1),
                fun(Session@2) ->
                    gleam@result:'try'(
                        wait_unchoke(Session@2),
                        fun(Session@3) ->
                            Piece@1 = new_piece_download(Piece),
                            gleam@result:'try'(
                                request_piece_blocks(Session@3, Piece@1),
                                fun(Piece@2) ->
                                    gleam@result:'try'(
                                        receive_all_blocks(Session@3, Piece@2),
                                        fun(Piece@3) ->
                                            Blocks = begin
                                                _pipe = maps:to_list(
                                                    erlang:element(4, Piece@3)
                                                ),
                                                _pipe@1 = gleam@list:sort(
                                                    _pipe,
                                                    fun(A, B) ->
                                                        gleam@int:compare(
                                                            erlang:element(1, A),
                                                            erlang:element(1, B)
                                                        )
                                                    end
                                                ),
                                                gleam@list:map(
                                                    _pipe@1,
                                                    fun gleam@pair:second/1
                                                )
                                            end,
                                            _pipe@2 = gleam_stdlib:bit_array_concat(
                                                Blocks
                                            ),
                                            {ok, _pipe@2}
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
