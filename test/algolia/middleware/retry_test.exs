defmodule Algolia.Middleware.RetryTest do
  use ExUnit.Case, async: true

  setup do
    client =
      Tesla.client(
        [Algolia.Middleware.Retry],
        Tesla.Mock
      )

    {:ok, client: client}
  end

  test "returns response with successful status code", %{client: client} do
    Tesla.Mock.mock(fn
      %{url: "/1/indexes"} ->
        {200, [], "OK"}
    end)

    assert {:ok, %{body: "OK"}} = Tesla.get(client, "/1/indexes", opts: [subdomain_hint: :read])
  end

  test "does not retry 400-level HTTP errors", %{client: client} do
    Tesla.Mock.mock(fn
      %{url: "/1/indexes", opts: [retry_count: 3, subdomain_hint: :read]} ->
        {200, [], "OK"}

      %{url: "/1/indexes"} ->
        {400, [], "you did a bad job"}
    end)

    assert {:ok, %{body: "you did a bad job"}} =
             Tesla.get(client, "/1/indexes", opts: [subdomain_hint: :read])
  end

  test "retries 500-level HTTP errors", %{client: client} do
    Tesla.Mock.mock(fn
      %{url: "/1/indexes", opts: [retry_count: 3, subdomain_hint: :read]} ->
        {200, [], "OK"}

      %{url: "/1/indexes"} ->
        {503, [], "you did a bad job"}
    end)

    assert {:ok, %{body: "OK", opts: [{:retry_count, 3} | _]}} =
             Tesla.get(client, "/1/indexes", opts: [subdomain_hint: :read])
  end

  test "retries 429 rate limit HTTP errors", %{client: client} do
    Tesla.Mock.mock(fn
      %{url: "/1/indexes", opts: [retry_count: 3, subdomain_hint: :read]} ->
        {200, [], "OK"}

      %{url: "/1/indexes"} ->
        {429, [], "you did a bad job"}
    end)

    assert {:ok, %{body: "OK", opts: [{:retry_count, 3} | _]}} =
             Tesla.get(client, "/1/indexes", opts: [subdomain_hint: :read])
  end

  test "retries when request errors", %{client: client} do
    Tesla.Mock.mock(fn
      %{url: "/1/indexes", opts: [retry_count: 3, subdomain_hint: :read]} ->
        {200, [], "OK"}

      %{url: "/1/indexes"} ->
        {:error, :econnrefused}
    end)

    assert {:ok, %{body: "OK", opts: [{:retry_count, 3} | _]}} =
             Tesla.get(client, "/1/indexes", opts: [subdomain_hint: :read])
  end

  test "gives up after 4 attempts", %{client: client} do
    Tesla.Mock.mock(fn
      %{url: "/1/indexes", opts: [retry_count: retry, subdomain_hint: :read]} when retry <= 3 ->
        {:error, :econnrefused}

      %{url: "/1/indexes", opts: [subdomain_hint: :read]} ->
        {:error, :econnrefused}
    end)

    assert {:error, :econnrefused} =
             Tesla.get(client, "/1/indexes", opts: [subdomain_hint: :read])
  end

  test "does more retries for write requests", %{client: client} do
    Tesla.Mock.mock(fn
      %{url: "/1/indexes", opts: [retry_count: 10, subdomain_hint: :write]} ->
        {200, [], "OK"}

      %{url: "/1/indexes"} ->
        {:error, :econnrefused}
    end)

    assert {:ok, %{body: "OK", opts: [{:retry_count, 10} | _]}} =
             Tesla.put(client, "/1/indexes", "", opts: [subdomain_hint: :write])
  end
end
