## Algolia

This is an Elixir implementation of the Algolia search API.

To use it, add the following to your dependencies:

```elixir
defp deps do
    [{:algolia, "~> 0.8.0"}]
end
```

## Configuration

#### Using environment variables:

    ALGOLIA_APPLICATION_ID=YOUR_APPLICATION_ID
    ALGOLIA_API_KEY=YOUR_API_KEY

#### Using config:

```elixir
config :algolia,
  application_id: "YOUR_APPLICATION_ID",
  api_key: "YOUR_API_KEY"
```

**Note**: You must use _admin_ API key rather than a _search_ API key to enable write access.

### Return values

All responses are deserialized into maps before returning one of these responses:

  - `{:ok, response}`
  - `{:error, error_code, response}`
  - `{:error, "Cannot connect to Algolia"}`: The client implements retry
      strategy on all Algolia hosts with increasing timeout. It should only
      return this error when it has tried all 4 hosts.
      [**More details here**](https://www.algolia.com/doc/rest#quick-reference).

## Examples

### Searching

#### Searching an index

```elixir
"my_index" |> Algolia.search("some query")
```

With options:

```elixir
"my_index" |> Algolia.search("some query", attributesToRetrieve: "firstname", hitsPerPage: 20)
```

See all available search options [**here**](https://www.algolia.com/doc/rest#full-text-search-parameters).

#### Browsing an index

Browsing is like search but skips most ranking and allows fetching more results at once.

```elixir
"my_index" |> Algolia.browse("some query", filter: "color:red")
```

#### Multiple queries at once

```elixir
Algolia.multi([
    %{index_name => "my_index1", query: "search query"},
    %{index_name => "my_index2", query: "another query", hitsPerPage: 3,},
    %{index_name => "my_index3", query: "3rd query", tagFilters: "promotion"}])
])
```

You can specify a strategy to optimize your multiple queries:

- `:none`: Execute the sequence of queries until the end.
- `stop_if_enough_matches`: Execute the sequence of queries until the number of hits is reached by the sum of hits.

```elixir
Algolia.multi([query1, query2], strategy: :stop_if_enough_matches)
```

### Saving

All `save_*` operations will overwrite the object at the objectID.

Save a single object to index without specifying objectID. You must have `objectID`
inside object, or use the `id_attribute` option (see below).

```elixir
"my_index" |> Algolia.save_object(%{objectID: "1"})
```

Save a single object with a given objectID:

```elixir
"my_index" |> Algolia.save_object(%{title: "hello"}, "12345")
```

Save multiple objects to an index:

```elixir
"my_index" |> Algolia.save_objects([%{objectID: "1"}, %{objectID: "2"}])
```

### Updating

Partially update a single object:

```elixir
"my_index" |> Algolia.partial_update_object(%{title: "hello"}, "12345")
```

Update multiple objects. You must have `objectID` in each object, or use the `id_attribute` option (see below).

```elixir
"my_index" |> Algolia.partial_update_objects([%{objectID: "1"}, %{objectID: "2"}])
```

Partial update by default creates a new object if an object does not exist at the
objectID. You can turn this off by passing `false` to the `:upsert?` option.

```elixir
"my_index" |> Algolia.partial_update_object(%{title: "hello"}, "12345", upsert?: false)
"my_index" |> Algolia.partial_update_objects([%{id: "1"}, %{id: "2"}], id_attribute: :id, upsert?: false)
```


### `id_attribute` option

All write functions such as `save_object` and `partial_update_object` come with an `id_attribute` option that lets
you specify the `objectID` from an existing field in the object, so you do not have to generate it yourself.

```elixir
"my_index" |> Algolia.save_object(%{id: "2"}, id_attribute: :id)
```

It also works for batch operations, such as `save_objects` and `partial_update_objects`:

```elixir
"my_index" |> Algolia.save_objects([%{id: "1"}, %{id: "2"}], id_attribute: :id)
```


### Wait for task

All write operations can be waited on by simply piping the response into `wait/1`:

```elixir
"my_index" |> Algolia.save_object(%{id: "123"}) |> Algolia.wait()
```

The client polls the server to check the status of the task.
You can specify a time (in milliseconds) between each tick of the poll; the default is 1000ms (1 second).

```elixir
"my_index" |> Algolia.save_object(%{id: "123"}) |> Algolia.wait(2_000)
```

You can also explicitly pass a `taskID` to `wait`:


```elixir
{:ok, %{"taskID" => task_id, "indexName" => index}}
  = "my_index" |> Algolia.save_object(%{id: "123"})

Algolia.wait(index, task_id)
```

Optionally including the poll interval:

```elixir
Algolia.wait(index, task_id, 2_000)
```

### Index related operations

#### Listing all indexes

```elixir
Algolia.list_indexes()
```

#### Move an index

```elixir
Algolia.move_index(source_index, destination_index)
```

#### Copy an index

```elixir
Algolia.copy_index(source_index, destination_index)
```

#### Clear an index

```elixir
Algolia.clear_index(index)
```

### Settings

#### Get index settings

```elixir
Algolia.get_settings(index)
```

Example response:

```elixir
{:ok,
  %{"minWordSizefor1Typo" => 4,
    "minWordSizefor2Typos" => 8,
    "hitsPerPage" => 20,
    "attributesToIndex" => nil,
    "attributesToRetrieve" => nil,
    "attributesToSnippet" => nil,
    "attributesToHighlight" => nil,
    "ranking" => [
        "typo",
        "geo",
        "words",
        "proximity",
        "attribute",
        "exact",
        "custom"
    ],
    "customRanking" => nil,
    "separatorsToIndex" => "",
    "queryType" => "prefixAll"}}
```

#### Update index settings

```elixir
Algolia.set_settings(index, %{"hitsPerPage" => 20})

> {:ok, %{"updatedAt" => "2013-08-21T13:20:18.960Z",
          "taskID" => 10210332.
          "indexName" => "my_index"}}
```

### Insights

#### Push events

```elixir
Algolia.push_events([
  %{
    "eventType" => "click",
    "eventName" => "Product Clicked",
    "index" => "products",
    "userToken" => "user-123456",
    "objectIDs" => ["9780545139700", "9780439784542"],
    "queryID" => "43b15df305339e827f0ac0bdc5ebcaa7",
    "positions" => [7, 6]
  }
])
```
