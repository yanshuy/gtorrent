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
import torrent/peer/protocol
import torrent/torrent

pub type TrackerError {
  InvalidUrl
  HttpError(httpc.HttpError)
  DecodeError(bencode.BencodeError)
  InvalidResponse(String)
}

pub fn get_peers(
  torrent: torrent.TorrentInfo,
  peer_id: protocol.PeerId,
) -> Result(List(String), TrackerError) {
  use req <- try(request.to(torrent.announce) |> replace_error(InvalidUrl))
  let req = request.set_body(req, <<>>)

  use query_string <- try(construct_query_string(torrent, peer_id))
  let req = request.Request(..req, query: option.Some(query_string))

  use resp <- try(httpc.send_bits(req) |> map_error(HttpError))
  use resp_bencode <- try(bencode.decode(resp.body) |> map_error(DecodeError))

  use dict <- try(bencode.dict(resp_bencode) |> map_error(DecodeError))
  use peers <- try(bencode.get_value(dict, "peers") |> map_error(DecodeError))

  decode_peers(peers)
}

fn decode_peers(
  peers_value: bencode.Bencode,
) -> Result(List(String), TrackerError) {
  case peers_value {
    bencode.BString(peers) -> {
      split_peers(peers, [])
      |> replace_error(InvalidResponse("malformed compact peers string"))
    }

    bencode.BList(peer_list) -> {
      parse_uncompact_peers(peer_list, [])
      |> replace_error(InvalidResponse("malformed legacy peers list"))
    }

    _ -> Error(InvalidResponse("expected peers to be a string or a list"))
  }
}

fn construct_query_string(
  torrent: torrent.TorrentInfo,
  peer_id: protocol.PeerId,
) -> Result(String, TrackerError) {
  let encoded = torrent.info_hash |> helpers.percent_encode
  let protocol.PeerId(id) = peer_id
  let peer_id = id |> helpers.percent_encode
  let left = torrent.length |> int.to_string

  Ok(
    [
      "info_hash=" <> encoded,
      "peer_id=" <> peer_id,
      "port=6881",
      "uploaded=0",
      "downloaded=0",
      "left=" <> left,
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
    InvalidUrl -> "Invalid tracker URL"
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
    DecodeError(err) -> "Decoding: " <> bencode.describe_error(err)
    InvalidResponse(msg) -> msg
  }
}

fn describe_connect_error(error: httpc.ConnectError) {
  case error {
    httpc.Posix(code) -> "POSIX error: " <> code
    httpc.TlsAlert(code, detail) ->
      "TLS alert: " <> code <> " (" <> detail <> ")"
  }
}

fn parse_uncompact_peers(
  list: List(bencode.Bencode),
  acc: List(String),
) -> Result(List(String), Nil) {
  case list {
    [] -> Ok(list.reverse(acc))
    [head, ..rest] -> {
      case head {
        bencode.BDict(entries) -> {
          let peer_dict = dict.from_list(entries)
          case
            bencode.get_string(peer_dict, "ip"),
            bencode.get_int(peer_dict, "port")
          {
            Ok(ip), Ok(port) -> {
              let end_point = ip <> ":" <> int.to_string(port)
              parse_uncompact_peers(rest, [end_point, ..acc])
            }
            _, _ -> parse_uncompact_peers(rest, acc)
          }
        }
        _ -> parse_uncompact_peers(rest, acc)
      }
    }
  }
}
