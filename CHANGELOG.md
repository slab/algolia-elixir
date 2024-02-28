## v0.9.0 (2024-02-28)

This is the first release published under the `algolia_ex` package name.

  * Add support for [push events](https://www.algolia.com/doc/rest-api/insights/#send-events) request
  * Add support for [browse](https://www.algolia.com/doc/rest-api/search/#browse-index-post) request
  * Add `:telemetry` instrumentation to requests and searches
  * Use POST method for search and browse requests
  * **BREAKING**: Use Tesla to make requests instead of Hackney directly. You may need to configure the default Tesla adapter to use something besides the default `:httpc` adapter.
  * **BREAKING**: Add `Algolia.new/1` to create a client, and require passing a client to all API functions. Different clients can use different API keys and application IDs, allowing you to access multiple Algolia applications in the same Elixir app. See the API documentation for more info.

## v0.8.0 (2018-11-17)

  * Allow extra HTTP headers to be passed along Algolia requests
  * Add support for [Delete By](https://www.algolia.com/doc/api-reference/api-methods/delete-by/) request
  * Add support for [Get Logs](https://www.algolia.com/doc/api-reference/api-methods/get-logs/) request
  * Fix docs for default parameter
