module Agents
  class ShopsavvyDealDiscoveryAgent < Agent
    cannot_be_scheduled!
    can_dry_run!

    default_schedule 'every_2h'

    description <<~MD
      The ShopSavvy Deal Discovery Agent fetches trending deals from ShopSavvy's social deal feed and emits events for new deals it has not seen before.

      ShopSavvy deals are community-driven — anyone can post a deal, and users vote thumbs up/down. Deals are ranked with a Reddit-like decay algorithm so the hottest recent deals rise to the top.

      The agent tracks which deals it has already emitted using `memory`, so you only get notified about new deals.

      **Sort options:**
      - `hot` — trending deals (votes weighted by recency, default)
      - `new` — newest deals first
      - `top` — highest voted deals

      Get your API key at [shopsavvy.com/data](https://shopsavvy.com/data).
    MD

    # Maximum number of seen deal paths to retain in memory to prevent unbounded growth
    SEEN_DEALS_MAX = 5000

    def default_options
      {
        'api_key' => '',
        'category' => '',
        'min_grade' => '',
        'sort' => 'hot',
        'limit' => '25'
      }
    end

    form_configurable :api_key, type: :password
    form_configurable :category
    form_configurable :min_grade
    form_configurable :sort, type: :array, values: %w[hot new top]
    form_configurable :limit

    def validate_options
      errors.add(:base, 'api_key is required') if options['api_key'].blank?
      errors.add(:base, 'sort must be hot, new, or top') unless %w[hot new top].include?(options['sort'])
      if options['limit'].present? && options['limit'].to_i < 1
        errors.add(:base, 'limit must be a positive integer')
      end
    end

    def working?
      checked_without_error?
    end

    def check
      client = HuginnShopsavvyAgent::APIClient.new(interpolated['api_key'])

      limit = (interpolated['limit'] || 25).to_i
      category = interpolated['category'].presence
      result = client.get_deals(sort: interpolated['sort'], limit: limit, category: category)

      deals = extract_deals(result)
      seen_paths = memory['seen_deal_paths'] || []
      min_grade = interpolated['min_grade'].presence
      new_count = 0

      deals.each do |deal|
        deal_path = deal['path'] || deal['id']&.to_s || deal['url']
        next if deal_path.nil?
        next if seen_paths.include?(deal_path)

        # Filter by minimum grade if configured (e.g., "A", "B+")
        if min_grade && deal['grade']
          next unless grade_meets_minimum?(deal['grade'], min_grade)
        end

        seen_paths << deal_path
        new_count += 1

        create_event payload: deal.merge(
          'shopsavvy_sort' => interpolated['sort'],
          'shopsavvy_discovered_at' => Time.now.iso8601
        )
      end

      # Trim seen_paths to prevent unbounded memory growth
      if seen_paths.length > SEEN_DEALS_MAX
        seen_paths = seen_paths.last(SEEN_DEALS_MAX)
      end

      memory['seen_deal_paths'] = seen_paths
      memory['last_checked_at'] = Time.now.iso8601

      log "Checked deals (sort: #{interpolated['sort']}): #{deals.length} total, #{new_count} new"
    rescue HuginnShopsavvyAgent::APIClient::APIError => e
      error "ShopSavvy API error: #{e.message}"
    rescue StandardError => e
      error "Unexpected error: #{e.message}"
    end

    private

    def extract_deals(result)
      return [] unless result.is_a?(Hash)

      result['deals'] || result['results'] || result.dig('data', 'deals') || []
    end

    # Grade ordering for comparison: A+ > A > A- > B+ > B > B- > C+ > C > ...
    GRADE_ORDER = %w[F D- D D+ C- C C+ B- B B+ A- A A+].freeze

    def grade_meets_minimum?(grade, min_grade)
      grade_idx = GRADE_ORDER.index(grade.to_s.strip.upcase)
      min_idx = GRADE_ORDER.index(min_grade.to_s.strip.upcase)
      return true if grade_idx.nil? || min_idx.nil? # If grade is unrecognized, let it through
      grade_idx >= min_idx
    end
  end
end
