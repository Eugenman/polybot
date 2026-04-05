defmodule PolybotWeb.PageController do
  use PolybotWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
