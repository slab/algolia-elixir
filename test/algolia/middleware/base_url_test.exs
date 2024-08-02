defmodule Algolia.Middleware.BaseUrlTest do
  use ExUnit.Case, async: true

  alias Algolia.Middleware.BaseUrl

  alias Tesla.Env

  @opts [application_id: "application_id", host_order: [3, 1, 2]]

  describe "read requests" do
    test "use dsn subdomain for first request" do
      assert {:ok, env} =
               BaseUrl.call(
                 %Env{url: "/1/indexes", opts: [subdomain_hint: :read, retry_count: 0]},
                 [],
                 @opts
               )

      assert env.url == "https://application_id-dsn.algolia.net/1/indexes"
    end

    test "use numbered subdomain for subsequent requests" do
      assert {:ok, env} =
               BaseUrl.call(
                 %Env{url: "/1/indexes", opts: [subdomain_hint: :read, retry_count: 1]},
                 [],
                 @opts
               )

      assert env.url == "https://application_id-3.algolianet.com/1/indexes"

      assert {:ok, env} =
               BaseUrl.call(
                 %Env{url: "/1/indexes", opts: [subdomain_hint: :read, retry_count: 3]},
                 [],
                 @opts
               )

      assert env.url == "https://application_id-2.algolianet.com/1/indexes"

      assert {:ok, env} =
               BaseUrl.call(
                 %Env{url: "/1/indexes", opts: [subdomain_hint: :read, retry_count: 5]},
                 [],
                 @opts
               )

      assert env.url == "https://application_id-1.algolianet.com/1/indexes"
    end
  end

  describe "write requests" do
    test "use basic subdomain for first request" do
      assert {:ok, env} =
               BaseUrl.call(
                 %Env{url: "/1/indexes/foo/bar", opts: [subdomain_hint: :write, retry_count: 0]},
                 [],
                 @opts
               )

      assert env.url == "https://application_id.algolia.net/1/indexes/foo/bar"
    end

    test "use numbered subdomain for subsequent requests" do
      assert {:ok, env} =
               BaseUrl.call(
                 %Env{url: "/1/indexes/foo/bar", opts: [subdomain_hint: :write, retry_count: 1]},
                 [],
                 @opts
               )

      assert env.url == "https://application_id-3.algolianet.com/1/indexes/foo/bar"

      assert {:ok, env} =
               BaseUrl.call(
                 %Env{url: "/1/indexes/foo/bar", opts: [subdomain_hint: :write, retry_count: 3]},
                 [],
                 @opts
               )

      assert env.url == "https://application_id-2.algolianet.com/1/indexes/foo/bar"

      assert {:ok, env} =
               BaseUrl.call(
                 %Env{url: "/1/indexes/foo/bar", opts: [subdomain_hint: :write, retry_count: 5]},
                 [],
                 @opts
               )

      assert env.url == "https://application_id-1.algolianet.com/1/indexes/foo/bar"
    end
  end

  describe "insights requests" do
    test "use insights host for first request" do
      assert {:ok, env} =
               BaseUrl.call(
                 %Env{url: "/1/events", opts: [subdomain_hint: :insights, retry_count: 0]},
                 [],
                 @opts
               )

      assert env.url == "https://insights.algolia.io/1/events"
    end

    test "use insights host for retried requests" do
      assert {:ok, env} =
               BaseUrl.call(
                 %Env{url: "/1/events", opts: [subdomain_hint: :insights, retry_count: 3]},
                 [],
                 @opts
               )

      assert env.url == "https://insights.algolia.io/1/events"
    end
  end
end
