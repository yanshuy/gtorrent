{application, app_gleam, [
    {vsn, "1.0.0"},
    {applications, [argv,
                    gleam_crypto,
                    gleam_erlang,
                    gleam_http,
                    gleam_httpc,
                    gleam_json,
                    gleam_stdlib,
                    gleeunit,
                    inets,
                    mug,
                    simplifile]},
    {description, ""},
    {modules, [bittorrent,
               handshake]},
    {registered, []}
]}.
