defmodule AlgoliaTest do
  use ExUnit.Case

  import Algolia

  @indexes [
    "test",
    "test_1",
    "test_2",
    "test_3",
    "test_4",
    "multi_test_1",
    "multi_test_2",
    "delete_by_test_1",
    "move_index_test_src",
    "move_index_test_dst",
    "copy_index_src",
    "copy_index_dst"
  ]

  @settings_test_index "settings_test"

  setup_all do
    client = Algolia.new()

    on_exit(fn ->
      delete_index(client, @settings_test_index)
    end)

    @indexes
    |> Enum.map(&clear_index(client, &1))
    |> Enum.each(&wait(&1, client))

    {:ok, client: client}
  end

  test "add object", %{client: client} do
    {:ok, %{"objectID" => object_id}} =
      client
      |> add_object("test_1", %{text: "hello"})
      |> wait(client)

    assert {:ok, %{"text" => "hello"}} =
             get_object(client, "test_1", object_id)
  end

  test "add multiple objects", %{client: client} do
    assert {:ok, %{"objectIDs" => ids}} =
             client
             |> add_objects("test_1", [
               %{text: "add multiple test"},
               %{text: "add multiple test"},
               %{text: "add multiple test"}
             ])
             |> wait(client)

    for id <- ids do
      assert {:ok, %{"text" => "add multiple test"}} =
               get_object(client, "test_1", id)
    end
  end

  test "list all indexes", %{client: client} do
    assert {:ok, %{"items" => _items}} = list_indexes(client)
  end

  test "wait task", %{client: client} do
    :rand.seed(:exs1024, :erlang.timestamp())
    object_id = :rand.uniform(1_000_000) |> to_string

    {:ok, %{"objectID" => ^object_id, "taskID" => task_id}} =
      save_object(client, "test_1", %{}, object_id)

    wait_task(client, "test_1", task_id)

    assert {:ok, %{"objectID" => ^object_id}} = get_object(client, "test_1", object_id)
  end

  test "save one object, and then read it, using wait_task pipeing", %{client: client} do
    :rand.seed(:exs1024, :erlang.timestamp())
    id = :rand.uniform(1_000_000) |> to_string

    {:ok, %{"objectID" => object_id}} =
      client
      |> save_object("test_1", %{}, id)
      |> wait(client)

    assert object_id == id
    assert {:ok, %{"objectID" => ^object_id}} = get_object(client, "test_1", id)
  end

  describe "save_object/2" do
    test "requires an objectID attribute", %{client: client} do
      assert_raise ArgumentError, ~r/must have an objectID/, fn ->
        save_object(client, "test_1", %{"noObjectId" => "raises error"})
      end
    end

    test "requires a valid attribute as object id", %{client: client} do
      assert_raise ArgumentError, ~r/does not have a 'id' attribute/, fn ->
        save_object(client, "test_1", %{"noId" => "raises error"}, id_attribute: "id")
      end
    end
  end

  test "search single index", %{client: client} do
    :rand.seed(:exs1024, :erlang.timestamp())
    count = :rand.uniform(10)
    docs = Enum.map(1..count, &%{id: &1, test: "search_single_index"})

    {:ok, _} = save_objects(client, "test_3", docs, id_attribute: :id) |> wait(client)

    {:ok, %{"hits" => hits1}} = search(client, "test_3", "search_single_index")
    assert length(hits1) === count
  end

  test "search with list opts", %{client: client} do
    :rand.seed(:exs1024, :erlang.timestamp())
    count = :rand.uniform(10)
    docs = Enum.map(1..count, &%{id: &1, test: "search with list opts"})

    {:ok, _} = save_objects(client, "test_3", docs, id_attribute: :id) |> wait(client)

    opts = [
      responseFields: ["hits", "nbPages"]
    ]

    {:ok, response} = search(client, "test_3", "search_with_list_opts", opts)

    assert response["hits"]
    assert response["nbPages"]
    refute response["page"]
  end

  test "search > 1 pages", %{client: client} do
    docs = Enum.map(1..40, &%{id: &1, test: "search_more_than_one_pages"})

    {:ok, _} = save_objects(client, "test_3", docs, id_attribute: :id) |> wait(client)

    {:ok, %{"hits" => hits, "page" => page}} =
      search(client, "test_3", "search_more_than_one_pages", page: 1)

    assert page == 1
    assert length(hits) === 20
  end

  test "search multiple indexes", %{client: client} do
    :rand.seed(:exs1024, :erlang.timestamp())

    indexes = ["multi_test_1", "multi_test_2"]

    fixture_list = Enum.map(indexes, &generate_fixtures_for_index(client, &1))

    {:ok, %{"results" => results}} =
      indexes
      |> Enum.map(&%{index_name: &1, query: "search_multiple_indexes"})
      |> then(&multi(client, &1))

    for {index, count} <- fixture_list do
      hits =
        results
        |> Enum.find(fn result -> result["index"] == index end)
        |> Map.fetch!("hits")

      assert length(hits) == count
    end
  end

  test "search for facet values", %{client: client} do
    {:ok, _} =
      client
      |> set_settings("test_4", %{attributesForFaceting: ["searchable(family)"]})
      |> wait(client)

    docs = [
      %{family: "Diplaziopsidaceae", name: "D. cavaleriana"},
      %{family: "Diplaziopsidaceae", name: "H. marginatum"},
      %{family: "Dipteridaceae", name: "D. nieuwenhuisii"}
    ]

    {:ok, _} = client |> add_objects("test_4", docs) |> wait(client)

    {:ok, %{"facetHits" => hits}} = search_for_facet_values(client, "test_4", "family", "Dip")

    assert [
             %{
               "count" => 2,
               "highlighted" => "<em>Dip</em>laziopsidaceae",
               "value" => "Diplaziopsidaceae"
             },
             %{
               "count" => 1,
               "highlighted" => "<em>Dip</em>teridaceae",
               "value" => "Dipteridaceae"
             }
           ] == hits
  end

  test "browse index", %{client: client} do
    :rand.seed(:exs1024, :erlang.timestamp())
    count = :rand.uniform(10)
    docs = Enum.map(1..count, &%{id: &1, test: "browse_index"})

    {:ok, _} = save_objects(client, "test_3", docs, id_attribute: :id) |> wait(client)

    {:ok, %{"hits" => hits1}} = browse(client, "test_3", query: "browse_index")
    assert length(hits1) === count
  end

  defp generate_fixtures_for_index(client, index) do
    :rand.seed(:exs1024, :erlang.timestamp())
    count = :rand.uniform(3)
    objects = Enum.map(1..count, &%{objectID: &1, test: "search_multiple_indexes"})
    client |> save_objects(index, objects) |> wait(client, retry_delay: 3_000)
    {index, length(objects)}
  end

  test "search query with special characters", %{client: client} do
    {:ok, %{"hits" => _}} = search(client, "test_1", "foo & bar")
  end

  test "partially update object", %{client: client} do
    {:ok, %{"objectID" => object_id}} =
      client
      |> save_object("test_2", %{id: "partially_update_object"}, id_attribute: :id)
      |> wait(client)

    assert {:ok, _} =
             client
             |> partial_update_object("test_2", %{update: "updated"}, object_id)
             |> wait(client)

    {:ok, object} = get_object(client, "test_2", object_id)
    assert object["update"] == "updated"
  end

  test "partially update object, upsert true", %{client: client} do
    id = "partially_update_object_upsert_true"

    assert {:ok, _} =
             client
             |> partial_update_object("test_2", %{}, id)
             |> wait(client)

    {:ok, object} = get_object(client, "test_2", id)
    assert object["objectID"] == id
  end

  test "partial update object, upsert is false", %{client: client} do
    id = "partial_update_upsert_false"

    assert {:ok, _} =
             client
             |> partial_update_object("test_3", %{update: "updated"}, id, upsert?: false)
             |> wait(client)

    assert {:error, 404, _} = get_object(client, "test_3", id)
  end

  test "partially update multiple objects, upsert is default", %{client: client} do
    objects = [%{id: "partial_update_multiple_1"}, %{id: "partial_update_multiple_2"}]

    assert {:ok, _} =
             client
             |> partial_update_objects("test_3", objects, id_attribute: :id)
             |> wait(client)

    assert {:ok, _} = get_object(client, "test_3", "partial_update_multiple_1")
    assert {:ok, _} = get_object(client, "test_3", "partial_update_multiple_2")
  end

  test "partially update multiple objects, upsert is false", %{client: client} do
    objects = [
      %{id: "partial_update_multiple_1_no_upsert"},
      %{id: "partial_update_multiple_2_no_upsert"}
    ]

    assert {:ok, _} =
             client
             |> partial_update_objects("test_3", objects, id_attribute: :id, upsert?: false)
             |> wait(client)

    assert {:error, 404, _} = get_object(client, "test_3", "partial_update_multiple_1_no_upsert")
    assert {:error, 404, _} = get_object(client, "test_3", "partial_update_multiple_2_no_upsert")
  end

  test "delete object", %{client: client} do
    {:ok, %{"objectID" => object_id}} =
      client
      |> save_object("test_1", %{id: "delete_object"}, id_attribute: :id)
      |> wait(client)

    client |> delete_object("test_1", object_id) |> wait(client)

    assert {:error, 404, _} = get_object(client, "test_1", object_id)
  end

  test "deleting an object with empty string should return an error", %{client: client} do
    assert {:error, %Algolia.InvalidObjectIDError{}} = delete_object(client, "test", "")
  end

  test "delete multiple objects", %{client: client} do
    objects = [%{id: "delete_multipel_objects_1"}, %{id: "delete_multipel_objects_2"}]

    {:ok, %{"objectIDs" => object_ids}} =
      client
      |> save_objects("test_1", objects, id_attribute: :id)
      |> wait(client)

    client |> delete_objects("test_1", object_ids) |> wait(client)

    assert {:error, 404, _} = get_object(client, "test_1", "delete_multipel_objects_1")
    assert {:error, 404, _} = get_object(client, "test_1", "delete_multipel_objects_2")
  end

  describe "delete_by/2" do
    test "deletes according to filters", %{client: client} do
      {:ok, _} =
        client
        |> set_settings("delete_by_test_1", %{attributesForFaceting: ["filterOnly(score)"]})
        |> wait(client)

      objects = [%{id: "gets deleted", score: 10}, %{id: "remains there", score: 20}]

      {:ok, _} =
        client
        |> save_objects("delete_by_test_1", objects, id_attribute: :id)
        |> wait(client)

      results =
        client
        |> delete_by("delete_by_test_1", filters: "score < 15")
        |> wait(client)

      assert {:ok, _} = results

      assert {:error, 404, _} = get_object(client, "delete_by_test_1", "gets deleted")
      assert {:ok, _} = get_object(client, "delete_by_test_1", "remains there")
    end

    test "requires opts", %{client: client} do
      assert_raise ArgumentError, ~r/opts are required/, fn ->
        delete_by(client, "delete_by_test_1", [])
      end
    end

    test "ignores hitsPerPage and attributesToRetrieve opts", %{client: client} do
      assert_raise ArgumentError, ~r/opts are required/, fn ->
        delete_by(client, "delete_by_test_1", hitsPerPage: 10, attributesToRetrieve: [])
      end
    end
  end

  test "settings", %{client: client} do
    attributesToIndex = ~w(foo bar baz)

    assert {:ok, _} =
             client
             |> set_settings(@settings_test_index, %{attributesToIndex: attributesToIndex})
             |> wait(client)

    assert {:ok, %{"attributesToIndex" => ^attributesToIndex}} =
             get_settings(client, @settings_test_index)
  end

  test "move index", %{client: client} do
    src = "move_index_test_src"
    dst = "move_index_test_dst"

    objects = [%{id: "move_1"}, %{id: "move_2"}]

    {:ok, _} = client |> save_objects(src, objects, id_attribute: :id) |> wait(client)
    {:ok, _} = client |> move_index(src, dst) |> wait(client)

    assert {:ok, %{"objectID" => "move_1"}} = get_object(client, dst, "move_1")
    assert {:ok, %{"objectID" => "move_2"}} = get_object(client, dst, "move_2")
  end

  test "copy index", %{client: client} do
    src = "copy_index_src"
    dst = "copy_index_dst"

    objects = [%{id: "copy_1"}, %{id: "copy_2"}]

    {:ok, _} = client |> save_objects(src, objects, id_attribute: :id) |> wait(client)
    {:ok, _} = client |> copy_index(src, dst) |> wait(client)

    assert {:ok, %{"objectID" => "copy_1"}} = get_object(client, dst, "copy_1")
    assert {:ok, %{"objectID" => "copy_2"}} = get_object(client, dst, "copy_2")
  end

  test "deletes an index", %{client: client} do
    index = "delete_test_index"
    client |> add_object(index, %{objectID: "delete_test"}) |> wait(client)

    {:ok, %{"items" => items}} = list_indexes(client)
    all_indexes = Enum.map(items, & &1["name"])
    assert index in all_indexes

    assert {:ok, _} = client |> delete_index(index) |> wait(client)
    {:ok, %{"items" => items}} = list_indexes(client)
    all_indexes = Enum.map(items, & &1["name"])
    refute index in all_indexes
  end

  test "get index logs", %{client: client} do
    {:ok, _} = search(client, "test", "test query")

    assert {:ok, %{"logs" => [log]}} =
             get_logs(client, indexName: "test", length: 1, type: :query)

    assert %{"index" => "test", "query_params" => "query=test+query"} = log
  end

  test "forwards extra HTTP headers", %{client: client} do
    {:ok, _} =
      client
      |> add_object("test", %{text: "hello"}, headers: [{"X-Forwarded-For", "1.2.3.4"}])
      |> wait(client)

    {:ok, %{"logs" => [log]}} = get_logs(client, indexName: "test", length: 1, type: :build)
    %{"index" => "test", "query_headers" => headers} = log
    assert headers =~ ~r/X-Forwarded-For: 1\.2\.3\.4/i
  end

  test "push_events is successful", %{client: client} do
    events = [
      %{
        "eventType" => "click",
        "eventName" => "Product Clicked",
        "index" => "products",
        "userToken" => "user-123456",
        "objectIDs" => ["9780545139700", "9780439784542"],
        "queryID" => "43b15df305339e827f0ac0bdc5ebcaa7",
        "positions" => [7, 6]
      },
      %{
        "eventType" => "view",
        "eventName" => "Product Detail Page Viewed",
        "index" => "products",
        "userToken" => "user-123456",
        "objectIDs" => ["9780545139700", "9780439784542"]
      },
      %{
        "eventType" => "conversion",
        "eventName" => "Product Purchased",
        "index" => "products",
        "userToken" => "user-123456",
        "objectIDs" => ["9780545139700", "9780439784542"],
        "queryID" => "43b15df305339e827f0ac0bdc5ebcaa7"
      }
    ]

    assert {:ok, _} = push_events(client, events)
  end
end
