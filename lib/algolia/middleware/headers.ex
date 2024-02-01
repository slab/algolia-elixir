defmodule Algolia.Middleware.Headers do
  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, opts) do
    api_key = Keyword.get_lazy(opts, :api_key, &Algolia.api_key/0)
    application_id = Keyword.get_lazy(opts, :application_id, &Algolia.application_id/0)

    env
    |> Tesla.put_headers([
      {"X-Algolia-API-Key", api_key},
      {"X-Algolia-Application-Id", application_id}
    ])
    |> Tesla.run(next)
  end
end
