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
      %{url: "/1/indexes", opts: [curr_retry: 0]} ->
        {200, [], "OK"}
    end)

    assert {:ok, %{body: "OK"}} = Tesla.get(client, "/1/indexes")
  end

  test "returns response with unsuccessful status code", %{client: client} do
    Tesla.Mock.mock(fn
      %{url: "/1/indexes", opts: [curr_retry: 0]} ->
        {500, [], "you did a bad job"}
    end)

    assert {:ok, %{body: "you did a bad job"}} = Tesla.get(client, "/1/indexes")
  end

  test "retries when request errors", %{client: client} do
    Tesla.Mock.mock(fn
      %{url: "/1/indexes", opts: [curr_retry: 3]} ->
        {200, [], "OK"}

      %{url: "/1/indexes"} ->
        {:error, :econnrefused}
    end)

    assert {:ok, %{body: "OK", opts: [curr_retry: 3]}} = Tesla.get(client, "/1/indexes")
  end

  test "gives up after 4 attempts", %{client: client} do
    Tesla.Mock.mock(fn
      %{url: "/1/indexes", opts: [curr_retry: retry]} when retry <= 3 ->
        {:error, :econnrefused}
    end)

    assert {:error, {"Unable to connect to Algolia", 4}} = Tesla.get(client, "/1/indexes")
  end
end
