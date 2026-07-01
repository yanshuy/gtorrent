{application, app_gleam, [
    {vsn, "1.0.0"},
    {applications, [argv,
                    gleam_json,
                    gleam_stdlib,
                    gleeunit,
                    simplifile]},
    {description, ""},
    {modules, [bittorrent,
               torrent]},
    {registered, []}
]}.
