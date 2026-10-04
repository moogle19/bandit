defmodule Bandit.HTTP1.Handler do
  @moduledoc false
  # An HTTP 1.0 & 1.1 Thousand Island Handler

  use ThousandIsland.Handler

  @impl ThousandIsland.Handler
  def handle_connection(socket, state) do
    state =
      state
      |> Map.put(:conn_data, Bandit.SocketHelpers.conn_data(socket))
      |> Map.put(:http_1_settings, resolve_http_1_settings(state.opts.http_1))

    {:continue, state}
  end

  # Resolve the HTTP/1 options we consult on every request once per connection, rather than
  # walking the options keyword list on every (keepalive) request
  defp resolve_http_1_settings(http_1_opts) do
    %{
      max_request_line_length: Keyword.get(http_1_opts, :max_request_line_length, 10_000),
      max_header_length: Keyword.get(http_1_opts, :max_header_length, 10_000),
      max_header_count: Keyword.get(http_1_opts, :max_header_count, 50),
      max_requests: Keyword.get(http_1_opts, :max_requests, 0),
      clear_process_dict: Keyword.get(http_1_opts, :clear_process_dict, true),
      gc_every_n_keepalive_requests: Keyword.get(http_1_opts, :gc_every_n_keepalive_requests, 5)
    }
  end

  @impl ThousandIsland.Handler
  def handle_data(data, socket, state) do
    settings = state.http_1_settings

    transport = %Bandit.HTTP1.Socket{
      socket: socket,
      buffer: data,
      max_request_line_length: settings.max_request_line_length,
      max_header_length: settings.max_header_length,
      max_header_count: settings.max_header_count,
      close_after_response: request_limit_reached?(state)
    }

    connection_span = ThousandIsland.Socket.telemetry_span(socket)

    case Bandit.Pipeline.run(
           transport,
           state.plug,
           connection_span,
           state.conn_data,
           state.opts
         ) do
      {:ok, transport} -> maybe_keepalive(transport, state)
      {:error, _reason} -> {:close, state}
      {:upgrade, _transport, :websocket, opts} -> do_websocket_upgrade(opts, state)
    end
  end

  defp maybe_keepalive(transport, state) do
    if !transport.close_after_response && transport.keepalive do
      if state.http_1_settings.clear_process_dict, do: clear_process_dict()
      requests_processed = Map.get(state, :requests_processed, 0) + 1
      gc_every_n_requests = state.http_1_settings.gc_every_n_keepalive_requests
      if rem(requests_processed, gc_every_n_requests) == 0, do: :erlang.garbage_collect()

      state = Map.put(state, :requests_processed, requests_processed)

      # We have bytes that we've read but haven't yet processed, tail call handle_data to start
      # reading the next request
      if Bandit.SocketHelpers.iodata_empty?(transport.buffer) do
        {:continue, state}
      else
        handle_data(transport.buffer, transport.socket, state)
      end
    else
      {:close, state}
    end
  end

  defp request_limit_reached?(state) do
    requests_processed = Map.get(state, :requests_processed, 0) + 1
    request_limit = state.http_1_settings.max_requests
    request_limit != 0 && requests_processed >= request_limit
  end

  defp clear_process_dict do
    Process.get_keys()
    |> Enum.each(
      &if &1 not in ~w[$ancestors $initial_call $process_label]a, do: Process.delete(&1)
    )
  end

  defp do_websocket_upgrade(upgrade_opts, state) do
    :erlang.garbage_collect()
    {:switch, Bandit.WebSocket.Handler, Map.put(state, :upgrade_opts, upgrade_opts)}
  end

  def handle_info({:plug_conn, :sent}, {socket, state}), do: {:noreply, {socket, state}}

  def handle_info({:EXIT, _pid, :normal}, {socket, state}), do: {:noreply, {socket, state}}

  def handle_info(msg, {socket, state}) do
    if Keyword.get(state.opts.http_1, :log_unknown_messages, false), do: log_no_handle_info(msg)
    {:noreply, {socket, state}}
  end

  defp log_no_handle_info(msg) do
    # Copied verbatim from lib/elixir/lib/gen_server.ex
    proc =
      case Process.info(self(), :registered_name) do
        {_, []} -> self()
        {_, name} -> name
      end

    :logger.error(
      %{
        label: {GenServer, :no_handle_info},
        report: %{
          module: __MODULE__,
          message: msg,
          name: proc
        }
      },
      %{
        domain: [:otp, :elixir],
        error_logger: %{tag: :error_msg},
        report_cb: &GenServer.format_report/1
      }
    )
  end
end
