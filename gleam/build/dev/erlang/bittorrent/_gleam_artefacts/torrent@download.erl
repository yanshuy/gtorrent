-module(torrent@download).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/torrent/download.gleam").
-export([is_bit_set/2, describe_error/1, connect_with_peers/4, download_torrent/4, download_piece/5]).
-export_type([torrent_state/0, torrent_error/0]).

-type torrent_state() :: {torrent_state,
        torrent@torrent:torrent_info(),
        list(torrent@torrent:piece_info()),
        list(torrent@torrent:piece_info()),
        gleam@dict:dict(torrent@peer@protocol:peer_id(), gleam@erlang@process:subject(torrent@torrent:piece_info()))}.

-type torrent_error() :: no_peer_responding |
    {protocol_error, torrent@peer@protocol:protocol_error()} |
    {peer_error, torrent@peer@session:peer_error()} |
    {file_error, simplifile:file_error()}.

-file("src/torrent/download.gleam", 42).
-spec new_download(torrent@torrent:torrent_info()) -> torrent_state().
new_download(Torrent) ->
    Pieces = torrent@torrent:new_pieces(
        erlang:element(4, Torrent),
        erlang:element(5, Torrent),
        erlang:element(6, Torrent)
    ),
    {torrent_state, Torrent, Pieces, [], maps:new()}.

-file("src/torrent/download.gleam", 249).
-spec verify_piece(bitstring(), bitstring()) -> boolean().
verify_piece(Binary, Hash) ->
    Calc = gleam@crypto:hash(sha1, Binary),
    Calc =:= Hash.

-file("src/torrent/download.gleam", 220).
-spec is_bit_set(bitstring(), integer()) -> boolean().
is_bit_set(Bits, Index) ->
    case Bits of
        <<_:Index, Target:1, _/bitstring>> ->
            Target =:= 1;

        _ ->
            false
    end.

-file("src/torrent/download.gleam", 204).
-spec lease_piece(torrent_state(), bitstring()) -> {ok,
        torrent@torrent:piece_info()} |
    {error, nil}.
lease_piece(State, Bitfield) ->
    _pipe = erlang:element(3, State),
    gleam@list:find(
        _pipe,
        fun(Piece) -> is_bit_set(Bitfield, erlang:element(2, Piece)) end
    ).

