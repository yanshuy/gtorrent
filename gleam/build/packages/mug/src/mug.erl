-module(mug).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/mug.gleam").
-export([describe_error/1, new/2, ip_version_preference/2, timeout/2, connect/1, send_builder/2, send/2, 'receive'/2, receive_exact/3, shutdown/1, receive_next_packet_as_message/1, select_tcp_messages/2]).
-export_type([socket/0, do_not_leak/0, connect_error/0, error/0, connection_options/0, ip_version_preference/0, mode_value/0, active_value/0, gen_tcp_option/0, tcp_message/0]).

-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

-type socket() :: any().

-type do_not_leak() :: any().

-type connect_error() :: {connect_failed_ipv4, error()} |
    {connect_failed_ipv6, error()} |
    {connect_failed_both, error(), error()}.

-type error() :: closed |
    timeout |
    eaddrinuse |
    eaddrnotavail |
    eafnosupport |
    ealready |
    econnaborted |
    econnrefused |
    econnreset |
    edestaddrreq |
    ehostdown |
    ehostunreach |
    einprogress |
    eisconn |
    emsgsize |
    enetdown |
    enetunreach |
    enopkg |
    enoprotoopt |
    enotconn |
    enotty |
    enotsock |
    eproto |
    eprotonosupport |
    eprototype |
    esocktnosupport |
    etimedout |
    ewouldblock |
    exbadport |
    exbadseq |
    nxdomain |
    eacces |
    eagain |
    ebadf |
    ebadmsg |
    ebusy |
    edeadlk |
    edeadlock |
    edquot |
    eexist |
    efault |
    efbig |
    eftype |
    eintr |
    einval |
    eio |
    eisdir |
    eloop |
    emfile |
    emlink |
    emultihop |
    enametoolong |
    enfile |
    enobufs |
    enodev |
    enolck |
    enolink |
    enoent |
    enomem |
    enospc |
    enosr |
    enostr |
    enosys |
    enotblk |
    enotdir |
    enotsup |
    enxio |
    eopnotsupp |
    eoverflow |
    eperm |
    epipe |
    erange |
    erofs |
    espipe |
    esrch |
    estale |
    etxtbsy |
    exdev.

-type connection_options() :: {connection_options,
        binary(),
        integer(),
        integer(),
        ip_version_preference()}.

-type ip_version_preference() :: ipv4_only |
    ipv4_preferred |
    ipv6_only |
    ipv6_preferred.

-type mode_value() :: binary.

-type active_value() :: any().

-type gen_tcp_option() :: inet |
    inet6 |
    {active, active_value()} |
    {mode, mode_value()}.

-type tcp_message() :: {packet, socket(), bitstring()} |
    {socket_closed, socket()} |
    {tcp_error, socket(), error()}.

