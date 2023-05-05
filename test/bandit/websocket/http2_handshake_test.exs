defmodule WebSocketHTTP2HandshakeTest do
  # This is fundamentally a test of the Plug helpers in Bandit.WebSocket.Handshake, so we define
  # a simple Plug that uses these handshakes to upgrade to a no-op WebSock implementation

  use ExUnit.Case, async: true
  use ServerHelpers

  # credo:disable-for-this-file Credo.Check.Design.AliasUsage

  setup :https_server

  defmodule MyNoopWebSock do
    use NoopWebSock
  end

  def call(conn, _opts) do
    case Bandit.WebSocket.Handshake.valid_upgrade?(conn) do
      true ->
        opts = if List.first(conn.path_info) == "compress", do: [compress: true], else: []

        conn
        |> Plug.Conn.upgrade_adapter(:websocket, {MyNoopWebSock, [], opts})

      false ->
        conn
        |> Plug.Conn.send_resp(204, <<>>)
    end
  end

  describe "HTTP/2 handshake" do
    test "accepts well formed requests", context do
      socket = SimpleH2Client.setup_connection(context)

      headers = [
        {":method", "GET"},
        {":path", "/send_big_body"},
        {":scheme", "https"},
        {":authority", "localhost:#{context.port}"},
        {"accept-encoding", "x-gzip"}
      ]

      SimpleH2Client.send_headers(socket, 1, true, headers)
    end
  end
end
