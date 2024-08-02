defmodule Algolia.Middleware.Retry do
  @behaviour Tesla.Middleware

  @default_opts [
    read: [max_retries: 3],
    write: [max_retries: 10],
    insights: [max_retries: 5]
  ]

  @impl Tesla.Middleware
  def call(env, next, opts) do
    opts = Keyword.merge(@default_opts, opts)

    retry_opts =
      opts
      |> Keyword.fetch!(env.opts[:subdomain_hint])
      |> Keyword.put_new(:should_retry, &should_retry?/1)

    Tesla.Middleware.Retry.call(env, next, retry_opts)
  end

  defp should_retry?({:error, _}), do: true
  defp should_retry?({:ok, %{status: 429}}), do: true
  defp should_retry?({:ok, %{status: status}}) when status > 499, do: true
  defp should_retry?(_), do: false
end
