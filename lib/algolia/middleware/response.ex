defmodule Algolia.Middleware.Response do
  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, _opts) do
    case Tesla.run(env, next) do
      {:ok, %{status: code, body: body}} when code in 200..299 ->
        {:ok, body}

      {:ok, %{status: code, body: body}} ->
        {:error, code, body}

      other ->
        other
    end
  end
end
