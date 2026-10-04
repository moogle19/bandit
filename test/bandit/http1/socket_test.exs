defmodule Bandit.HTTP1.SocketTest do
  use ExUnit.Case, async: true

  alias Bandit.HTTP1.Socket

  describe "downcase_header_name/1" do
    test "maps every well-known httph atom to its lowercased name" do
      assert length(Socket.httph_field_atoms()) == 52

      for atom <- Socket.httph_field_atoms() do
        assert Socket.downcase_header_name(atom) == atom |> to_string() |> String.downcase(:ascii)
      end
    end

    test "covers names that decode_packet returns as atoms" do
      for atom <- Socket.httph_field_atoms() do
        for name <- [to_string(atom), atom |> to_string() |> String.downcase(:ascii)] do
          assert {:ok, {:http_header, _, ^atom, _, "x"}, "\r\n"} =
                   :erlang.decode_packet(:httph_bin, name <> ": x\r\n\r\n", [])
        end
      end
    end

    test "lowercases names which are not well-known" do
      assert {:ok, {:http_header, _, "X-Custom-Header", _, "x"}, "\r\n"} =
               :erlang.decode_packet(:httph_bin, "X-Custom-Header: x\r\n\r\n", [])

      assert Socket.downcase_header_name("X-Custom-Header") == "x-custom-header"
    end
  end
end