-file("src/mug.gleam", 191).
?DOC(" Convert an error into a human-readable description\n").
-spec describe_error(error()) -> binary().
describe_error(Error) ->
    case Error of
        closed ->
            <<"Connection closed"/utf8>>;

        timeout ->
            <<"Operation timed out"/utf8>>;

        eaddrinuse ->
            <<"Address already in use"/utf8>>;

        eaddrnotavail ->
            <<"Cannot assign requested address"/utf8>>;

        eafnosupport ->
            <<"Address family not supported"/utf8>>;

        ealready ->
            <<"Operation already in progress"/utf8>>;

        econnaborted ->
            <<"Connection aborted"/utf8>>;

        econnrefused ->
            <<"Connection refused"/utf8>>;

        econnreset ->
            <<"Connection reset by peer"/utf8>>;

        edestaddrreq ->
            <<"Destination address required"/utf8>>;

        ehostdown ->
            <<"Host is down"/utf8>>;

        ehostunreach ->
            <<"No route to host"/utf8>>;

        einprogress ->
            <<"Operation now in progress"/utf8>>;

        eisconn ->
            <<"Socket is already connected"/utf8>>;

        emsgsize ->
            <<"Message too long"/utf8>>;

        enetdown ->
            <<"Network is down"/utf8>>;

        enetunreach ->
            <<"Network is unreachable"/utf8>>;

        enopkg ->
            <<"Package not installed"/utf8>>;

        enoprotoopt ->
            <<"Protocol not available"/utf8>>;

        enotconn ->
            <<"Socket is not connected"/utf8>>;

        enotty ->
            <<"Inappropriate ioctl for device"/utf8>>;

        enotsock ->
            <<"Socket operation on non-socket"/utf8>>;

        eproto ->
            <<"Protocol error"/utf8>>;

        eprotonosupport ->
            <<"Protocol not supported"/utf8>>;

        eprototype ->
            <<"Protocol wrong type for socket"/utf8>>;

        esocktnosupport ->
            <<"Socket type not supported"/utf8>>;

        etimedout ->
            <<"Connection timed out"/utf8>>;

        ewouldblock ->
            <<"Operation would block"/utf8>>;

        exbadport ->
            <<"Bad port number"/utf8>>;

        exbadseq ->
            <<"Bad sequence number"/utf8>>;

        nxdomain ->
            <<"Non-existent domain"/utf8>>;

        eacces ->
            <<"Permission denied"/utf8>>;

        eagain ->
            <<"Resource temporarily unavailable"/utf8>>;

        ebadf ->
            <<"Bad file descriptor"/utf8>>;

        ebadmsg ->
            <<"Bad message"/utf8>>;

        ebusy ->
            <<"Device or resource busy"/utf8>>;

        edeadlk ->
            <<"Resource deadlock avoided"/utf8>>;

        edeadlock ->
            <<"Resource deadlock avoided"/utf8>>;

        edquot ->
            <<"Disk quota exceeded"/utf8>>;

        eexist ->
            <<"File exists"/utf8>>;

        efault ->
            <<"Bad address"/utf8>>;

        efbig ->
            <<"File too large"/utf8>>;

        eftype ->
            <<"Inappropriate file type or format"/utf8>>;

        eintr ->
            <<"Interrupted system call"/utf8>>;

        einval ->
            <<"Invalid argument"/utf8>>;

        eio ->
            <<"Input/output error"/utf8>>;

        eisdir ->
            <<"Is a directory"/utf8>>;

        eloop ->
            <<"Too many levels of symbolic links"/utf8>>;

        emfile ->
            <<"Too many open files"/utf8>>;

        emlink ->
            <<"Too many links"/utf8>>;

        emultihop ->
            <<"Multihop attempted"/utf8>>;

        enametoolong ->
            <<"File name too long"/utf8>>;

        enfile ->
            <<"Too many open files in system"/utf8>>;

        enobufs ->
            <<"No buffer space available"/utf8>>;

        enodev ->
            <<"No such device"/utf8>>;

        enolck ->
            <<"No locks available"/utf8>>;

        enolink ->
            <<"Link has been severed"/utf8>>;

        enoent ->
            <<"No such file or directory"/utf8>>;

        enomem ->
            <<"Out of memory"/utf8>>;

        enospc ->
            <<"No space left on device"/utf8>>;

        enosr ->
            <<"Out of streams resources"/utf8>>;

        enostr ->
            <<"Device not a stream"/utf8>>;

        enosys ->
            <<"Function not implemented"/utf8>>;

        enotblk ->
            <<"Block device required"/utf8>>;

        enotdir ->
            <<"Not a directory"/utf8>>;

        enotsup ->
            <<"Operation not supported"/utf8>>;

        enxio ->
            <<"No such device or address"/utf8>>;

        eopnotsupp ->
            <<"Operation not supported on socket"/utf8>>;

        eoverflow ->
            <<"Value too large for defined data type"/utf8>>;

        eperm ->
            <<"Operation not permitted"/utf8>>;

        epipe ->
            <<"Broken pipe"/utf8>>;

        erange ->
            <<"Result too large"/utf8>>;

        erofs ->
            <<"Read-only file system"/utf8>>;

        espipe ->
            <<"Illegal seek"/utf8>>;

        esrch ->
            <<"No such process"/utf8>>;

        estale ->
            <<"Stale file handle"/utf8>>;

        etxtbsy ->
            <<"Text file busy"/utf8>>;

        exdev ->
            <<"Cross-device link"/utf8>>
    end.

