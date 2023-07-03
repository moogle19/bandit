defmodule Bandit.MixProject do
  use Mix.Project

  def project do
    [
      app: :bandit,
      version: "1.0.0-pre.10",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_path(Mix.env()),
      dialyzer: dialyzer(),
      name: "Bandit",
      description: "A pure-Elixir HTTP server built for Plug & WebSock apps",
      source_url: "https://github.com/mtrudel/bandit",
      package: [
        files: ["lib", "test", "mix.exs", "README*", "LICENSE*"],
        maintainers: ["Mat Trudel"],
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/mtrudel/bandit"}
      ],
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger], mod: {Bandit.Application, []}]
  end

  defp deps do
    [
      {:thousand_island, "~> 1.0-pre and >= 1.0.0-pre.5"},
      {:plug, "~> 1.14"},
      {:websock, "~> 0.5"},
      {:hpax, "~> 0.1.1"},
      {:telemetry, "~> 0.4 or ~> 1.0"},
      #{:brotli, "~> 0.3.1", optional: true},
      {:brotli, github: "yjh0502/erl-brotli", override: true, optional: true},
      {:req, "~> 0.3", only: [:dev, :test]},
      {:machete, ">= 0.0.0", only: [:dev, :test]},
      {:ex_doc, "~> 0.24", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false},
      {:mix_test_watch, "~> 1.0", only: :dev, runtime: false}
    ]
  end

  defp elixirc_path(:test), do: ["lib/", "test/support"]
  defp elixirc_path(_), do: ["lib/"]

  defp dialyzer do
    [
      plt_core_path: "priv/plts",
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_deps: :apps_direct,
      plt_add_apps: [:ssl, :public_key],
      flags: [
        "-Werror_handling",
        "-Wextra_return",
        "-Wmissing_return",
        "-Wunknown",
        "-Wunmatched_returns",
        "-Wunderspecs"
      ]
    ]
  end

  defp docs do
    [main: "Bandit", logo: "assets/ex_doc_logo.png"]
  end
end
