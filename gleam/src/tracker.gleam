import bencode
import gleam/dict
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/list
import gleam/option
import gleam/result.{map_error, replace_error, try}
import gleam/string
import helpers
import torrent

pub type TrackerError {
  HttpError(httpc.HttpError)
  TorrentError(torrent.TorrentError)
  DecodeError(bencode.DecodeError)
  InvalidUrl
  InvalidResponse(String)
}

pub fn get_peers(
  torrent: bencode.Bencode,
  peer_id: BitArray,
) -> Result(List(String), TrackerError) {
  use dict <- try(torrent.dict(torrent) |> map_error(TorrentError))
  use tracker_url <- try(
    torrent.get_string(dict, "announce") |> map_error(TorrentError),
  )

  use req <- try(request.to(tracker_url) |> replace_error(InvalidUrl))
  let req = request.set_body(req, <<>>)

  use query_string <- try(construct_query_string(dict, peer_id))
  let req = request.Request(..req, query: option.Some(query_string))

  use resp <- try(httpc.send_bits(req) |> map_error(HttpError))
  use resp_bencode <- try(bencode.decode(resp.body) |> map_error(DecodeError))

  use dict <- try(torrent.dict(resp_bencode) |> map_error(TorrentError))
  use peers <- try(
    torrent.get_string_bits(dict, "peers") |> map_error(TorrentError),
  )
  split_peers(peers, [])
  |> replace_error(InvalidResponse("malformed peers list"))
}

fn construct_query_string(
  torrent: dict.Dict(String, bencode.Bencode),
  peer_id: BitArray,
) -> Result(String, TrackerError) {
  use info_entries <- try(
    torrent.get_entries(torrent, "info") |> map_error(TorrentError),
  )
  let info_hash = torrent.digest_entries(info_entries) |> helpers.percent_encode

  let peer_id = peer_id |> helpers.percent_encode

  let info_dict = dict.from_list(info_entries)
  use length <- try(
    torrent.get_int(info_dict, "length") |> map_error(TorrentError),
  )
  let left = length

  Ok(
    [
      "info_hash=" <> info_hash,
      "peer_id=" <> peer_id,
      "port=6881",
      "uploaded=0",
      "downloaded=0",
      "left=" <> int.to_string(left),
      "compact=1",
    ]
    |> string.join("&"),
  )
}

pub fn split_peers(
  peers: BitArray,
  acc: List(String),
) -> Result(List(String), Nil) {
  case peers {
    <<>> -> Ok(list.reverse(acc))
    <<peer:bytes-size(6)-unit(8), rest:bits>> -> {
      let assert <<ip4:bytes-size(4)-unit(8), port:size(16)>> = peer

      let assert <<
        one:unsigned-size(8),
        two:unsigned-size(8),
        three:unsigned-size(8),
        four:unsigned-size(8),
      >> = ip4
      let ip_addr =
        int.to_string(one)
        <> "."
        <> int.to_string(two)
        <> "."
        <> int.to_string(three)
        <> "."
        <> int.to_string(four)

      let end_point = ip_addr <> ":" <> int.to_string(port)
      split_peers(rest, [end_point, ..acc])
    }
    _ -> Error(Nil)
  }
}

pub fn describe_error(error: TrackerError) -> String {
  case error {
    HttpError(err) -> {
      case err {
        httpc.InvalidUtf8Response -> panic as "using utf8 for req/resp"
        httpc.FailedToConnect(ip4, ip6) ->
          "Failed to connect to tracker.\n"
          <> "IPv4: "
          <> describe_connect_error(ip4)
          <> "\nIPv6: "
          <> describe_connect_error(ip6)

        httpc.ResponseTimeout -> "Tracker request timed out"
      }
    }

    TorrentError(err) -> "Response Torrent: " <> torrent.describe_error(err)

    DecodeError(err) -> "Decoding: " <> bencode.describe_error(err)

    InvalidResponse(msg) -> msg

    InvalidUrl -> "Invalid tracker URL"
  }
}

fn describe_connect_error(error: httpc.ConnectError) {
  case error {
    httpc.Posix(code) -> "POSIX error: " <> code

    httpc.TlsAlert(code, detail) ->
      "TLS alert: " <> code <> " (" <> detail <> ")"
  }
}
