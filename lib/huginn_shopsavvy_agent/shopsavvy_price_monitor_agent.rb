module Agents
  class ShopsavvyPriceMonitorAgent < Agent
    cannot_be_scheduled!
    can_dry_run!

    default_schedule 'every_6h'

    description <<~MD
      The ShopSavvy Price Monitor Agent watches a product's price across retailers and emits an event when the price drops below a threshold or changes significantly.

      It uses `memory` to persist the last known lowest price between checks, so it only fires when there is an actual change.

      **Trigger modes:**
      - `below_threshold` — emit when the lowest offer price drops below your configured threshold price
      - `any_drop` — emit whenever the lowest price is lower than the last check
      - `both` — emit on either condition

      Get your API key at [shopsavvy.com/data](https://shopsavvy.com/data).
    MD

    def default_options
      {
        'api_key' => '',
        'identifier' => '',
        'threshold_price' => '',
        'trigger_mode' => 'below_threshold',
        'retailer' => ''
      }
    end

    form_configurable :api_key, type: :password
    form_configurable :identifier
    form_configurable :threshold_price
    form_configurable :trigger_mode, type: :array, values: %w[below_threshold any_drop both]
    form_configurable :retailer

    def validate_options
      errors.add(:base, 'api_key is required') if options['api_key'].blank?
      errors.add(:base, 'identifier is required') if options['identifier'].blank?
      unless %w[below_threshold any_drop both].include?(options['trigger_mode'])
        errors.add(:base, 'trigger_mode must be below_threshold, any_drop, or both')
      end
      if options['trigger_mode'] != 'any_drop' && options['threshold_price'].blank?
        errors.add(:base, 'threshold_price is required when trigger_mode includes threshold')
      end
    end

    def working?
      checked_without_error?
    end

    def check
      client = HuginnShopsavvyAgent::APIClient.new(interpolated['api_key'])
      retailer = interpolated['retailer'].presence

      result = client.get_current_offers(interpolated['identifier'], retailer: retailer)
      offers = extract_offers(result)

      if offers.empty?
        log "No offers found for '#{interpolated['identifier']}'"
        return
      end

      lowest_offer = offers.min_by { |o| o['price'].to_f }
      current_price = lowest_offer['price'].to_f
      last_price = memory['last_lowest_price']&.to_f
      threshold = interpolated['threshold_price'].to_f

      triggered = false
      reasons = []

      trigger_mode = interpolated['trigger_mode']

      if %w[below_threshold both].include?(trigger_mode) && threshold > 0 && current_price <= threshold
        triggered = true
        reasons << "price $#{'%.2f' % current_price} is at or below threshold $#{'%.2f' % threshold}"
      end

      if %w[any_drop both].include?(trigger_mode) && last_price && current_price < last_price
        triggered = true
        reasons << "price dropped from $#{'%.2f' % last_price} to $#{'%.2f' % current_price}"
      end

      memory['last_lowest_price'] = current_price
      memory['last_checked_at'] = Time.now.iso8601
      memory['offer_count'] = offers.length

      if triggered
        create_event payload: {
          'identifier' => interpolated['identifier'],
          'current_price' => current_price,
          'previous_price' => last_price,
          'threshold_price' => threshold,
          'trigger_reasons' => reasons,
          'lowest_offer' => lowest_offer,
          'total_offers' => offers.length,
          'checked_at' => Time.now.iso8601
        }
        log "Price alert triggered for '#{interpolated['identifier']}': #{reasons.join('; ')}"
      else
        log "No price alert for '#{interpolated['identifier']}' — current lowest: $#{'%.2f' % current_price}"
      end
    rescue HuginnShopsavvyAgent::APIClient::APIError => e
      error "ShopSavvy API error: #{e.message}"
    rescue StandardError => e
      error "Unexpected error: #{e.message}"
    end

    private

    def extract_offers(result)
      return [] unless result.is_a?(Hash)

      # The API may return offers nested under various keys
      result['offers'] || result['results'] || result.dig('data', 'offers') || []
    end
  end
end
