-record(connection_options, {
    host :: binary(),
    port :: integer(),
    timeout :: integer(),
    ip_version_preference :: mug:ip_version_preference()
}).
