-record(writer, {
    file :: gleam@option:option(file_io:file()),
    write :: fun((file_io:writer(), integer(), bitstring()) -> {ok, nil} |
        {error, binary()})
}).
