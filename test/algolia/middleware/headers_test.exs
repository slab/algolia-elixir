defmodule Algolia.Middleware.HeadersTest do
  use ExUnit.Case, async: true

  alias Algolia.Middleware.Headers

  alias Tesla.Env

  test "with no headers to start" do
    assert {:ok, env} = Headers.call(%Env{url: "/foo"}, [], api_key: "abc", application_id: "def")

    assert env.headers == [
             {"X-Algolia-API-Key", "abc"},
             {"X-Algolia-Application-Id", "def"}
           ]
  end

  test "adds to the headers that are already present" do
    assert {:ok, env} =
             Headers.call(%Env{url: "/foo", headers: [{"Content-Type", "application/json"}]}, [],
               api_key: "abc",
               application_id: "def"
             )

    assert env.headers == [
             {"Content-Type", "application/json"},
             {"X-Algolia-API-Key", "abc"},
             {"X-Algolia-Application-Id", "def"}
           ]
  end

  test "raises if :api_key is missing" do
    assert_raise KeyError, fn ->
      Headers.call(%Env{url: "/foo"}, [], application_id: "def")
    end
  end

  test "raises if :application_id is missing" do
    assert_raise KeyError, fn ->
      Headers.call(%Env{url: "/foo"}, [], api_key: "abc")
    end
  end
end
