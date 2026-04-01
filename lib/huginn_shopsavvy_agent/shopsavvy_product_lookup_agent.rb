module Agents
  class ShopsavvyProductLookupAgent < Agent
    cannot_be_scheduled!
    can_dry_run!

    default_schedule 'every_12h'

    description <<~MD
      The ShopSavvy Product Lookup Agent searches for products or looks up a specific product by identifier (UPC, EAN, ISBN, ASIN, URL, or model number) using the ShopSavvy Data API.

      In **search** mode, it searches for products matching a text query and emits an event for each result.

      In **lookup** mode, it fetches details and current offers for a specific product identifier.

      This agent can also receive events — if an incoming event contains a `query` or `identifier` field, it will use that value instead of the configured one.

      Get your API key at [shopsavvy.com/data](https://shopsavvy.com/data).
    MD

    def default_options
      {
        'api_key' => '',
        'mode' => 'search',
        'query_or_identifier' => '',
        'limit' => '20'
      }
    end

    form_configurable :api_key, type: :password
    form_configurable :mode, type: :array, values: %w[search lookup]
    form_configurable :query_or_identifier
    form_configurable :limit

    def validate_options
      errors.add(:base, 'api_key is required') if options['api_key'].blank?
      errors.add(:base, 'query_or_identifier is required') if options['query_or_identifier'].blank? && !options['receive_events']
      errors.add(:base, 'mode must be search or lookup') unless %w[search lookup].include?(options['mode'])
      if options['limit'].present? && options['limit'].to_i < 1
        errors.add(:base, 'limit must be a positive integer')
      end
    end

    def working?
      checked_without_error? || received_event_without_error?
    end

    def check
      perform_lookup(interpolated['query_or_identifier'])
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        query = event.payload['query'] || event.payload['identifier'] || interpolated['query_or_identifier']
        mode = event.payload['mode'] || interpolated['mode']
        perform_lookup(query, mode: mode)
      end
    end

    private

    def perform_lookup(query, mode: nil)
      mode ||= interpolated['mode']
      client = HuginnShopsavvyAgent::APIClient.new(interpolated['api_key'])

      if mode == 'search'
        limit = (interpolated['limit'] || 20).to_i
        result = client.search_products(query, limit: limit)
        products = result.is_a?(Hash) ? (result['products'] || result['results'] || []) : Array(result)
        products.each do |product|
          create_event payload: product.merge('shopsavvy_mode' => 'search', 'shopsavvy_query' => query)
        end
        log "Searched for '#{query}', found #{products.length} product(s)"
      else
        result = client.get_product(query)
        create_event payload: result.merge('shopsavvy_mode' => 'lookup', 'shopsavvy_identifier' => query)
        log "Looked up product '#{query}'"
      end
    rescue HuginnShopsavvyAgent::APIClient::APIError => e
      error "ShopSavvy API error: #{e.message}"
    rescue StandardError => e
      error "Unexpected error: #{e.message}"
    end
  end
end
