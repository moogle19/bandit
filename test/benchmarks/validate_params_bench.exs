defmodule ValidateParamsBench do
  @valid_params ~w[server_no_context_takeover client_no_context_takeover server_max_window_bits client_max_window_bits]

  def validate_params_orig(params) do
    no_invalid_params = params |> :proplists.split(@valid_params) |> elem(1) == []
    no_repeat_params = params |> :proplists.get_keys() |> length() == length(params)

    no_invalid_values =
      :proplists.get_value("server_no_context_takeover", params) in [:undefined, true] &&
        :proplists.get_value("client_no_context_takeover", params) in [:undefined, true] &&
        :proplists.get_value("server_max_window_bits", params, 15) in 8..15 &&
        :proplists.get_value("client_max_window_bits", params, 15) in 8..15

    no_invalid_params && no_repeat_params && no_invalid_values
  end

  def validate_params_map_new(params) do
    map = Map.new(params)

    no_invalid_params = Enum.all?(params, fn {k, _v} -> k in @valid_params end)
    no_repeat_params = map_size(map) == length(params)

    no_invalid_values =
      Map.get(map, "server_no_context_takeover", :undefined) in [:undefined, true] &&
        Map.get(map, "client_no_context_takeover", :undefined) in [:undefined, true] &&
        Map.get(map, "server_max_window_bits", 15) in 8..15 &&
        Map.get(map, "client_max_window_bits", 15) in 8..15

    no_invalid_params && no_repeat_params && no_invalid_values
  end

  def validate_params_uniq(params) do
    no_invalid_params = Enum.all?(params, fn {k, _v} -> k in @valid_params end)
    no_repeat_params = params |> Enum.uniq_by(fn {k, _} -> k end) |> length() == length(params)

    no_invalid_values =
      :proplists.get_value("server_no_context_takeover", params) in [:undefined, true] &&
        :proplists.get_value("client_no_context_takeover", params) in [:undefined, true] &&
        :proplists.get_value("server_max_window_bits", params, 15) in 8..15 &&
        :proplists.get_value("client_max_window_bits", params, 15) in 8..15

    no_invalid_params && no_repeat_params && no_invalid_values
  end
end

Benchee.run(
  %{
    "original" => fn ->
      ValidateParamsBench.validate_params_orig([
        {"server_no_context_takeover", true},
        {"client_max_window_bits", 15}
      ])
    end,
    "map_new" => fn ->
      ValidateParamsBench.validate_params_map_new([
        {"server_no_context_takeover", true},
        {"client_max_window_bits", 15}
      ])
    end,
    "uniq_by" => fn ->
      ValidateParamsBench.validate_params_uniq([
        {"server_no_context_takeover", true},
        {"client_max_window_bits", 15}
      ])
    end
  },
  time: 2,
  memory_time: 1
)
