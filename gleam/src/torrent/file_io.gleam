import gleam/result

pub type File

@external(erlang, "file_ffi", "open")
fn open(filename: String) -> Result(File, String)

@external(erlang, "file_ffi", "allocate")
fn allocate(file: File, size: Int) -> Result(Nil, String)

@external(erlang, "file_ffi", "pwrite")
fn pwrite(file: File, offset: Int, data: BitArray) -> Result(Nil, String)

pub type Writer {
  Writer(file: File, write: fn(Int, BitArray) -> Result(Nil, String))
}

pub fn new_file_writer(
  file_path: String,
  file_size: Int,
) -> Result(Writer, String) {
  use file <- result.try(open(file_path))
  use _ <- result.try(allocate(file, file_size))
  Writer(file: file, write: fn(offset, data) { pwrite(file, offset, data) })
  |> Ok
}
