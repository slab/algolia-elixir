defmodule Algolia.Middleware.Retry do
  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, _opts) do
    curr_retry = 0

    retry(env, next, curr_retry)
  end

  defp retry(_env, _next, 4) do
    {:error, {"Unable to connect to Algolia", 4}}
  end

  defp retry(env, next, curr_retry) do
    opts = Keyword.put(env.opts || [], :curr_retry, curr_retry)

    with {:error, _} <- Tesla.run(%{env | opts: opts}, next) do
      retry(env, next, curr_retry + 1)
    end
  end
end
