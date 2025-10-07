defmodule TainaWeb.Router do
  use TainaWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end
end
