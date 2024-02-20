defmodule Algolia.Middleware.BaseUrl do
  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, opts) do
    hint = env.opts[:subdomain_hint]
    curr_retry = env.opts[:curr_retry]
    application_id = Keyword.fetch!(opts, :application_id)

    host =
      case {hint, curr_retry} do
        {:read, 0} ->
          "#{application_id}-dsn.algolia.net"

        {:write, 0} ->
          "#{application_id}.algolia.net"

        {:insights, _} ->
          "insights.algolia.io"

        _ ->
          "#{application_id}-#{curr_retry}.algolianet.com"
      end

    Tesla.run(%{env | url: "https://#{host}#{env.url}"}, next)
  end
end
