defmodule Algolia.Middleware.Headers do
  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, opts) do
    api_key = Keyword.fetch!(opts, :api_key)
    application_id = Keyword.fetch!(opts, :application_id)

    env
    |> Tesla.put_headers([
      {"X-Algolia-API-Key", api_key},
      {"X-Algolia-Application-Id", application_id}
    ])
    |> Tesla.run(next)
  end
end
