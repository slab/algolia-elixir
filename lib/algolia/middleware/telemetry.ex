defmodule Algolia.Middleware.Telemetry do
  @behaviour Tesla.Middleware

  @impl Tesla.Middleware
  def call(env, next, _opts) do
    start_metadata = %{
      request: %{method: env.method, path: env.url, opts: env.opts, headers: env.headers},
      subdomain_hint: env.opts[:subdomain_hint]
    }

    :telemetry.span([:algolia, :request], start_metadata, fn ->
      {result, stop_metadata} =
        case Tesla.run(env, next) do
          {:ok, %{status: code} = env} when code in 200..299 ->
            {{:ok, env}, %{success: true, result: env.body, retries: env.opts[:curr_retry]}}

          {:ok, %{status: code} = env} ->
            {{:error, code, env.body},
             %{success: false, error: env.body, retries: env.opts[:curr_retry]}}

          {:error, {error, retries}} ->
            {{:error, error}, %{success: false, error: error, retries: retries}}
        end

      {result, Map.merge(start_metadata, stop_metadata)}
    end)
  end
end
