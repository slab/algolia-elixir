defmodule Algolia.Middleware.Headers do
  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, _opts) do
    env
    |> Tesla.put_headers([
      {"X-Algolia-API-Key", Algolia.api_key()},
      {"X-Algolia-Application-Id", Algolia.application_id()}
    ])
    |> Tesla.run(next)
  end
end
