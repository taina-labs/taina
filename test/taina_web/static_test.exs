defmodule TainaWeb.StaticTest do
  use ExUnit.Case, async: true

  import Plug.Test

  @moduletag :tmp_dir

  # Regressão: `assets.deploy` fingerprinta os arquivos de raiz de priv/static
  # e o `~p` do layout emite o nome com hash. O `only` do Plug.Static casa o
  # nome exato, então sem `only_matching` o manifest e os ícones davam 404 no
  # build publicado -- e sem manifest o iOS abre a PWA com a moldura do Safari.
  test "arquivo de raiz fingerprintado é servido (only_matching)", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "manifest.webmanifest"), "{}")
    File.write!(Path.join(dir, "manifest-b63bf65a4613b02eb387404e6e6ffbd3.webmanifest"), "{}")

    opts =
      Plug.Static.init(
        at: "/",
        from: dir,
        only: TainaWeb.static_paths(),
        only_matching: TainaWeb.static_path_prefixes()
      )

    conn = Plug.Static.call(conn(:get, "/manifest-b63bf65a4613b02eb387404e6e6ffbd3.webmanifest"), opts)

    assert conn.status == 200
  end

  test "todo arquivo de raiz de priv/static tem um prefixo em only_matching" do
    root_files =
      "priv/static"
      |> File.ls!()
      # sw.js tem plug próprio no Endpoint (no-cache), não passa pelo Plug.Static.
      |> Enum.reject(&(&1 == "sw.js" or File.dir?(Path.join("priv/static", &1))))

    for file <- root_files do
      assert Enum.any?(TainaWeb.static_path_prefixes(), &String.starts_with?(file, &1)),
             "#{file} is a root static file but no static_path_prefixes entry matches it"
    end
  end
end
