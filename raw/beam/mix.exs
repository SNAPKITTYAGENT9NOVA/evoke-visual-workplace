defmodule Evoke.MixProject do
  use Mix.Project

  def project do
    [
      app: :evoke,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # OTP application entry point: {Evoke.Application, []}.
  # :crypto is required for the WebSocket handshake (SHA-1) and agent ids.
  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {Evoke.Application, []}
    ]
  end

  # Zero external dependencies: the whole mesh is pure OTP/Elixir so
  # `mix test` runs fully offline with no hex packages.
  defp deps do
    []
  end
end
