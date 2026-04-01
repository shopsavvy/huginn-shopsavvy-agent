require 'rails_helper'

describe Agents::ShopsavvyDealDiscoveryAgent do
  before do
    @valid_options = {
      'api_key' => 'test-api-key-123',
      'category' => '',
      'min_grade' => '',
      'sort' => 'hot',
      'limit' => '25'
    }
    @agent = Agents::ShopsavvyDealDiscoveryAgent.new(name: 'Test Deal Discovery', options: @valid_options)
    @agent.user = users(:bob)
    @agent.save!
  end

  describe '#validate_options' do
    it 'requires api_key' do
      @agent.options['api_key'] = ''
      expect(@agent).not_to be_valid
    end

    it 'requires valid sort' do
      @agent.options['sort'] = 'invalid'
      expect(@agent).not_to be_valid
    end

    it 'requires positive limit' do
      @agent.options['limit'] = '-1'
      expect(@agent).not_to be_valid
    end

    it 'is valid with defaults' do
      expect(@agent).to be_valid
    end
  end

  describe '#check' do
    let(:mock_client) { instance_double(HuginnShopsavvyAgent::APIClient) }

    before do
      allow(HuginnShopsavvyAgent::APIClient).to receive(:new).and_return(mock_client)
    end

    it 'emits events for new deals' do
      allow(mock_client).to receive(:get_deals).and_return({
        'deals' => [
          { 'path' => '/deals/abc123', 'title' => 'Sony XM5 for $229', 'grade' => 'A', 'votes' => 42 },
          { 'path' => '/deals/def456', 'title' => 'iPad Air $100 off', 'grade' => 'A+', 'votes' => 87 }
        ]
      })

      expect { @agent.check }.to change { @agent.events.count }.by(2)

      event = @agent.events.last
      expect(event.payload['shopsavvy_sort']).to eq('hot')
      expect(event.payload['shopsavvy_discovered_at']).to be_present
    end

    it 'deduplicates deals across checks using memory' do
      allow(mock_client).to receive(:get_deals).and_return({
        'deals' => [
          { 'path' => '/deals/abc123', 'title' => 'Sony XM5 for $229' },
          { 'path' => '/deals/def456', 'title' => 'iPad Air $100 off' }
        ]
      })

      @agent.check
      expect(@agent.events.count).to eq(2)
      expect(@agent.memory['seen_deal_paths']).to include('/deals/abc123', '/deals/def456')

      # Second check with one new deal and one old deal
      allow(mock_client).to receive(:get_deals).and_return({
        'deals' => [
          { 'path' => '/deals/abc123', 'title' => 'Sony XM5 for $229' },
          { 'path' => '/deals/ghi789', 'title' => 'MacBook Pro 30% off' }
        ]
      })

      @agent.check
      expect(@agent.events.count).to eq(3) # only 1 new
      expect(@agent.memory['seen_deal_paths']).to include('/deals/ghi789')
    end

    it 'filters by min_grade when configured' do
      @agent.options['min_grade'] = 'B+'
      @agent.save!

      allow(mock_client).to receive(:get_deals).and_return({
        'deals' => [
          { 'path' => '/deals/1', 'title' => 'Great deal', 'grade' => 'A' },
          { 'path' => '/deals/2', 'title' => 'OK deal', 'grade' => 'C+' },
          { 'path' => '/deals/3', 'title' => 'Good deal', 'grade' => 'B+' }
        ]
      })

      expect { @agent.check }.to change { @agent.events.count }.by(2) # A and B+ pass, C+ does not
    end

    it 'trims seen_deal_paths to prevent unbounded memory growth' do
      @agent.memory['seen_deal_paths'] = (1..5001).map { |i| "/deals/old-#{i}" }

      allow(mock_client).to receive(:get_deals).and_return({
        'deals' => [
          { 'path' => '/deals/new-1', 'title' => 'Fresh deal' }
        ]
      })

      @agent.check

      expect(@agent.memory['seen_deal_paths'].length).to be <= Agents::ShopsavvyDealDiscoveryAgent::SEEN_DEALS_MAX
    end

    it 'handles deals without a path using id as fallback' do
      allow(mock_client).to receive(:get_deals).and_return({
        'deals' => [
          { 'id' => 99001, 'title' => 'Deal with ID only' }
        ]
      })

      expect { @agent.check }.to change { @agent.events.count }.by(1)
      expect(@agent.memory['seen_deal_paths']).to include('99001')
    end

    it 'skips deals with no path or id' do
      allow(mock_client).to receive(:get_deals).and_return({
        'deals' => [
          { 'title' => 'Deal with no identifier at all' }
        ]
      })

      expect { @agent.check }.not_to change { @agent.events.count }
    end

    it 'passes category to the API when configured' do
      @agent.options['category'] = 'electronics'
      @agent.save!

      expect(mock_client).to receive(:get_deals).with(
        sort: 'hot', limit: 25, category: 'electronics'
      ).and_return({ 'deals' => [] })

      @agent.check
    end
  end

  describe 'error handling' do
    it 'logs API errors without raising' do
      mock_client = instance_double(HuginnShopsavvyAgent::APIClient)
      allow(HuginnShopsavvyAgent::APIClient).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:get_deals).and_raise(
        HuginnShopsavvyAgent::APIClient::APIError.new('Server error')
      )

      expect { @agent.check }.not_to raise_error
    end
  end
end
