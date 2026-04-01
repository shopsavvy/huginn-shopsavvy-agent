require 'faraday'

module HuginnShopsavvyAgent
  class APIClient
    BASE_URL = 'https://api.shopsavvy.com/v1'.freeze

    def initialize(api_key)
      @conn = Faraday.new(url: BASE_URL, headers: {
        'Authorization' => "Bearer #{api_key}",
        'User-Agent' => 'ShopSavvy-Huginn-Agent/1.0.0'
      }) do |f|
        f.request :json
        f.response :json
        f.adapter Faraday.default_adapter
      end
    end

    def search_products(query, limit: 20)
      get('products/search', q: query, limit: limit)
    end

    def get_product(identifier)
      get("products/#{identifier}")
    end

    def get_current_offers(identifier, retailer: nil)
      params = { ids: identifier }
      params[:retailer] = retailer if retailer
      get('products/offers', params)
    end

    def get_deals(sort: 'hot', limit: 25, category: nil)
      params = { sort: sort, limit: limit }
      params[:category] = category if category
      get('deals', params)
    end

    private

    def get(path, params = {})
      response = @conn.get(path, params)
      case response.status
      when 200..299 then response.body
      when 401 then raise AuthError, "Authentication failed: #{error_message(response)}"
      when 429 then raise RateLimitError, "Rate limit exceeded: #{error_message(response)}"
      else raise APIError, "API error #{response.status}: #{error_message(response)}"
      end
    end

    def error_message(response)
      if response.body.is_a?(Hash)
        response.body['error'] || response.body['message'] || response.body.to_s
      else
        response.body.to_s
      end
    end

    class APIError < StandardError; end
    class AuthError < APIError; end
    class RateLimitError < APIError; end
  end
end
