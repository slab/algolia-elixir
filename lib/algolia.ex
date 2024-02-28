defmodule Algolia do
  @moduledoc """
  Elixir implementation of Algolia Search API.

  You can interact with Algolia's API by creating a new client using `new/1`, and then using
  the other functions in this modules to make requests with that client.
  """

  alias Algolia.Paths

  defmodule MissingApplicationIDError do
    defexception message: """
                   The `application_id` settings is required to use Algolia. Please include your
                   application_id in your application config file like so:
                     config :algolia, application_id: YOUR_APPLICATION_ID
                   Alternatively, you can also set the secret key as an environment variable:
                     ALGOLIA_APPLICATION_ID=YOUR_APP_ID
                 """
  end

  defmodule MissingAPIKeyError do
    defexception message: """
                   The `api_key` settings is required to use Algolia. Please include your
                   api key in your application config file like so:
                     config :algolia, api_key: YOUR_API_KEY
                   Alternatively, you can also set the secret key as an environment variable:
                     ALGOLIA_API_KEY=YOUR_SECRET_API_KEY
                 """
  end

  defmodule InvalidObjectIDError do
    defexception message: "The ObjectID cannot be an empty string"
  end

  @doc false
  def application_id do
    System.get_env("ALGOLIA_APPLICATION_ID") || Application.get_env(:algolia, :application_id) ||
      raise MissingApplicationIDError
  end

  @doc false
  def api_key do
    System.get_env("ALGOLIA_API_KEY") || Application.get_env(:algolia, :api_key) ||
      raise MissingAPIKeyError
  end

  @typedoc """
  A client to use to communicate with Algolia.

  All API functions require a client to be able to make requests.
  """
  @type client() :: Tesla.Client.t()

  @typedoc """
  The name of an Algolia index.
  """
  @type index() :: String.t()

  @typedoc """
  Generic options that can be passed to any API function.
  """
  @type request_option() :: {:headers, Tesla.Env.headers()}
  @type result(resp) :: {:ok, resp} | {:error, any()}

  @doc """
  Creates a new Algolia client.

  A client must be passed to any function that makes a request to Algolia.

  ## Examples

      client = Algolia.new(
        api_key: "my_api_key",
        application_id: "my_application_id"
      )
      Algolia.search(client, "my_index", "some query")

      # adding logging middleware
      client = Algolia.new(
        middleware: fn middleware ->
          middleware ++ [
            {Tesla.Middleware.Logger, filter_headers: ["X-Algolia-API-Key"]}
          ]
        end
      )

      # set a custom adapter
      client = Algolia.new(adapter: Tesla.Adapter.Mint)

  ## Options

  * `:api_key` - the API key to use for Algolia. If unset, reads from the `ALGOLIA_API_KEY`
    environment variable or the `:api_key` key in the `:algolia` application config.
  * `:application_id` - the application ID to use for Algolia. If unset, reads from the
    `ALGOLIA_APPLICATION_ID` environment variable or the `:application_id` key in the
    `:algolia` application config.
  * `:middleware` - a function that can be used to alter the default list of Tesla middleware
    that will be used. The function takes the default list of middleware as an argument, so
    you can inject middleware as needed. Note that removing any of the default middleware
    might break the client.
  * `:adapter` - the Tesla HTTP adapter to use. Defaults to Tesla's default adapter, which
    is `:httpc` by default but can be overridden in the `:tesla` application config.
  """
  @spec new([
          {:api_key, String.t()}
          | {:application_id, String.t()}
          | {:middleware, ([Tesla.Client.middleware()] -> [Tesla.Client.middleware()])}
          | {:adapter, Tesla.Client.adapter()}
        ]) :: client()
  def new(opts \\ []) do
    middleware_fn = Keyword.get(opts, :middleware, & &1)
    adapter = Keyword.get(opts, :adapter)

    middleware =
      opts
      |> Keyword.put_new_lazy(:api_key, &api_key/0)
      |> Keyword.put_new_lazy(:application_id, &application_id/0)
      |> default_middleware()
      |> middleware_fn.()

    Tesla.client(middleware, adapter)
  end

  defp default_middleware(opts) do
    [
      Algolia.Middleware.Telemetry,
      {Algolia.Middleware.Headers, Keyword.take(opts, [:api_key, :application_id])},
      Algolia.Middleware.Retry,
      {Algolia.Middleware.BaseUrl, Keyword.take(opts, [:application_id])},
      Tesla.Middleware.JSON
    ]
  end

  @type multi_strategy() :: nil | :stop_if_enough_matches

  @doc """
  Performs multiple search queries in a single request.

  Each entry in `queries` should be a map with `:index_name` indicating which index to search,
  and the remaining keys corresponding to [Algolia search parameters](https://www.algolia.com/doc/api-reference/search-api-parameters/).

  ## Examples

      Algolia.multi(client, [
        %{index_name: "my_index1", query: "search query"},
        %{index_name: "my_index2", query: "another query", hitsPerPage: 3},
        %{index_name: "my_index3", query: "3rd query", tagFilters: "promotion"}
      ])

  ## Options

  * `:strategy` - strategy to use to decide whether to continue with additional queries. Can be
    either `:none` or `:stop_if_enough_matches`. Defaults to `:none`. See
    [Algolia's documentation](https://www.algolia.com/doc/rest-api/search/#search-multiple-indices)
    for more information about the difference between these two strategies.
  * `:headers` - list of additional HTTP headers to include in the request.
  """
  @spec multi(client(), [map()], [{:strategy, multi_strategy()} | request_option()]) ::
          result(map())
  def multi(client, queries, opts \\ []) do
    {req_opts, opts} = pop_request_opts(opts)

    path = Paths.multiple_queries(opts[:strategy])

    send_request(client, :read, %{
      method: :post,
      path: path,
      body: format_multi(queries),
      options: req_opts
    })
  end

  defp format_multi(queries) do
    requests =
      Enum.map(queries, fn query ->
        index_name = query[:index_name] || query["index_name"]

        if !index_name,
          do: raise(ArgumentError, message: "Missing index_name for one of the multiple queries")

        params =
          query
          |> Map.delete(:index_name)
          |> Map.delete("index_name")
          |> URI.encode_query()

        %{indexName: index_name, params: params}
      end)

    %{requests: requests}
  end

  @doc """
  Searches a single index.

  ## Examples

      # basic search
      Algolia.search(client, "my_index", "some query")

      # with search parameters
      Algolia.search(client, "my_index", "some query",
        attributesToRetrieve: "firstname",
        hitsPerPage: 20
      )

  ## Options

  Any of Algolia's supported [search parameters](https://www.algolia.com/doc/api-reference/search-api-parameters/)
  can be passed as options.

  ### Additional options

  * `:headers` - list of additional HTTP headers to include in the request.
  """
  @spec search(client(), index(), String.t(), [{atom(), any()} | request_option()]) ::
          result(map())
  def search(client, index, query, opts \\ []) do
    {req_opts, opts} = pop_request_opts(opts)

    body =
      opts
      |> Map.new()
      |> Map.put(:query, query)

    with {:ok, %{} = data} <-
           send_request(client, :read, %{
             method: :post,
             path: Paths.search(index),
             body: body,
             options: req_opts
           }) do
      :telemetry.execute(
        [:algolia, :search, :result],
        %{hits: data["nbHits"], processing_time: data["processingTimeMS"]},
        %{query: query, index: index, options: opts}
      )

      {:ok, data}
    end
  end

  @doc """
  Searches for facet values.

  Enables you to search through the values of a facet attribute, selecting
  only a subset of those values that meet a given criteria.

  For a facet attribute to be searchable, it must have been declared in the
  `attributesForFaceting` index setting with the `searchable` modifier.

  Facet-searching only affects facet values. It does not impact the underlying
  index search.

  ## Examples

      iex> Algolia.search_for_facet_values("species", "phylum", "dophyta")
      {:ok,
        %{"exhaustiveFacetsCount" => false,
          "facetHits" => [
            %{
              "count" => 9000,
              "highlighted" => "Pteri<em>dophyta</em>",
              "value" => "Pteridophyta"
            },
            %{
              "count" => 7000,
              "highlighted" => "Rho<em>dophyta</em>",
              "value" => "Rhodophyta"
            },
            %{
              "count" => 150,
              "highlighted" => "Cyca<em>dophyta</em>",
              "value" => "Cycadophyta"
            }
          ],
          "processingTimeMS" => 42}}

  ## Options

  Many of Algolia's supported [search parameters](https://www.algolia.com/doc/api-reference/search-api-parameters/)
  can be passed as options to filter the objects that are matched.

  ### Additional options

  * `:sortFacetValuesBy` - control how facets are sorted. Either `"count"` (by count, descending)
    or `"alpha"` (by value alphabetically, ascending). Defaults to `"count"`.
  * `:maxFacetHits` - maximum number of hits to return. Defaults to 10. Cannot exceed 100.
  * `:headers` - list of additional HTTP headers to include in the request.
  """
  @spec search_for_facet_values(client(), index(), String.t(), String.t(), [
          request_option() | {atom(), any()}
        ]) :: result(map())
  def search_for_facet_values(client, index, facet, text, opts \\ []) do
    {req_opts, opts} = pop_request_opts(opts)

    path = Paths.search_facet(index, facet)

    body =
      opts
      |> Map.new()
      |> Map.put("facetQuery", text)

    send_request(client, :read, %{method: :post, path: path, body: body, options: req_opts})
  end

  @doc """
  Browses a single index.

  Browsing is similar to searching, but it skips ranking results and allows fetching more
  objects.

  ## Example

      Algolia.browse(client, "my_index", filters: "color:red AND kind:fruit")

  ## Options

  Any of Algolia's supported [search parameters](https://www.algolia.com/doc/api-reference/search-api-parameters/)
  can be passed as options, with the exception of `:distinct` which is not supported when browsing.

  ### Additional options

  * `:headers` - list of additional HTTP headers to include in the request.
  """
  @spec browse(client(), index(), [request_option() | {atom(), any()}]) :: result(map())
  def browse(client, index, opts \\ []) do
    {req_opts, opts} = pop_request_opts(opts)

    with {:ok, %{} = data} <-
           send_request(client, :read, %{
             method: :post,
             path: Paths.browse(index),
             body: Map.new(opts),
             options: req_opts
           }) do
      :telemetry.execute(
        [:algolia, :browse, :result],
        %{hits: data["nbHits"], processing_time: data["processingTimeMS"]},
        %{index: index, options: opts}
      )

      {:ok, data}
    end
  end

  @doc """
  Retrieves a single object from an index by ID.

  ## Example

      Algolia.get_object(client, "my_index", "123")

  ## Options

  * `:headers` - list of additional HTTP headers to include in the request.
  """
  @spec get_object(client(), index(), String.t(), [request_option()]) :: result(map())
  def get_object(client, index, object_id, opts \\ []) do
    path = Paths.object(index, object_id)

    client
    |> send_request(:read, %{method: :get, path: path, options: opts})
    |> inject_index_into_response(index)
  end

  @doc """
  Adds an object to an index, or replaces an existing one.

  If the object does not have an `:objectID` or `"objectID"` key, then Algolia
  will automatically generate one and add it to the object.

  The `:id_attribute` option can be used to set the `:objectID` key based on an
  existing key already on the object.

  ## Examples

      # add an object with automatically generated object ID
      Algolia.add_object(client, "my_index", %{
        kind: "fruit",
        color: "red",
        name: "apple"
      })

      # add or replace an object based on the object ID
      Algolia.add_object(client, "my_index", %{
        objectID: "123",
        kind: "fruit",
        color: "red",
        name: "apple"
      })

      # set the object ID based on another attribute
      Algolia.add_object(client, "my_index", %{
        kind: "fruit",
        color: "red",
        name: "apple"
      }, id_attribute: :name)
      # resulting objectID is "apple"

  ## Options

  * `:id_attribute` - key to use as the `:objectID` of the object. If set, the
    saved object will have both `:objectID` and this key set to the same value.
  * `:headers` - list of additional HTTP headers to include in the request.
  """
  @spec add_object(client(), index(), map(), [
          {:id_attribute, atom() | String.t()} | request_option()
        ]) :: result(map())
  def add_object(client, index, object, opts \\ []) do
    if opts[:id_attribute] do
      save_object(client, index, object, opts)
    else
      path = Paths.index(index)

      client
      |> send_request(:write, %{
        method: :post,
        path: path,
        body: object,
        options: opts
      })
      |> inject_index_into_response(index)
    end
  end

  @doc """
  Adds or replaces multiple objects in an index.

  If any objects do not have an `:objectID` or `"objectID"` key, then Algolia
  will automatically generate one and add it to the object.

  The `:id_attribute` option can be used to set the `:objectID` key based on an
  existing key already on the object.

  ## Examples

      # with automatically assigned object IDs
      Algolia.add_objects(client, "my_index", [
        %{name: "apple"},
        %{name: "banana"},
        %{name: "pear"}
      ])

      # adding or replacing objects based on object ID
      Algolia.add_objects(client, "my_index", [
        %{objectID: "fruit1", name: "apple"},
        %{objectID: "fruit2", name: "banana"},
        %{objectID: "fruit3", name: "pear"}
      ])

      # use the `:name` as the object IDs
      Algolia.add_objects(client, "my_index", [
        %{name: "apple"},
        %{name: "banana"},
        %{name: "pear"}
      ], id_attribute: :name)

  ## Options

  * `:id_attribute` - key to use as the `:objectID` of the objects. If set, the
    saved objects will have both `:objectID` and this key set to the same value.
  * `:headers` - list of additional HTTP headers to include in the request.
  """
  @spec add_objects(client(), index(), [map()], [
          {:id_attribute, atom() | String.t()} | request_option()
        ]) :: result(map())
  def add_objects(client, index, objects, opts \\ []) do
    if opts[:id_attribute] do
      save_objects(client, index, objects, opts)
    else
      objects
      |> build_batch_request("addObject")
      |> send_batch_request(client, index, opts)
    end
  end

  @doc """
  Saves a single object, replacing it if it already exists.

  Unlike `add_object/4`, the object must already have an object ID. The `:id_attribute`
  option can still be used to set an object ID based on another attribute.

  ## Examples

      # add or replace an object based on the object ID
      Algolia.save_object(client, "my_index", %{
        objectID: "123",
        kind: "fruit",
        color: "red",
        name: "apple"
      })

      # pass the object ID as its own argument
      Algolia.save_object(client, "my_index", %{
        kind: "fruit",
        color: "red",
        name: "apple"
      }, "123")

      # set the object ID based on another attribute
      Algolia.save_object(client, "my_index", %{
        kind: "fruit",
        color: "red",
        name: "apple"
      }, id_attribute: :name)
      # resulting objectID is "apple"

  ## Options

  * `:id_attribute` - key to use as the `:objectID` of the object. If set, the
    saved object will have both `:objectID` and this key set to the same value.
  * `:headers` - list of additional HTTP headers to include in the request.
  """
  @spec save_object(client(), index(), map(), [
          {:id_attribute, atom() | String.t()} | request_option()
        ]) :: result(map())
  def save_object(client, index, object, opts \\ [])

  def save_object(client, index, object, id) when is_map(object) and not is_list(id) do
    save_object(client, index, object, id, [])
  end

  def save_object(client, index, object, opts) when is_map(object) do
    id = object_id_for_save!(object, opts)

    save_object(client, index, object, id, opts)
  end

  defp object_id_for_save!(object, opts) do
    if id_attribute = opts[:id_attribute] do
      object[id_attribute] || object[to_string(id_attribute)] ||
        raise ArgumentError,
          message: "Your object does not have a '#{id_attribute}' attribute"
    else
      object["objectID"] || object[:objectID] ||
        raise ArgumentError,
          message: "Your object must have an objectID to be saved using save_object"
    end
  end

  defp save_object(client, index, object, object_id, opts) do
    path = Paths.object(index, object_id)

    client
    |> send_request(:write, %{method: :put, path: path, body: object, options: opts})
    |> inject_index_into_response(index)
  end

  @doc """
  Saves multiple objects, replacing any that already exist.

  Unlike `add_objects/4`, the objects must already have object IDs. The `:id_attribute`
  option can still be used to set the object IDs based on another attribute.

  ## Examples

      Algolia.save_objects(client, "my_index", [
        %{objectID: "1", name: "apple"},
        %{objectID: "2", name: "orange"}
      ])

      # use `:id` for the object ID
      Algolia.save_objects(client, "my_index", [
        %{id: "1", name: "apple"},
        %{id: "2", name: "orange"}
      ], id_attribute: :id)

  ## Options

  * `:id_attribute` - key to use as the `:objectID` of the objects.
  * `:headers` - list of additional HTTP headers to include in the request.
  """
  @spec save_objects(client(), index(), [map()], [
          {:id_attribute, atom() | String.t()} | request_option()
        ]) :: result(map())
  def save_objects(client, index, objects, opts \\ [id_attribute: :objectID])
      when is_list(objects) do
    id_attribute = opts[:id_attribute] || :objectID

    objects
    |> add_object_ids(id_attribute: id_attribute)
    |> build_batch_request("updateObject")
    |> send_batch_request(client, index, opts)
  end

  @doc """
  Partially updates a single object.

  ## Examples

      Algolia.partial_update_object(client, "my_index", %{
        objectID: "1",
        name: "apple"
      })

      # don't create the object if it doesn't already exist
      Algolia.partial_update_object(client, "my_index", %{
        id: "1",
        name: "apple"
      }, upsert?: false)

  ## Options

  * `:upsert?` - whether to create the record if it doesn't already exist. Defaults to `true`.
  * `:headers` - list of additional HTTP headers to include in the request.
  """
  @spec partial_update_object(client(), index(), map(), String.t(), [
          {:upsert?, boolean()} | request_option()
        ]) :: result(map())
  def partial_update_object(client, index, object, object_id, opts \\ [upsert?: true]) do
    path = Paths.partial_object(index, object_id, opts[:upsert?])

    client
    |> send_request(:write, %{method: :post, path: path, body: object, options: opts})
    |> inject_index_into_response(index)
  end

  @doc """
  Partially updates multiple objects.

  ## Examples

      Algolia.partial_update_objects(client, "my_index", [
        %{objectID: "1", name: "apple"},
        %{objectID: "2", name: "orange"}
      ])

      # don't create objects if they don't already exist,
      # and use `:id` for the object ID
      Algolia.partial_update_objects(client, "my_index", [
        %{id: "1", name: "apple"},
        %{id: "2", name: "orange"}
      ], upsert?: false, id_attribute: :id)

  ## Options

  * `:upsert?` - whether to create any records that don't already exist. Defaults to `true`.
  * `:id_attribute` - key to use as the `:objectID` of the objects.
  * `:headers` - list of additional HTTP headers to include in the request.
  """
  @spec partial_update_objects(client(), index(), [map()], [
          {:upsert?, boolean()}
          | {:id_attribute, atom() | String.t()}
          | request_option()
        ]) :: result(map())
  def partial_update_objects(
        client,
        index,
        objects,
        opts \\ [upsert?: true, id_attribute: :objectID]
      ) do
    id_attribute = opts[:id_attribute] || :objectID

    upsert =
      case opts[:upsert?] do
        false -> false
        _ -> true
      end

    action = if upsert, do: "partialUpdateObject", else: "partialUpdateObjectNoCreate"

    objects
    |> add_object_ids(id_attribute: id_attribute)
    |> build_batch_request(action)
    |> send_batch_request(client, index, opts)
  end

  # No need to add any objectID by default
  defp add_object_ids(objects, id_attribute: :objectID), do: objects
  defp add_object_ids(objects, id_attribute: "objectID"), do: objects

  defp add_object_ids(objects, id_attribute: attribute) do
    Enum.map(objects, fn object ->
      object_id = object[attribute] || object[to_string(attribute)]

      if !object_id do
        raise ArgumentError, message: "id attribute `#{attribute}` doesn't exist"
      end

      add_object_id(object, object_id)
    end)
  end

  defp add_object_id(object, object_id) do
    Map.put(object, :objectID, object_id)
  end

  defp get_object_id(object) do
    case object[:objectID] || object["objectID"] do
      nil -> {:error, "Not objectID found"}
      object_id -> {:ok, object_id}
    end
  end

  defp send_batch_request(requests, client, index, opts) do
    path = Paths.batch(index)

    client
    |> send_request(:write, %{method: :post, path: path, body: requests, options: opts})
    |> inject_index_into_response(index)
  end

  defp build_batch_request(objects, action) do
    requests =
      Enum.map(objects, fn object ->
        case get_object_id(object) do
          {:ok, object_id} -> %{action: action, body: object, objectID: object_id}
          _ -> %{action: action, body: object}
        end
      end)

    %{requests: requests}
  end

  @doc """
  Deletes a single object by its object ID.

  ## Options

  * `:headers` - list of additional HTTP headers to include in the request.
  """
  @spec delete_object(client(), index(), String.t(), [request_option()]) :: result(map())
  def delete_object(client, index, object_id, opts \\ [])

  def delete_object(_client, _index, "", _request_options) do
    {:error, %InvalidObjectIDError{}}
  end

  def delete_object(client, index, object_id, opts) do
    path = Paths.object(index, object_id)

    client
    |> send_request(:write, %{method: :delete, path: path, options: opts})
    |> inject_index_into_response(index)
  end

  @doc """
  Deletes multiple objects by object ID.

  ## Options

  * `:headers` - list of additional HTTP headers to include in the request.
  """
  @spec delete_objects(client(), index(), [String.t()], [request_option()]) :: result(map())
  def delete_objects(client, index, object_ids, opts \\ []) do
    object_ids
    |> Enum.map(fn id -> %{objectID: id} end)
    |> build_batch_request("deleteObject")
    |> send_batch_request(client, index, opts)
  end

  @doc """
  Removes all objects matching a filter.

  ## Examples

      iex> Algolia.delete_by(client, "index", filters: ["score < 30"])
      {:ok,
        %{"indexName" => "index",
          "taskId" => 42,
          "deletedAt" => "2018-10-30T15:33:13.556Z"}}

  ## Options

  Allowed filter parameters:

  * `filters`
  * `facetFilters`
  * `numericFilters`
  * `aroundLatLng` and `aroundRadius` (these two need to be used together)
  * `insideBoundingBox`
  * `insidePolygon`

  They have the same meaning as when used for a query (such as with `search/4` or `browse/3`).
  At least one type of filter is required.

  ### Additional options

  * `:headers` - list of additional HTTP headers to include in the request.
  """
  @spec delete_by(client(), index(), [{atom(), any()} | request_option()]) :: result(map())
  def delete_by(client, index, opts) when is_list(opts) do
    {req_opts, opts} = pop_request_opts(opts)

    path = Paths.delete_by(index)

    body =
      opts
      |> sanitize_delete_by_opts()
      |> validate_delete_by_opts!()
      |> Map.new()

    client
    |> send_request(:write, %{method: :post, path: path, body: body, options: req_opts})
    |> inject_index_into_response(index)
  end

  defp sanitize_delete_by_opts(opts) do
    Keyword.drop(opts, [
      :hitsPerPage,
      :attributesToRetrieve,
      "hitsPerPage",
      "attributesToRetrieve"
    ])
  end

  defp validate_delete_by_opts!([]) do
    raise ArgumentError, message: "opts are required, use `clear_index/1` to wipe the index."
  end

  defp validate_delete_by_opts!(opts), do: opts

  @doc """
  Lists all indexes.

  ## Options

  * `:headers` - list of additional HTTP headers to include in the request.
  """
  @spec list_indexes(client(), [request_option()]) :: result(map())
  def list_indexes(client, opts \\ []) do
    send_request(client, :read, %{method: :get, path: Paths.indexes(), options: opts})
  end

  @doc """
  Deletes an index.

  ## Options

  * `:headers` - list of additional HTTP headers to include in the request.
  """
  @spec delete_index(client(), index(), [request_option()]) :: result(map())
  def delete_index(client, index, opts \\ []) do
    client
    |> send_request(:write, %{method: :delete, path: Paths.index(index), options: opts})
    |> inject_index_into_response(index)
  end

  @doc """
  Clears all objects from an index.

  ## Options

  * `:headers` - list of additional HTTP headers to include in the request.
  """
  @spec clear_index(client(), index(), [request_option()]) :: result(map())
  def clear_index(client, index, opts \\ []) do
    client
    |> send_request(:write, %{method: :post, path: Paths.clear(index), options: opts})
    |> inject_index_into_response(index)
  end

  @doc """
  Sets the settings of a index.

  ## Example

      iex> Algolia.set_settings(client, "my_index", %{hitsPerPage: 20})
      {:ok,
        %{"updatedAt" => "2013-08-21T13:20:18.960Z",
          "taskID" => 10210332.
          "indexName" => "my_index"}}

  ## Options

  * `:headers` - list of additional HTTP headers to include in the request.
  """
  @spec set_settings(client(), index(), map(), [request_option()]) :: result(map())
  def set_settings(client, index, settings, opts \\ []) do
    path = Paths.settings(index)

    client
    |> send_request(:write, %{method: :put, path: path, body: settings, options: opts})
    |> inject_index_into_response(index)
  end

  @doc """
  Gets the settings of a index.

  ## Example

      iex> Algolia.get_settings(client, "my_index")
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

  ## Options

  * `:headers` - list of additional HTTP headers to include in the request.
  """
  @spec get_settings(client(), index(), [request_option()]) :: result(map())
  def get_settings(client, index, opts \\ []) do
    client
    |> send_request(:read, %{method: :get, path: Paths.settings(index), options: opts})
    |> inject_index_into_response(index)
  end

  @doc """
  Moves an index to new one.

  ## Options

  * `:headers` - list of additional HTTP headers to include in the request.
  """
  @spec move_index(client(), index(), index(), [request_option()]) :: result(map())
  def move_index(client, src_index, dst_index, opts \\ []) do
    body = %{operation: "move", destination: dst_index}

    client
    |> send_request(:write, %{
      method: :post,
      path: Paths.operation(src_index),
      body: body,
      options: opts
    })
    |> inject_index_into_response(src_index)
  end

  @doc """
  Copies an index to a new one.

  ## Options

  * `:headers` - list of additional HTTP headers to include in the request.
  """
  @spec copy_index(client(), index(), index(), [request_option()]) :: result(map())
  def copy_index(client, src_index, dst_index, opts \\ []) do
    body = %{operation: "copy", destination: dst_index}

    client
    |> send_request(:write, %{
      method: :post,
      path: Paths.operation(src_index),
      body: body,
      options: opts
    })
    |> inject_index_into_response(src_index)
  end

  @doc """
  Gets the logs of the latest search and indexing operations.

  ## Options

  * `:indexName` - index for which log entries should be retrieved. When omitted,
    log entries are retrieved across all indices.
  * `:length` - maximum number of entries to retrieve. Maximum allowed value: 1000.
  * `:offset` - first entry to retrieve (zero-based). Log entries are sorted by
    decreasing date, therefore 0 designates the most recent log entry.
  * `:type` - type of log to retrieve: `:all`, `:query`, `:build` or `:error`. Defaults
    to `:all`.
  * `:headers` - list of additional HTTP headers to include in the request.
  """
  @spec get_logs(client(), [
          {:indexName, index()}
          | {:length, integer()}
          | {:offset, integer()}
          | {:type, :all | :query | :build | :error}
          | request_option()
        ]) :: result(map())
  def get_logs(client, opts \\ []) do
    {req_opts, opts} = pop_request_opts(opts)
    send_request(client, :write, %{method: :get, path: Paths.logs(opts), options: req_opts})
  end

  @doc """
  Waits for a task for an index to complete.

  Returns `:ok` when the task is completed.

  ## Example

      {:ok, %{"taskID" => task_id, "indexName" => index}} =
        Algolia.save_object(client, %{id: "123"}, id_attribute: :id)

      Algolia.wait_task(client, index, task_id)

  See `wait/3` for a convenient shortcut using piping.

  ## Options

  * `:retry_delay` - number of milliseconds to wait before each request to Algolia to
    check for task completion. Defaults to `1_000`, or one second.
  * `:headers` - list of additional HTTP headers to include in the request.
  """
  @spec wait_task(client(), index(), String.t(), [
          {:retry_delay, integer()} | request_option()
        ]) :: :ok | {:error, any()}
  def wait_task(client, index, task_id, opts \\ []) do
    retry_delay = Keyword.get(opts, :retry_delay, 1000)

    case send_request(client, :write, %{
           method: :get,
           path: Paths.task(index, task_id),
           options: opts
         }) do
      {:ok, %{"status" => "published"}} ->
        :ok

      {:ok, %{"status" => "notPublished"}} ->
        :timer.sleep(retry_delay)
        wait_task(client, index, task_id, opts)

      other ->
        other
    end
  end

  @doc """
  Waits on the task created by a previous request.

  This is a convenient variation of `wait_task/4` that accepts a response from another
  API function. You can pipe another API function into `wait/3` to only return the
  response once the task is completed.

  ## Examples

      client
      |> Algolia.save_object("my_index", %{id: "123"}, id_attribute: :id)
      |> Algolia.wait(client)

      client
      |> Algolia.save_objects("my_index", [
        %{id: "123"},
        %{id: "234"}
      ], id_attribute: :id)
      |> Algolia.wait(client, retry_delay: 2_000)

  ## Options

  * `:retry_delay` - number of milliseconds to wait before each request to Algolia to
    check for task completion. Defaults to `1_000`, or one second.
  * `:headers` - list of additional HTTP headers to include in the request.
  """
  @spec wait(result(map()), client(), [
          {:retry_delay, integer()} | request_option()
        ]) :: :ok | {:error, any()}
  def wait(response, client, opts \\ [])

  def wait({:ok, %{"indexName" => index, "taskID" => task_id}} = response, client, opts) do
    with :ok <- wait_task(client, index, task_id, opts), do: response
  end

  def wait(response, _client, _opts), do: response

  @doc """
  Pushes events to the Insights API.

  See Algolia's documentation for the [send events endpoint](https://www.algolia.com/doc/rest-api/insights/#send-events)
  for more information on the fields that events should include.

  ## Examples

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

  ## Options

  * `:headers` - list of additional HTTP headers to include in the request.
  """
  @spec push_events(client(), [map()], [request_option()]) :: result(map())
  def push_events(client, events, opts \\ []) do
    body = %{"events" => events}

    send_request(
      client,
      :insights,
      %{method: :post, path: "/1/events", body: body, options: opts}
    )
  end

  defp send_request(client, subdomain_hint, request) do
    {path, request} = Map.pop(request, :path)
    {options, request} = Map.pop(request, :options, [])

    opts =
      request
      |> Map.to_list()
      |> Keyword.merge(
        url: path,
        headers: options[:headers] || [],
        opts: [subdomain_hint: subdomain_hint]
      )

    with {:ok, %{body: response}} <- Tesla.request(client, opts) do
      {:ok, response}
    end
  end

  defp pop_request_opts(opts) do
    Keyword.split(opts, [:headers])
  end

  ## Helps piping a response into wait_task, as it requires the index
  defp inject_index_into_response({:ok, body}, index) do
    {:ok, Map.put(body, "indexName", index)}
  end

  defp inject_index_into_response(response, _index), do: response
end
