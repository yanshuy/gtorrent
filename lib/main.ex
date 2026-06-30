defmodule CLI do
  @compile {:no_warn_undefined, :bittorrent}
  def main(argv) do
    root = File.cwd!()

    root
    |> Path.join("gleam/build/dev/erlang")
    |> File.ls!()
    |> Enum.each(fn app ->
      path = Path.join([root, "gleam/build/dev/erlang", app, "ebin"])
      :code.add_path(String.to_charlist(path))
    end)

    # IO.inspect(:bittorrent.module_info(:exports), label: "exports")
    :bittorrent.execute(argv)
  end
end