-file("src/mug.gleam", 303).
?DOC(" Create a new set of connection options.\n").
-spec new(binary(), integer()) -> connection_options().
new(Host, Port) ->
    {connection_options, Host, Port, 1000, ipv6_preferred}.

-file("src/mug.gleam", 317).
?DOC(
    " What approach to take selecting between IPv4 and IPv6.\n"
    " See the `IpVersionPreference` type for documentation.\n"
    "\n"
    " The default is `Ipv6Preferred`.\n"
).
-spec ip_version_preference(connection_options(), ip_version_preference()) -> connection_options().
ip_version_preference(Options, Preference) ->
    {connection_options,
        erlang:element(2, Options),
        erlang:element(3, Options),
        erlang:element(4, Options),
        Preference}.

-file("src/mug.gleam", 328).
?DOC(
    " Specify a timeout for the connection to be established, in milliseconds.\n"
    "\n"
    " The default is 1000ms.\n"
).
-spec timeout(connection_options(), integer()) -> connection_options().
timeout(Options, Timeout) ->
    {connection_options,
        erlang:element(2, Options),
        erlang:element(3, Options),
        Timeout,
        erlang:element(5, Options)}.

-file("src/mug.gleam", 367).
?DOC(
    " Establish a TCP connection to the server specified in the connection\n"
    " options.\n"
    "\n"
    " Returns an error if the connection could not be established.\n"
    "\n"
    " The socket is created in passive mode, meaning the the `receive` function is\n"
    " to be called to receive packets from the client. The\n"
    " `receive_next_packet_as_message` function can be used to switch the socket\n"
    " to active mode and receive the next packet as an Erlang message.\n"
).
-spec connect(connection_options()) -> {ok, socket()} | {error, connect_error()}.
connect(Options) ->
    Host = unicode:characters_to_list(erlang:element(2, Options)),
    Connect = fun(Inet) ->
        Gen_options = [Inet, {active, mug_ffi:passive()}, {mode, binary}],
        gen_tcp:connect(
            Host,
            erlang:element(3, Options),
            Gen_options,
            erlang:element(4, Options)
        )
    end,
    case erlang:element(5, Options) of
        ipv4_only ->
            _pipe = Connect(inet),
            case _pipe of
                {ok, X} ->
                    {ok, X};

                {error, Error} ->
                    {error, {connect_failed_ipv4, Error}}
            end;

        ipv6_only ->
            _pipe@1 = Connect(inet6),
            case _pipe@1 of
                {ok, X@1} ->
                    {ok, X@1};

                {error, Error@1} ->
                    {error, {connect_failed_ipv6, Error@1}}
            end;

        ipv4_preferred ->
            case Connect(inet) of
                {ok, Conn} ->
                    {ok, Conn};

                {error, Ipv4} ->
                    case Connect(inet6) of
                        {ok, Conn@1} ->
                            {ok, Conn@1};

                        {error, Ipv6} ->
                            {error, {connect_failed_both, Ipv4, Ipv6}}
                    end
            end;

        ipv6_preferred ->
            case Connect(inet6) of
                {ok, Conn@2} ->
                    {ok, Conn@2};

                {error, Ipv6@1} ->
                    case Connect(inet) of
                        {ok, Conn@3} ->
                            {ok, Conn@3};

                        {error, Ipv4@1} ->
                            {error, {connect_failed_both, Ipv4@1, Ipv6@1}}
                    end
            end
    end.

-file("src/mug.gleam", 446).
?DOC(
    " Send a message to the client, the data in `BytesBuilder`. Using this function\n"
    " is more efficient turning an `BytesBuilder` or a `StringBuilder` into a\n"
    " `BitArray` to use with the `send` function.\n"
).
-spec send_builder(socket(), gleam@bytes_tree:bytes_tree()) -> {ok, nil} |
    {error, error()}.
send_builder(Socket, Packet) ->
    mug_ffi:send(Socket, Packet).

