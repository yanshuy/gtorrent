% thanks https://github.com/Xetera
-module(file_ffi).

-export([open/1, allocate/2, pwrite/3]).

open(Filename) ->
    filelib:ensure_dir(Filename),
    case file:open(Filename, [read, write, binary]) of
        {ok, Device} ->
            {ok, Device};
        {error, Reason} ->
            {error, io_lib:format("~p", [Reason])}
    end.

allocate(File, Length) ->
    case file:allocate(File, 0, Length) of
        ok ->
            {ok, nil};
        {error, Reason} ->
            {error, io_lib:format("~p", [Reason])}
    end.

pwrite(File, Offset, Bytes) ->
    case file:pwrite(File, Offset, Bytes) of
        ok ->
            {ok, nil};
        {error, Reason} ->
            {error, io_lib:format("~p", [Reason])}
    end.
