defmodule Bandit.HTTP1.StatusLineTest do
  use ExUnit.Case, async: true

  alias Bandit.HTTP1.Socket

  test "status lines match the dynamically built line for every known status" do
    for version <- [:"HTTP/1.1", :"HTTP/1.0"], status <- 100..599 do
      case (try do
              Plug.Conn.Status.reason_phrase(status)
            rescue
              ArgumentError -> nil
            end) do
        nil ->
          assert_raise ArgumentError, fn -> Socket.status_line(version, status) end

        reason ->
          assert Socket.status_line(version, status) == "#{version} #{status} #{reason}\r\n"
      end
    end
  end

  test "status lines are built correctly for common statuses" do
    assert Socket.status_line(:"HTTP/1.1", 200) == "HTTP/1.1 200 OK\r\n"
    assert Socket.status_line(:"HTTP/1.0", 404) == "HTTP/1.0 404 Not Found\r\n"
  end
end
