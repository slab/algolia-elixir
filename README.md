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

### Creating a client

All API function that make requests require a client.

```elixir
client = Algolia.new()
```

### Searching

#### Searching an index

```elixir
Algolia.search(client, "my_index", "some query")
```

With options:

```elixir
Algolia.search(client, "my_index", "some query", attributesToRetrieve: "firstname", hitsPerPage: 20)
```

See all available search options [**here**](https://www.algolia.com/doc/rest#full-text-search-parameters).

#### Browsing an index

Browsing is like search but skips most ranking and allows fetching more results at once.

```elixir
Algolia.browse(client, "my_index", query: "some query", filter: "color:red")
```

#### Multiple queries at once

```elixir
Algolia.multi(client, [
  %{index_name: "my_index1", query: "search query"},
  %{index_name: "my_index2", query: "another query", hitsPerPage: 3},
  %{index_name: "my_index3", query: "3rd query", tagFilters: "promotion"}
])
```

You can specify a strategy to optimize your multiple queries:

- `:none`: Execute the sequence of queries until the end.
- `stop_if_enough_matches`: Execute the sequence of queries until the number of hits is reached by the sum of hits.

```elixir
Algolia.multi(client, [query1, query2], strategy: :stop_if_enough_matches)
```

### Saving

All `save_*` operations will overwrite the object at the objectID.

Save a single object to index without specifying objectID. You must have `objectID`
inside object, or use the `id_attribute` option (see below).

```elixir
Algolia.save_object(client, "my_index", %{objectID: "1"})
```

Save a single object with a given objectID:

```elixir
Algolia.save_object(client, "my_index", %{title: "hello"}, "12345")
```

Save multiple objects to an index:

```elixir
Algolia.save_objects(client, "my_index", [%{objectID: "1"}, %{objectID: "2"}])
```

### Updating

Partially update a single object:

```elixir
Algolia.partial_update_object(client, "my_index", %{title: "hello"}, "12345")
```

Update multiple objects. You must have `objectID` in each object, or use the `id_attribute` option (see below).

```elixir
Algolia.partial_update_objects(client, "my_index", [%{objectID: "1"}, %{objectID: "2"}])
```

Partial update by default creates a new object if an object does not exist at the
objectID. You can turn this off by passing `false` to the `:upsert?` option.

```elixir
Algolia.partial_update_object(client, "my_index", %{title: "hello"}, "12345", upsert?: false)
Algolia.partial_update_objects(client, "my_index", [%{id: "1"}, %{id: "2"}], id_attribute: :id, upsert?: false)
```

### `id_attribute` option

All write functions such as `save_object` and `partial_update_object` come with an `id_attribute` option that lets
you specify the `objectID` from an existing field in the object, so you do not have to generate it yourself.

```elixir
Algolia.save_object(client, "my_index", %{id: "2"}, id_attribute: :id)
```

It also works for batch operations, such as `save_objects` and `partial_update_objects`:

```elixir
Algolia.save_objects(client, "my_index", [%{id: "1"}, %{id: "2"}], id_attribute: :id)
```

### Wait for task

All write operations can be waited on by simply piping the response into `wait/1`:

```elixir
client
|> Algolia.save_object("my_index", %{id: "123"})
|> Algolia.wait(client)
```

The client polls the server to check the status of the task.
You can specify a time (in milliseconds) between each tick of the poll; the default is 1000ms (1 second).

```elixir
client
|> Algolia.save_object("my_index", %{id: "123"})
|> Algolia.wait(client, retry_delay: 2_000)
```

You can also explicitly pass a `taskID` to `wait_task`:


```elixir
{:ok, %{"taskID" => task_id, "indexName" => index}}
  = Algolia.save_object(client, "my_index", %{id: "123"})

Algolia.wait_task(client, index, task_id)
```

Optionally including the poll interval:

```elixir
Algolia.wait(client, index, task_id, retry_delay: 2_000)
```

### Index related operations

#### Listing all indexes

```elixir
Algolia.list_indexes(client)
```

#### Move an index

```elixir
Algolia.move_index(client, source_index, destination_index)
```

#### Copy an index

```elixir
Algolia.copy_index(client, source_index, destination_index)
```

#### Clear an index

```elixir
Algolia.clear_index(client, index)
```

### Settings

#### Get index settings

```elixir
Algolia.get_settings(client, index)
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
Algolia.set_settings(client, index, %{"hitsPerPage" => 20})

> {:ok, %{"updatedAt" => "2013-08-21T13:20:18.960Z",
          "taskID" => 10210332.
          "indexName" => "my_index"}}
```

### Insights

#### Push events

```elixir
Algolia.push_events(client, [
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