-file("src/torrent/download.gleam", 67).
-spec handle_download(
    file_io:writer(),
    torrent_state(),
    gleam@erlang@process:subject(torrent@messages:peer_event())
) -> {ok, nil} | {error, torrent_error()}.
handle_download(Writer, State, Mailbox) ->
    gleam@bool:guard(
        begin
            _pipe = erlang:element(3, State),
            gleam@list:is_empty(_pipe)
        end
        andalso begin
            _pipe@1 = erlang:element(4, State),
            gleam@list:is_empty(_pipe@1)
        end,
        {ok, nil},
        fun() -> case gleam@erlang@process:'receive'(Mailbox, 10000) of
                {ok, Event} ->
                    case Event of
                        {ready, Peer_id, Subject} ->
                            Peers = gleam@dict:insert(
                                erlang:element(5, State),
                                Peer_id,
                                Subject
                            ),
                            State@1 = {torrent_state,
                                erlang:element(2, State),
                                erlang:element(3, State),
                                erlang:element(4, State),
                                Peers},
                            handle_download(Writer, State@1, Mailbox);

                        {lease_piece, Peer_id@1, Bitfield} ->
                            Subject@2 = case gleam_stdlib:map_get(
                                erlang:element(5, State),
                                Peer_id@1
                            ) of
                                {ok, Subject@1} -> Subject@1;
                                _assert_fail ->
                                    erlang:error(#{gleam_error => let_assert,
                                                message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                                                file => <<?FILEPATH/utf8>>,
                                                module => <<"torrent/download"/utf8>>,
                                                function => <<"handle_download"/utf8>>,
                                                line => 87,
                                                value => _assert_fail,
                                                start => 2378,
                                                'end' => 2433,
                                                pattern_start => 2389,
                                                pattern_end => 2400})
                            end,
                            case lease_piece(State, Bitfield) of
                                {ok, Piece} ->
                                    gleam@erlang@process:send(Subject@2, Piece),
                                    Pendings = begin
                                        _pipe@2 = erlang:element(3, State),
                                        gleam@list:filter(
                                            _pipe@2,
                                            fun(Pending) ->
                                                erlang:element(2, Pending) /= erlang:element(
                                                    2,
                                                    Piece
                                                )
                                            end
                                        )
                                    end,
                                    State@2 = {torrent_state,
                                        erlang:element(2, State),
                                        Pendings,
                                        erlang:element(4, State),
                                        erlang:element(5, State)},
                                    Leased = [Piece |
                                        erlang:element(4, State@2)],
                                    State@3 = {torrent_state,
                                        erlang:element(2, State@2),
                                        erlang:element(3, State@2),
                                        Leased,
                                        erlang:element(5, State@2)},
                                    handle_download(Writer, State@3, Mailbox);

                                {error, _} ->
                                    handle_download(Writer, State, Mailbox)
                            end;

                        {piece_completed, Peer_id@2, Index, Data} ->
                            gleam_stdlib:println(
                                <<"[COMPLETE EVENT] index="/utf8,
                                    (erlang:integer_to_binary(Index))/binary>>
                            ),
                            Leased@2 = case begin
                                _pipe@3 = erlang:element(4, State),
                                gleam@list:find(
                                    _pipe@3,
                                    fun(Piece@1) ->
                                        erlang:element(2, Piece@1) =:= Index
                                    end
                                )
                            end of
                                {ok, Leased@1} -> Leased@1;
                                _assert_fail@1 ->
                                    erlang:error(#{gleam_error => let_assert,
                                                message => <<"Pattern match failed, no pattern matched the value."/utf8>>,
                                                file => <<?FILEPATH/utf8>>,
                                                module => <<"torrent/download"/utf8>>,
                                                function => <<"handle_download"/utf8>>,
                                                line => 110,
                                                value => _assert_fail@1,
                                                start => 3188,
                                                'end' => 3292,
                                                pattern_start => 3199,
                                                pattern_end => 3209})
                            end,
                            New_leased = begin
                                _pipe@4 = erlang:element(4, State),
                                gleam@list:filter(
                                    _pipe@4,
                                    fun(Piece@2) ->
                                        erlang:element(2, Piece@2) /= Index
                                    end
                                )
                            end,
                            case verify_piece(Data, erlang:element(3, Leased@2)) of
                                true ->
                                    proc_lib:spawn_link(
                                        fun() ->
                                            Offset = Index * erlang:element(
                                                5,
                                                erlang:element(2, State)
                                            ),
                                            Res = (erlang:element(3, Writer))(
                                                Writer,
                                                Offset,
                                                Data
                                            ),
                                            case Res of
                                                {ok, _} ->
                                                    nil;

                                                {error, _} ->
                                                    erlang:error(
                                                        #{gleam_error => panic,
                                                            message => <<"write failed"/utf8>>,
                                                            file => <<?FILEPATH/utf8>>,
                                                            module => <<"torrent/download"/utf8>>,
                                                            function => <<"handle_download"/utf8>>,
                                                            line => 124}
                                                    )
                                            end
                                        end
                                    ),
                                    New_state = {torrent_state,
                                        erlang:element(2, State),
                                        erlang:element(3, State),
                                        New_leased,
                                        erlang:element(5, State)},
                                    handle_download(Writer, New_state, Mailbox);

                                false ->
                                    New_state@1 = {torrent_state,
                                        erlang:element(2, State),
                                        [Leased@2 | erlang:element(3, State)],
                                        New_leased,
                                        erlang:element(5, State)},
                                    handle_download(
                                        Writer,
                                        New_state@1,
                                        Mailbox
                                    )
                            end;

                        {return_piece_lease, Peer_id@3, Piece_index} ->
                            Leased@4 = case begin
                                _pipe@5 = erlang:element(4, State),
                                gleam@list:find(
                                    _pipe@5,
                                    fun(Piece@3) ->
                                        erlang:element(2, Piece@3) =:= Piece_index
                                    end
                                )
                            end of
                                {ok, Leased@3} -> Leased@3;
                                _assert_fail@2 ->
                                    erlang:error(#{gleam_error => let_assert,
                                                message => <<"returned a piece that was never leased"/utf8>>,
                                                file => <<?FILEPATH/utf8>>,
                                                module => <<"torrent/download"/utf8>>,
                                                function => <<"handle_download"/utf8>>,
                                                line => 144,
                                                value => _assert_fail@2,
                                                start => 4342,
                                                'end' => 4464,
                                                pattern_start => 4353,
                                                pattern_end => 4363})
                            end,
                            New_leased@1 = begin
                                _pipe@6 = erlang:element(4, State),
                                gleam@list:filter(
                                    _pipe@6,
                                    fun(Piece@4) ->
                                        erlang:element(2, Piece@4) /= Piece_index
                                    end
                                )
                            end,
                            New_state@2 = {torrent_state,
                                erlang:element(2, State),
                                [Leased@4 | erlang:element(3, State)],
                                New_leased@1,
                                erlang:element(5, State)},
                            handle_download(Writer, New_state@2, Mailbox);

                        {peer_disconnected, Peer_id@4, Reason} ->
                            Id@1 = begin
                                {peer_id, Id} = Peer_id@4,
                                _pipe@7 = Id,
                                gleam_stdlib:base16_encode(_pipe@7)
                            end,
                            gleam_stdlib:print_error(
                                <<<<<<"Stopping peer session with: "/utf8,
                                            Id@1/binary>>/binary,
                                        "\nReason: "/utf8>>/binary,
                                    Reason/binary>>
                            ),
                            Peers@1 = gleam@dict:delete(
                                erlang:element(5, State),
                                Peer_id@4
                            ),
                            New_state@3 = {torrent_state,
                                erlang:element(2, State),
                                erlang:element(3, State),
                                erlang:element(4, State),
                                Peers@1},
                            handle_download(Writer, New_state@3, Mailbox)
                    end;

                {error, _} ->
                    {error, no_peer_responding}
            end end
    ).

