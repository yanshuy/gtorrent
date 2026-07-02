-module(bittorrent_ffi).

-export([start/1]).

start(App) ->
    case application:start(App) of
        ok ->
            {ok, nil};
        {error, {already_started, _TargetApp}} ->
            {ok, nil};
        {error, Reason} ->
            %% Flatten arbitrary reasons to a string so Gleam can read it
            ReasonString = list_to_binary(io_lib:format("~p", [Reason])),
            {error, {start_error, ReasonString}}
    end.
