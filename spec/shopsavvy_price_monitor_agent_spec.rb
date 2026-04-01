require 'rails_helper'

describe Agents::ShopsavvyPriceMonitorAgent do
  before do
    @valid_options = {
      'api_key' => 'test-api-key-123',
      'identifier' => '027242923379',
      'threshold_price' => '250.00',
      'trigger_mode' => 'below_threshold',
      'retailer' => ''
    }
    @agent = Agents::ShopsavvyPriceMonitorAgent.new(name: 'Test Price Monitor', options: @valid_options)
    @agent.user = users(:bob)
    @agent.save!
  end

  describe '#validate_options' do
    it 'requires api_key' do
      @agent.options['api_key'] = ''
      expect(@agent).not_to be_valid
    end

    it 'requires identifier' do
      @agent.options['identifier'] = ''
      expect(@agent).not_to be_valid
    end

    it 'requires threshold_price when trigger_mode is below_threshold' do
      @agent.options['threshold_price'] = ''
      expect(@agent).not_to be_valid
    end

    it 'does not require threshold_price when trigger_mode is any_drop' do
      @agent.options['trigger_mode'] = 'any_drop'
      @agent.options['threshold_price'] = ''
      expect(@agent).to be_valid
    end

    it 'requires valid trigger_mode' do
      @agent.options['trigger_mode'] = 'invalid'
      expect(@agent).not_to be_valid
    end
  end

  describe '#check' do
    let(:mock_client) { instance_double(HuginnShopsavvyAgent::APIClient) }

    before do
      allow(HuginnShopsavvyAgent::APIClient).to receive(:new).and_return(mock_client)
    end

    context 'when price is below threshold' do
      it 'emits a price alert event' do
        allow(mock_client).to receive(:get_current_offers).and_return({
          'offers' => [
            { 'retailer' => 'Amazon', 'price' => 229.99, 'url' => 'https://amazon.com/dp/...' },
            { 'retailer' => 'Best Buy', 'price' => 269.99, 'url' => 'https://bestbuy.com/...' }
          ]
        })

        expect { @agent.check }.to change { @agent.events.count }.by(1)

        event = @agent.events.last
        expect(event.payload['current_price']).to eq(229.99)
        expect(event.payload['trigger_reasons']).to include(a_string_matching(/below threshold/))
      end
    end

    context 'when price is above threshold' do
      it 'does not emit an event' do
        allow(mock_client).to receive(:get_current_offers).and_return({
          'offers' => [
            { 'retailer' => 'Amazon', 'price' => 298.00 }
          ]
        })

        expect { @agent.check }.not_to change { @agent.events.count }
      end
    end

    context 'with any_drop trigger mode' do
      before do
        @agent.options['trigger_mode'] = 'any_drop'
        @agent.options['threshold_price'] = ''
        @agent.save!
      end

      it 'emits when price drops from last check' do
        @agent.memory['last_lowest_price'] = 300.00

        allow(mock_client).to receive(:get_current_offers).and_return({
          'offers' => [{ 'retailer' => 'Amazon', 'price' => 279.99 }]
        })

        expect { @agent.check }.to change { @agent.events.count }.by(1)

        event = @agent.events.last
        expect(event.payload['current_price']).to eq(279.99)
        expect(event.payload['previous_price']).to eq(300.00)
        expect(event.payload['trigger_reasons']).to include(a_string_matching(/dropped/))
      end

      it 'does not emit when price stays the same' do
        @agent.memory['last_lowest_price'] = 279.99

        allow(mock_client).to receive(:get_current_offers).and_return({
          'offers' => [{ 'retailer' => 'Amazon', 'price' => 279.99 }]
        })

        expect { @agent.check }.not_to change { @agent.events.count }
      end

      it 'does not emit on first check (no previous price)' do
        allow(mock_client).to receive(:get_current_offers).and_return({
          'offers' => [{ 'retailer' => 'Amazon', 'price' => 279.99 }]
        })

        expect { @agent.check }.not_to change { @agent.events.count }
        expect(@agent.memory['last_lowest_price']).to eq(279.99)
      end
    end

    context 'when no offers are returned' do
      it 'does not emit an event and logs' do
        allow(mock_client).to receive(:get_current_offers).and_return({
          'offers' => []
        })

        expect { @agent.check }.not_to change { @agent.events.count }
      end
    end

    it 'persists the last lowest price in memory' do
      allow(mock_client).to receive(:get_current_offers).and_return({
        'offers' => [
          { 'retailer' => 'Amazon', 'price' => 265.00 },
          { 'retailer' => 'Walmart', 'price' => 259.50 }
        ]
      })

      @agent.check
      expect(@agent.memory['last_lowest_price']).to eq(259.50)
      expect(@agent.memory['offer_count']).to eq(2)
    end
  end

  describe 'error handling' do
    it 'logs rate limit errors without raising' do
      mock_client = instance_double(HuginnShopsavvyAgent::APIClient)
      allow(HuginnShopsavvyAgent::APIClient).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:get_current_offers).and_raise(
        HuginnShopsavvyAgent::APIClient::RateLimitError.new('Too many requests')
      )

      expect { @agent.check }.not_to raise_error
    end
  end
end
