defmodule Bandit.WebSocket.Frame do
  @moduledoc false

  import Record

  alias Bandit.WebSocket.Frame

  defrecord :binary_frame, fin: false, compressed: false, data: <<>>
  defrecord :text_frame, fin: false, compressed: false, data: <<>>
  defrecord :close_frame, code: nil, reason: <<>>
  defrecord :continuation_frame, fin: false, data: <<>>
  defrecord :ping_frame, data: <<>>
  defrecord :pong_frame, data: <<>>

  @typedoc "Indicates an opcode"
  @type opcode ::
          (binary :: 0x2)
          | (connection_close :: 0x8)
          | (continuation :: 0x0)
          | (ping :: 0x9)
          | (pong :: 0xA)
          | (text :: 0x1)

  @typedoc "A WebSocket status code, or none at all"
  @type status_code :: non_neg_integer() | nil

  @type binary_frame ::
          record(:binary_frame, fin: boolean(), compressed: boolean(), data: binary())
  @type text_frame :: record(:text_frame, fin: boolean(), compressed: boolean(), data: binary())
  @type close_frame :: record(:close_frame, code: status_code(), reason: binary())
  @type continuation_frame :: record(:continuation_frame, fin: boolean(), data: binary())
  @type ping_frame :: record(:ping_frame, data: binary())
  @type pong_frame :: record(:ping_frame, data: binary())

  @typedoc "A valid WebSocket frame"
  @type frame ::
          binary_frame()
          | text_frame()
          | close_frame()
          | continuation_frame()
          | ping_frame()
          | pong_frame()

  @spec deserialize(binary(), non_neg_integer()) ::
          {{:ok, frame()}, iodata()}
          | {{:more, binary()}, <<>>}
          | {{:error, term()}, iodata()}
          | nil
  def deserialize(
        <<fin::1, compressed::1, rsv::2, opcode::4, 1::1, 127::7, length::64, mask::32,
          payload::binary-size(length), rest::binary>>,
        max_frame_size
      )
      when max_frame_size == 0 or length <= max_frame_size do
    to_frame(fin, compressed, rsv, opcode, mask, payload, rest)
  end

  def deserialize(
        <<fin::1, compressed::1, rsv::2, opcode::4, 1::1, 126::7, length::16, mask::32,
          payload::binary-size(length), rest::binary>>,
        max_frame_size
      )
      when max_frame_size == 0 or length <= max_frame_size do
    to_frame(fin, compressed, rsv, opcode, mask, payload, rest)
  end

  def deserialize(
        <<fin::1, compressed::1, rsv::2, opcode::4, 1::1, length::7, mask::32,
          payload::binary-size(length), rest::binary>>,
        max_frame_size
      )
      when length <= 125 and (max_frame_size == 0 or length <= max_frame_size) do
    to_frame(fin, compressed, rsv, opcode, mask, payload, rest)
  end

  # nil is used to indicate for Stream.unfold/2 that the frame deserialization is finished
  def deserialize(<<>>, _max_frame_size) do
    nil
  end

  def deserialize(msg, max_frame_size)
      when max_frame_size != 0 and byte_size(msg) > max_frame_size do
    {{:error, :max_frame_size_exceeded}, msg}
  end

  def deserialize(msg, _max_frame_size) do
    {{:more, msg}, <<>>}
  end

  def recv_metrics(frame) do
    case frame do
      continuation_frame(data: data) ->
        [
          recv_continuation_frame_count: 1,
          recv_continuation_frame_bytes: IO.iodata_length(data)
        ]

      text_frame(data: data) ->
        [recv_text_frame_count: 1, recv_text_frame_bytes: IO.iodata_length(data)]

      binary_frame(data: data) ->
        [recv_binary_frame_count: 1, recv_binary_frame_bytes: IO.iodata_length(data)]

      close_frame(reason: reason) ->
        [
          recv_connection_close_frame_count: 1,
          recv_connection_close_frame_bytes: IO.iodata_length(reason)
        ]

      ping_frame(data: data) ->
        [recv_ping_frame_count: 1, recv_ping_frame_bytes: IO.iodata_length(data)]

      pong_frame(data: data) ->
        [recv_pong_frame_count: 1, recv_pong_frame_bytes: IO.iodata_length(data)]
    end
  end

  def send_metrics(%frame_type{} = frame) do
    case frame_type do
      Frame.Continuation ->
        [
          send_continuation_frame_count: 1,
          send_continuation_frame_bytes: IO.iodata_length(frame.data)
        ]

      Frame.Text ->
        [send_text_frame_count: 1, send_text_frame_bytes: IO.iodata_length(frame.data)]

      Frame.Binary ->
        [send_binary_frame_count: 1, send_binary_frame_bytes: IO.iodata_length(frame.data)]

      Frame.ConnectionClose ->
        [
          send_connection_close_frame_count: 1,
          send_connection_close_frame_bytes: IO.iodata_length(frame.reason)
        ]

      Frame.Ping ->
        [send_ping_frame_count: 1, send_ping_frame_bytes: IO.iodata_length(frame.data)]

      Frame.Pong ->
        [send_pong_frame_count: 1, send_pong_frame_bytes: IO.iodata_length(frame.data)]
    end
  end

  defp to_frame(_fin, _compressed, rsv, _opcode, _mask, _payload, rest) when rsv != 0x0 do
    {{:error, "Received unsupported RSV flags #{rsv}"}, rest}
  end

  # Continuation frame
  defp to_frame(_fin, 0x1, 0x0, 0x0, _mask, _payload, rest) do
    {{:error, "Cannot have a compressed continuation frame (RFC7692§6.1)"}, rest}
  end

  defp to_frame(fin, 0x0, 0x0, 0x0, mask, payload, rest) do
    {{:ok, continuation_frame(fin: fin == 0x1, data: mask(payload, mask))}, rest}
  end

  # Text frame
  defp to_frame(fin, compressed, 0x0, 0x1, mask, payload, rest) do
    {{:ok, text_frame(fin: fin == 0x1, compressed: compressed == 0x1, data: mask(payload, mask))},
     rest}
  end

  # Binary frame
  defp to_frame(fin, compressed, 0x0, 0x2, mask, payload, rest) do
    {{:ok,
      binary_frame(fin: fin == 0x1, compressed: compressed == 0x1, data: mask(payload, mask))},
     rest}
  end

  # Close frame
  defp to_frame(0x1, 0x0, 0x0, 0x8, _mask, <<>>, rest) do
    {{:ok, close_frame()}, rest}
  end

  defp to_frame(0x1, 0x0, 0x0, 0x8, mask, <<payload::binary>>, rest) when byte_size(payload) <= 125 do
    payload = mask(payload, mask)

    case payload do
      <<code::16>> ->
        {{:ok, close_frame(code: code)}, rest}

      <<code::16, reason::binary>> ->
        if String.valid?(reason) do
          {{:ok, close_frame(code: code, reason: reason)}, rest}
        else
          {{:error, "Received non UTF-8 connection close frame (RFC6455§5.5.1)"}, rest}
        end

      _ ->
    {{:error, "Invalid connection close payload (RFC6455§5.5)"}, rest}

    end
  end

  defp to_frame(0x1, 0x0, 0x0, 0x8, _mask, _payload, rest) do
    {{:error, "Invalid connection close payload (RFC6455§5.5)"}, rest}
  end

  defp to_frame(0x0, 0x0, 0x0, 0x8, _mask, _payload, rest) do
    {{:error, "Cannot have a fragmented connection close frame (RFC6455§5.5)"}, rest}
  end

  defp to_frame(0x1, 0x1, 0x0, 0x8, _mask, _payload, rest) do
    {{:error, "Cannot have a compressed connection close frame (RFC7692§6.1)"}, rest}
  end

  # Ping
  defp to_frame(0x1, 0x0, 0x0, 0x9, mask, <<data::binary>>, rest) when byte_size(data) <= 125 do
    {{:ok, ping_frame(data: mask(data, mask))}, rest}
  end

  defp to_frame(0x1, 0x0, 0x0, 0x9, _mask, _payload, rest) do
    {{:error, "Invalid ping payload (RFC6455§5.5.2)"}, rest}
  end

  defp to_frame(0x0, 0x0, 0x0, 0x9, _mask, _payload, rest) do
    {{:error, "Cannot have a fragmented ping frame (RFC6455§5.5.2)"}, rest}
  end

  defp to_frame(0x1, 0x1, 0x0, 0x9, _mask, _payload, rest) do
    {{:error, "Cannot have a compressed ping frame (RFC7692§6.1)"}, rest}
  end

  # Pong
  defp to_frame(0x1, 0x0, 0x0, 0xA, mask, <<data::binary>>, rest) when byte_size(data) <= 125 do
    {{:ok, pong_frame(data: mask(data, mask))}, rest}
  end

  defp to_frame(0x1, 0x0, 0x0, 0xA, _mask, _payload, rest) do
    {{:error, "Invalid pong payload (RFC6455§5.5.3)"}, rest}
  end

  defp to_frame(0x0, 0x0, 0x0, 0xA, _mask, _payload, rest) do
    {{:error, "Cannot have a fragmented pong frame (RFC6455§5.5.3)"}, rest}
  end

  defp to_frame(0x1, 0x1, 0x0, 0xA, _mask, _payload, rest) do
    {{:error, "Cannot have a compressed pong frame (RFC7692§6.1)"}, rest}
  end

  defp to_frame(_fin, _compressed, 0x0, opcode, _mask, _payload, rest) do
    {{:error, "unknown opcode #{opcode}"}, rest}
  end

  # defp to_frame(fin, compressed, 0x0, opcode, mask, payload, rest) do
  #   fin = fin == 0x1
  #   compressed = compressed == 0x1
  #   unmasked_payload = mask(payload, mask)

  #   opcode
  #   |> case do
  #     0x0 -> Frame.Continuation.deserialize(fin, compressed, unmasked_payload)
  #     0x1 -> Frame.Text.deserialize(fin, compressed, unmasked_payload)
  #     0x2 -> Frame.Binary.deserialize(fin, compressed, unmasked_payload)
  #     0x8 -> Frame.ConnectionClose.deserialize(fin, compressed, unmasked_payload)
  #     0x9 -> Frame.Ping.deserialize(fin, compressed, unmasked_payload)
  #     0xA -> Frame.Pong.deserialize(fin, compressed, unmasked_payload)
  #     unknown -> {:error, "unknown opcode #{unknown}"}
  #   end
  #   |> case do
  #     {:ok, frame} -> {{:ok, frame}, rest}
  #     {:error, reason} -> {{:error, reason}, rest}
  #   end
  # end

  defprotocol Serializable do
    @moduledoc false

    @spec serialize(any()) :: [{Frame.opcode(), boolean(), boolean(), iodata()}]
    def serialize(frame)
  end

  @spec serialize(frame()) :: iolist()
  def serialize(frame) do
    frame
    |> serialize_frame()
    |> Enum.map(fn {opcode, fin, compressed, payload} ->
      fin = if fin, do: 0x1, else: 0x0
      compressed = if compressed, do: 0x1, else: 0x0
      mask_and_length = payload |> IO.iodata_length() |> mask_and_length()
      [<<fin::1, compressed::1, 0x0::2, opcode::4>>, mask_and_length, payload]
    end)
  end

  defp serialize_frame(binary_frame(fin: fin, compressed: compressed, data: data)),
    do: [{0x2, fin, compressed, data}]

  defp serialize_frame(close_frame(code: nil)), do: [{888, true, false, <<>>}]

  defp serialize_frame(close_frame(code: code, reason: nil)),
    do: [{0x8, true, false, <<code::16>>}]

  defp serialize_frame(close_frame(code: code, reason: reason)),
    do: [{0x8, true, false, [<<code::16>>, reason]}]

  defp serialize_frame(continuation_frame(fin: fin, data: data)), do: [{0x0, fin, false, data}]
  defp serialize_frame(ping_frame(data: data)), do: [{0x9, true, false, data}]
  defp serialize_frame(pong_frame(data: data)), do: [{0xA, true, false, data}]

  defp serialize_frame(text_frame(fin: fin, compressed: compressed, data: data)),
    do: [{0x1, fin, compressed, data}]

  defp mask_and_length(length) when length <= 125, do: <<0::1, length::7>>
  defp mask_and_length(length) when length <= 65_535, do: <<0::1, 126::7, length::16>>
  defp mask_and_length(length), do: <<0::1, 127::7, length::64>>

  # Masking is done @mask_size bits at a time until there is less than that number of bits left.
  # We then go 32 bits at a time until there is less than 32 bits left. We then go 8 bits at
  # a time. This yields some significant perforamnce gains for only marginally more complexity
  @mask_size 512

  # Note that masking is an involution, so we don't need a separate unmask function
  def mask(payload, mask) when bit_size(payload) >= @mask_size do
    payload
    |> do_mask(String.duplicate(<<mask::32>>, div(@mask_size, 32)), [])
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  def mask(payload, mask) do
    payload
    |> do_mask(<<mask::32>>, [])
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  defp do_mask(
         <<h::unquote(@mask_size), rest::binary>>,
         <<int_mask::unquote(@mask_size)>> = mask,
         acc
       ) do
    do_mask(rest, mask, [<<Bitwise.bxor(h, int_mask)::unquote(@mask_size)>> | acc])
  end

  defp do_mask(<<h::32, rest::binary>>, <<int_mask::32, _mask_rest::binary>> = mask, acc) do
    do_mask(rest, mask, [<<Bitwise.bxor(h, int_mask)::32>> | acc])
  end

  defp do_mask(<<h::8, rest::binary>>, <<current::8, mask::24, _mask_rest::binary>>, acc) do
    do_mask(rest, <<mask::24, current::8>>, [<<Bitwise.bxor(h, current)::8>> | acc])
  end

  defp do_mask(<<>>, _mask, acc), do: acc
end
