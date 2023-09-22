defmodule Bandit.HTTP2.StreamCollection do
  @moduledoc false
  # Represents a collection of HTTP/2 streams, accessible by stream id or pid.
  # Provides the ability to track streams with any identifier, even though it
  # only manages explicit state for existing (current) streams.

  require Integer

  alias Bandit.HTTP2.Stream

  defstruct initial_recv_window_size: 65_535,
            initial_send_window_size: 65_535,
            max_concurrent_streams: :infinity,
            last_local_stream_id: 0,
            last_remote_stream_id: 0,
            stream_count: 0,
            streams: %{}

  @typedoc "A collection of Stream structs, accessible by id or pid"
  @type t :: %__MODULE__{
          initial_recv_window_size: non_neg_integer(),
          initial_send_window_size: non_neg_integer(),
          max_concurrent_streams: non_neg_integer() | :infinity,
          last_remote_stream_id: Stream.stream_id(),
          last_local_stream_id: Stream.stream_id(),
          streams: %{Stream.stream_id() => Stream.t()}
        }

  @spec update_max_concurrent_streams(t(), non_neg_integer()) :: t()
  def update_max_concurrent_streams(collection, max_concurrent_streams) do
    %{collection | max_concurrent_streams: max_concurrent_streams}
  end

  @spec update_initial_send_window_size(t(), non_neg_integer()) :: t()
  def update_initial_send_window_size(%__MODULE__{} = collection, initial_send_window_size) do
    delta = initial_send_window_size - collection.initial_send_window_size

    streams =
      collection.streams
      |> Enum.map(fn
        {id, %Stream{state: state} = stream} when state in [:open, :remote_closed] ->
          {id, %{stream | send_window_size: stream.send_window_size + delta}}

        {id, stream} ->
          {id, stream}
      end)
      |> Map.new()

    %{collection | streams: streams, initial_send_window_size: initial_send_window_size}
  end

  @spec get_stream(t(), Stream.stream_id()) :: {:ok, Stream.t()}
  def get_stream(%__MODULE__{streams: streams} = collection, stream_id) do
    case Map.get(streams, stream_id) do
      %Stream{} = stream ->
        {:ok, stream}

      nil ->
        state =
          if (Integer.is_even(stream_id) && stream_id <= collection.last_local_stream_id) ||
               (Integer.is_odd(stream_id) && stream_id <= collection.last_remote_stream_id) do
            :closed
          else
            :idle
          end

        {:ok,
         %Stream{
           stream_id: stream_id,
           state: state,
           recv_window_size: collection.initial_recv_window_size,
           send_window_size: collection.initial_send_window_size
         }}
    end
  end

  @spec get_active_stream_by_pid(t(), pid()) :: {:ok, Stream.t()} | {:error, :no_stream}
  def get_active_stream_by_pid(%__MODULE__{streams: streams}, pid) do
    case Enum.find(streams, fn {_stream_id, stream} -> stream.pid == pid end) do
      {_, %Stream{} = stream} -> {:ok, stream}
      nil -> {:error, :no_stream}
    end
  end

  @spec put_stream(t(), Stream.t()) :: {:ok, t()} | {:error, :invalid_stream}
  def put_stream(%__MODULE__{} = collection, %Stream{state: state} = stream)
      when state in [:idle, :closed] do
    case stream.pid do
      nil -> {:ok, %{collection | streams: Map.delete(collection.streams, stream.stream_id)}}
      _pid -> {:error, :invalid_stream}
    end
  end

  def put_stream(%__MODULE__{streams: streams} = collection, %Stream{} = stream) do
    case stream.pid do
      nil ->
        {:error, :invalid_stream}

      _pid ->
        new_stream_count =
          if Map.has_key?(streams, stream.stream_id),
            do: collection.stream_count,
            else: collection.stream_count + 1

        streams = Map.put(streams, stream.stream_id, stream)

        last_local_stream_id =
          if Integer.is_even(stream.stream_id) do
            max(stream.stream_id, collection.last_local_stream_id)
          else
            collection.last_local_stream_id
          end

        last_remote_stream_id =
          if Integer.is_odd(stream.stream_id) do
            max(stream.stream_id, collection.last_remote_stream_id)
          else
            collection.last_remote_stream_id
          end

        {:ok,
         %{
           collection
           | streams: streams,
             stream_count: new_stream_count,
             last_remote_stream_id: last_remote_stream_id,
             last_local_stream_id: last_local_stream_id
         }}
    end
  end

  @dialyzer {:nowarn_function, next_local_stream_id: 1}
  @spec next_local_stream_id(t()) :: Stream.stream_id()
  def next_local_stream_id(%__MODULE__{last_local_stream_id: id}), do: id + 2

  @spec last_remote_stream_id(t()) :: Stream.stream_id()
  def last_remote_stream_id(%__MODULE__{last_remote_stream_id: id}), do: id

  @spec stream_count(t()) :: non_neg_integer()
  def stream_count(%__MODULE__{stream_count: stream_count}), do: stream_count
end
