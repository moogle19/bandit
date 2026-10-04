defmodule ExtractorTest do
  use ExUnit.Case, async: true

  alias Bandit.Extractor
  alias Bandit.WebSocket.Frame

  defp new(opts \\ []), do: Extractor.new(Frame, Bandit.PrimitiveOps.WebSocket, opts)

  # A masked (with a zero mask) text frame
  defp text_frame(payload) when byte_size(payload) <= 125,
    do: <<0x81, 1::1, byte_size(payload)::7, 0::32, payload::binary>>

  defp text_frame(payload) when byte_size(payload) <= 65_535,
    do: <<0x81, 1::1, 126::7, byte_size(payload)::16, 0::32, payload::binary>>

  defp pop_all(extractor, acc \\ []) do
    case Extractor.pop_frame(extractor) do
      {extractor, :more} -> {extractor, Enum.reverse(acc)}
      {extractor, {:ok, %Frame.Text{data: data}}} -> pop_all(extractor, [data | acc])
    end
  end

  test "extracts several whole frames and keeps a trailing partial frame" do
    big = String.duplicate("a", 1000)
    second = text_frame("second")

    {extractor, frames} =
      new()
      |> Extractor.push_data(text_frame("first") <> text_frame(big) <> binary_part(second, 0, 4))
      |> pop_all()

    assert frames == ["first", big]

    {_extractor, frames} =
      extractor
      |> Extractor.push_data(binary_part(second, 4, byte_size(second) - 4))
      |> pop_all()

    assert frames == ["second"]
  end

  test "extracts frames whose payload spans several pushes, preserving trailing data" do
    big = String.duplicate("b", 1000)
    data = text_frame(big) <> text_frame("next") <> text_frame("last")

    {extractor, frames} = new() |> Extractor.push_data(binary_part(data, 0, 10)) |> pop_all()
    assert frames == []

    {extractor, frames} =
      extractor |> Extractor.push_data(binary_part(data, 10, 500)) |> pop_all()

    assert frames == []

    {_extractor, frames} =
      extractor |> Extractor.push_data(binary_part(data, 510, byte_size(data) - 510)) |> pop_all()

    assert frames == [big, "next", "last"]
  end

  test "extracts frames delivered a byte at a time" do
    data = text_frame("one") <> text_frame(String.duplicate("c", 200))

    {_extractor, frames} =
      for <<byte::binary-size(1) <- data>>, reduce: {new(), []} do
        {extractor, acc} ->
          {extractor, frames} = extractor |> Extractor.push_data(byte) |> pop_all()
          {extractor, acc ++ frames}
      end

    assert frames == ["one", String.duplicate("c", 200)]
  end

  test "enforces max_frame_size" do
    assert {_extractor, {:error, :max_frame_size_exceeded}} =
             new(max_frame_size: 100)
             |> Extractor.push_data(text_frame(String.duplicate("d", 200)))
             |> Extractor.pop_frame()
  end
end
