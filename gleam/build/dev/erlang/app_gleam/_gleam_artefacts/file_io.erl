-module(file_io).
-compile([no_auto_import, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-define(FILEPATH, "src/file_io.gleam").
-export([new_file_writer/2]).
-export_type([file/0, writer/0]).

-type file() :: any().

-type writer() :: {writer,
        gleam@option:option(file()),
        fun((writer(), integer(), bitstring()) -> {ok, nil} | {error, binary()})}.

-file("src/file_io.gleam", 22).
-spec new_file_writer(binary(), integer()) -> writer().
new_file_writer(File_path, File_size) ->
    {writer,
        none,
        fun(Writer, Offset, Data) -> case erlang:element(2, Writer) of
                {some, File} ->
                    file_ffi:pwrite(File, Offset, Data);

                none ->
                    gleam@result:'try'(
                        file_ffi:open(File_path),
                        fun(File@1) ->
                            gleam@result:'try'(
                                file_ffi:allocate(File@1, File_size),
                                fun(_) ->
                                    file_ffi:pwrite(File@1, Offset, Data)
                                end
                            )
                        end
                    )
            end end}.
