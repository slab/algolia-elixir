defmodule Algolia.Middleware.BaseUrl do
  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, _opts) do
    hint = env.opts[:subdomain_hint]
    curr_retry = env.opts[:curr_retry]

    host =
      case {hint, curr_retry} do
        {:read, 0} ->
          "#{Algolia.application_id()}-dsn.algolia.net"

        {:write, 0} ->
          "#{Algolia.application_id()}.algolia.net"

        {:insights, _} ->
          "insights.algolia.io"

        _ ->
          "#{Algolia.application_id()}-#{curr_retry}.algolianet.com"
      end

    Tesla.run(%{env | url: "https://#{host}#{env.url}"}, next)
  end
end
