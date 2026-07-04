-record(peer_state, {
    endpoint :: binary(),
    download_path :: binary(),
    choked :: boolean(),
    interested :: boolean(),
    bit_field :: gleam@option:option(bitstring())
}).