-file("src/mug.gleam", 437).
?DOC(" Send a message to the client.\n").
-spec send(socket(), bitstring()) -> {ok, nil} | {error, error()}.
send(Socket, Message) ->
    mug_ffi:send(Socket, gleam@bytes_tree:from_bit_array(Message)).

-file("src/mug.gleam", 453).
?DOC(
    " Receive a message from the client.\n"
    "\n"
    " Errors if the socket is closed, if the timeout is reached, or if there is\n"
    " some other problem receiving the packet.\n"
).
-spec 'receive'(socket(), integer()) -> {ok, bitstring()} | {error, error()}.
'receive'(Socket, Timeout) ->
    gen_tcp:recv(Socket, 0, Timeout).

-file("src/mug.gleam", 470).
?DOC(
    " Receive the specified number of bytes from the client, unless the socket\n"
    " was closed, from the other side. In that case, the last read may return\n"
    " less bytes.\n"
    " If the specified number of bytes is not available to read from the socket\n"
    " then the function will block until the bytes are available, or until the\n"
    " timeout is reached.\n"
    " This directly calls the underlying Erlang function `gen_tcp:recv/3`.\n"
    "\n"
    " Errors if the socket is closed, if the timeout is reached, or if there is\n"
    " some other problem receiving the packet.\n"
).
-spec receive_exact(socket(), integer(), integer()) -> {ok, bitstring()} |
    {error, error()}.
receive_exact(Socket, Size, Timeout) ->
    gen_tcp:recv(Socket, Size, Timeout).

-file("src/mug.gleam", 489).
?DOC(
    " Close the socket, ensuring that any data buffered in the socket is flushed\n"
    " to the operating system kernel socket first.\n"
).
-spec shutdown(socket()) -> {ok, nil} | {error, error()}.
shutdown(Socket) ->
    mug_ffi:shutdown(Socket).

-file("src/mug.gleam", 502).
?DOC(
    " Switch the socket to active mode, meaning that the next packet received on\n"
    " the socket will be sent as an Erlang message to the socket owner's inbox.\n"
    "\n"
    " This is useful for when you wish to have an OTP actor handle incoming\n"
    " messages as using the `receive` function would result in the actor being\n"
    " blocked and unable to handle other messages while waiting for the next\n"
    " packet.\n"
    "\n"
    " Messages will be send to the process that controls the socket, which is the\n"
    " process that established the socket with the `connect` function.\n"
).
-spec receive_next_packet_as_message(socket()) -> nil.
receive_next_packet_as_message(Socket) ->
    inet:setopts(Socket, [{active, mug_ffi:active_once()}]),
    nil.

-file("src/mug.gleam", 541).
-spec map_tcp_message(fun((tcp_message()) -> HKN)) -> fun((gleam@dynamic:dynamic_()) -> HKN).
map_tcp_message(Mapper) ->
    fun(Message) -> Mapper(mug_ffi:coerce_tcp_message(Message)) end.

-file("src/mug.gleam", 527).
?DOC(
    " Configure a selector to receive messages from TCP sockets.\n"
    "\n"
    " Note this will receive messages from all TCP sockets that the process\n"
    " controls, rather than any specific one. If you wish to only handle messages\n"
    " from one socket then use one process per socket.\n"
).
-spec select_tcp_messages(
    gleam@erlang@process:selector(HKK),
    fun((tcp_message()) -> HKK)
) -> gleam@erlang@process:selector(HKK).
select_tcp_messages(Selector, Mapper) ->
    Tcp = erlang:binary_to_atom(<<"tcp"/utf8>>),
    Closed = erlang:binary_to_atom(<<"tcp_closed"/utf8>>),
    Error = erlang:binary_to_atom(<<"tcp_error"/utf8>>),
    _pipe = Selector,
    _pipe@1 = gleam@erlang@process:select_record(
        _pipe,
        Tcp,
        2,
        map_tcp_message(Mapper)
    ),
    _pipe@2 = gleam@erlang@process:select_record(
        _pipe@1,
        Closed,
        1,
        map_tcp_message(Mapper)
    ),
    gleam@erlang@process:select_record(
        _pipe@2,
        Error,
        2,
        map_tcp_message(Mapper)
    ).
