{application, app_gleam, [
    {vsn, "1.0.0"},
    {applications, [argv,
                    gleam_json,
                    gleam_stdlib,
                    gleeunit]},
    {description, ""},
    {modules, [app_gleam@@main,
               app_gleam_test,
               bencode,
               bittorrent,
               helpers]},
    {registered, []}
]}.
