defmodule Bandit.Unicode do
  @compile {:inline, valid_utf8?: 1}
  if Code.ensure_loaded?(Bandit.Native) do
    def valid_utf8?(binary), do: Bandit.Native.valid_utf8(binary)
  else
    def valid_utf8?(binary), do: String.valid?(binary)
  end
end
