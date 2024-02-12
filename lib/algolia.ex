defmodule Algolia do
  @moduledoc """
  Elixir implementation of Algolia search API
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

  def application_id do
    System.get_env("ALGOLIA_APPLICATION_ID") || Application.get_env(:algolia, :application_id) ||
      raise MissingApplicationIDError
  end

  def api_key do
    System.get_env("ALGOLIA_API_KEY") || Application.get_env(:algolia, :api_key) ||
      raise MissingAPIKeyError
  end

  @type client() :: Tesla.Client.t()
  @type index() :: String.t()
  @type request_option() :: {:headers, Tesla.Env.headers()}
  @type result(resp) :: {:ok, resp} | {:error, any()}

  @doc """
  Create a new Algolia client.
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
  Multiple queries
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
  Search a single index
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
  Search for facet values

  Enables you to search through the values of a facet attribute, selecting
  only a **subset of those values that meet a given criteria**.

  For a facet attribute to be searchable, it must have been declared in the
  `attributesForFaceting` index setting with the `searchable` modifier.

  Facet-searching only affects facet values. It does not impact the underlying
  index search.

  The results are **sorted by decreasing count**. This can be adjusted via
  `sortFacetValuesBy`.

  By default, maximum **10 results are returned**. This can be adjusted via
  `maxFacetHits`.

  ## Examples

      iex> Algolia.search_for_facet_values("species", "phylum", "dophyta")
      {
        :ok,
        %{
          "exhaustiveFacetsCount" => false,
          "faceHits" => [
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
          "processingTimeMS" => 42
        }
      }
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
  Browse a single index
  """
  @spec browse(client(), index(), [request_option()]) :: result(map())
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
  Get an object in an index by objectID
  """
  @spec get_object(client(), index(), String.t(), [request_option()]) :: result(map())
  def get_object(client, index, object_id, opts \\ []) do
    path = Paths.object(index, object_id)

    client
    |> send_request(:read, %{method: :get, path: path, options: opts})
    |> inject_index_into_response(index)
  end

  @doc """
  Add an Object

  An attribute can be chosen as the objectID.
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
  Add multiple objects

  An attribute can be chosen as the objectID.
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
  Save a single object, without objectID specified, must have objectID as
  a field
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
  Save multiple objects
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
  Partially updates an object, takes option upsert: true or false
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
  Partially updates multiple objects
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
  Delete a object by its objectID
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
  Delete multiple objects
  """
  @spec delete_objects(client(), index(), [String.t()], [request_option()]) :: result(map())
  def delete_objects(client, index, object_ids, opts \\ []) do
    object_ids
    |> Enum.map(fn id -> %{objectID: id} end)
    |> build_batch_request("deleteObject")
    |> send_batch_request(client, index, opts)
  end

  @doc """
  Remove all objects matching a filter (including geo filters).

  Allowed filter parameters:

  * `filters`
  * `facetFilters`
  * `numericFilters`
  * `aroundLatLng` and `aroundRadius` (these two need to be used together)
  * `insideBoundingBox`
  * `insidePolygon`

  ## Examples

      iex> Algolia.delete_by("index", filters: ["score < 30"])
      {:ok, %{"indexName" => "index", "taskId" => 42, "deletedAt" => "2018-10-30T15:33:13.556Z"}}
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
  List all indexes
  """
  @spec list_indexes(client(), [request_option()]) :: result(map())
  def list_indexes(client, opts \\ []) do
    send_request(client, :read, %{method: :get, path: Paths.indexes(), options: opts})
  end

  @doc """
  Deletes the index
  """
  @spec delete_index(client(), index(), [request_option()]) :: result(map())
  def delete_index(client, index, opts \\ []) do
    client
    |> send_request(:write, %{method: :delete, path: Paths.index(index), options: opts})
    |> inject_index_into_response(index)
  end

  @doc """
  Clears all content of an index
  """
  @spec clear_index(client(), index(), [request_option()]) :: result(map())
  def clear_index(client, index, opts \\ []) do
    client
    |> send_request(:write, %{method: :post, path: Paths.clear(index), options: opts})
    |> inject_index_into_response(index)
  end

  @doc """
  Set the settings of a index
  """
  @spec set_settings(client(), index(), map(), [request_option()]) :: result(map())
  def set_settings(client, index, settings, opts \\ []) do
    path = Paths.settings(index)

    client
    |> send_request(:write, %{method: :put, path: path, body: settings, options: opts})
    |> inject_index_into_response(index)
  end

  @doc """
  Get the settings of a index
  """
  @spec get_settings(client(), index(), [request_option()]) :: result(map())
  def get_settings(client, index, opts \\ []) do
    client
    |> send_request(:read, %{method: :get, path: Paths.settings(index), options: opts})
    |> inject_index_into_response(index)
  end

  @doc """
  Moves an index to new one
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
  Copies an index to a new one
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
  Get the logs of the latest search and indexing operations.

  ## Options

    * `:indexName` - Index for which log entries should be retrieved. When omitted,
      log entries are retrieved across all indices.

    * `:length` - Maximum number of entries to retrieve. Maximum allowed value: 1000.

    * `:offset` - First entry to retrieve (zero-based). Log entries are sorted by
      decreasing date, therefore 0 designates the most recent log entry.

    * `:type` - Type of log to retrieve: `all` (default), `query`, `build` or `error`.
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
  Wait for a task for an index to complete
  returns :ok when it's done
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
  Convinient version of wait_task/4, accepts a response to be waited on
  directly. This enables piping a operation directly into wait_task
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
  Push events to the Insights REST API.
  Corresponds to https://www.algolia.com/doc/rest-api/insights/#push-events
  `events` should be a List of Maps, each Map having the fields described in the link above
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
