defmodule Algolia.Middleware.BaseUrl do
  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, opts) do
    hint = env.opts[:subdomain_hint]
    curr_retry = Keyword.get(env.opts, :retry_count, 0)
    application_id = Keyword.fetch!(opts, :application_id)
    host_order = Keyword.fetch!(opts, :host_order)

    host =
      case {hint, curr_retry} do
        {:read, 0} ->
          "#{application_id}-dsn.algolia.net"

        {:write, 0} ->
          "#{application_id}.algolia.net"

        {:insights, _} ->
          "insights.algolia.io"

        _ ->
          idx = Enum.at(host_order, rem(curr_retry - 1, 3))
          "#{application_id}-#{idx}.algolianet.com"
      end

    Tesla.run(%{env | url: "https://#{host}#{env.url}"}, next)
  end
end