-file("src/torrent/download.gleam", 261).
-spec describe_error(torrent_error()) -> binary().
describe_error(Error) ->
    case Error of
        no_peer_responding ->
            <<"Torrent download stalled: No connected peers are currently responding to download requests"/utf8>>;

        {protocol_error, Err} ->
            <<"Torrent protocol error: "/utf8,
                (torrent@peer@protocol:describe_error(Err))/binary>>;

        {peer_error, Err@1} ->
            torrent@peer@session:describe_error(Err@1);

        {file_error, File_err} ->
            <<"Disk I/O error: "/utf8,
                (simplifile:describe_error(File_err))/binary>>
    end.

-file("src/torrent/download.gleam", 180).
-spec connect_with_peers(
    gleam@erlang@process:subject(torrent@messages:peer_event()),
    list(torrent@peer@protocol:endpoint()),
    bitstring(),
    torrent@peer@protocol:peer_id()
) -> nil.
connect_with_peers(Main_subject, Endpoints, Info_hash, Peer_id) ->
    Spawn_worker = fun(Endpoint) ->
        proc_lib:spawn_link(
            fun() ->
                Session = begin
                    _pipe = torrent@peer@session:start_session(
                        Main_subject,
                        Endpoint,
                        Info_hash,
                        Peer_id
                    ),
                    gleam@result:map_error(
                        _pipe,
                        fun(Field@0) -> {peer_error, Field@0} end
                    )
                end,
                case Session of
                    {ok, _} ->
                        nil;

                    {error, Err} ->
                        gleam_stdlib:println(
                            <<<<(erlang:element(2, Endpoint))/binary,
                                    "is malicious"/utf8>>/binary,
                                (describe_error(Err))/binary>>
                        )
                end
            end
        )
    end,
    _pipe@1 = Endpoints,
    _pipe@2 = gleam@list:take(_pipe@1, 6),
    gleam@list:each(_pipe@2, Spawn_worker).

-file("src/torrent/download.gleam", 53).
-spec download_torrent(
    binary(),
    list(torrent@peer@protocol:endpoint()),
    torrent@torrent:torrent_info(),
    torrent@peer@protocol:peer_id()
) -> {ok, nil} | {error, torrent_error()}.
download_torrent(Download_path, Endpoints, Torrent, Peer_id) ->
    Main_subject = gleam@erlang@process:new_subject(),
    Writer = file_io:new_file_writer(Download_path, erlang:element(4, Torrent)),
    connect_with_peers(
        Main_subject,
        Endpoints,
        erlang:element(7, Torrent),
        Peer_id
    ),
    handle_download(Writer, new_download(Torrent), Main_subject).

-file("src/torrent/download.gleam", 227).
-spec download_piece(
    binary(),
    torrent@peer@protocol:endpoint(),
    torrent@torrent:torrent_info(),
    torrent@peer@protocol:peer_id(),
    torrent@torrent:piece_info()
) -> {ok, nil} | {error, torrent_error()}.
download_piece(Download_path, Endpoint, Torrent, Peer_id, Piece) ->
    gleam@result:'try'(
        begin
            _pipe = torrent@peer@protocol:handshake(
                Endpoint,
                erlang:element(7, Torrent),
                Peer_id
            ),
            gleam@result:map_error(
                _pipe,
                fun(Field@0) -> {protocol_error, Field@0} end
            )
        end,
        fun(_use0) ->
            {Socket, Peer_peer_id, _} = _use0,
            gleam@result:'try'(
                begin
                    _pipe@1 = torrent@peer@session:download_piece(
                        Socket,
                        Peer_peer_id,
                        Piece
                    ),
                    gleam@result:map_error(
                        _pipe@1,
                        fun(Field@0) -> {peer_error, Field@0} end
                    )
                end,
                fun(Data) ->
                    Writer = file_io:new_file_writer(
                        Download_path,
                        erlang:element(4, Piece)
                    ),
                    _pipe@2 = (erlang:element(3, Writer))(Writer, 0, Data),
                    gleam@result:replace_error(_pipe@2, {file_error, efault})
                end
            )
        end
    ).
