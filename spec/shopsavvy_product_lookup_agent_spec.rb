require 'rails_helper'

describe Agents::ShopsavvyProductLookupAgent do
  before do
    @valid_options = {
      'api_key' => 'test-api-key-123',
      'mode' => 'search',
      'query_or_identifier' => 'sony headphones',
      'limit' => '10'
    }
    @agent = Agents::ShopsavvyProductLookupAgent.new(name: 'Test Product Lookup', options: @valid_options)
    @agent.user = users(:bob)
    @agent.save!
  end

  describe '#validate_options' do
    it 'requires api_key' do
      @agent.options['api_key'] = ''
      expect(@agent).not_to be_valid
    end

    it 'requires mode to be search or lookup' do
      @agent.options['mode'] = 'invalid'
      expect(@agent).not_to be_valid
    end

    it 'requires a positive limit' do
      @agent.options['limit'] = '0'
      expect(@agent).not_to be_valid
    end

    it 'is valid with correct options' do
      expect(@agent).to be_valid
    end
  end

  describe '#check (search mode)' do
    it 'emits events for each product found' do
      mock_client = instance_double(HuginnShopsavvyAgent::APIClient)
      allow(HuginnShopsavvyAgent::APIClient).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:search_products).with('sony headphones', limit: 10).and_return({
        'products' => [
          { 'name' => 'Sony WH-1000XM5', 'upc' => '027242923379', 'price' => 298.00 },
          { 'name' => 'Sony WH-1000XM4', 'upc' => '027242919075', 'price' => 228.00 }
        ]
      })

      expect { @agent.check }.to change { @agent.events.count }.by(2)

      event = @agent.events.last
      expect(event.payload['name']).to eq('Sony WH-1000XM5')
      expect(event.payload['shopsavvy_mode']).to eq('search')
      expect(event.payload['shopsavvy_query']).to eq('sony headphones')
    end
  end

  describe '#check (lookup mode)' do
    before do
      @agent.options['mode'] = 'lookup'
      @agent.options['query_or_identifier'] = '027242923379'
      @agent.save!
    end

    it 'emits a single event for the looked-up product' do
      mock_client = instance_double(HuginnShopsavvyAgent::APIClient)
      allow(HuginnShopsavvyAgent::APIClient).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:get_product).with('027242923379').and_return({
        'name' => 'Sony WH-1000XM5',
        'upc' => '027242923379',
        'price' => 298.00
      })

      expect { @agent.check }.to change { @agent.events.count }.by(1)

      event = @agent.events.last
      expect(event.payload['shopsavvy_mode']).to eq('lookup')
      expect(event.payload['shopsavvy_identifier']).to eq('027242923379')
    end
  end

  describe '#receive' do
    it 'uses the query from the incoming event payload' do
      mock_client = instance_double(HuginnShopsavvyAgent::APIClient)
      allow(HuginnShopsavvyAgent::APIClient).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:search_products).with('bose speakers', limit: 10).and_return({
        'products' => [
          { 'name' => 'Bose SoundLink Flex', 'upc' => '017817835053' }
        ]
      })

      event = Event.new(payload: { 'query' => 'bose speakers' })
      expect { @agent.receive([event]) }.to change { @agent.events.count }.by(1)
    end

    it 'uses identifier from the incoming event to switch to lookup mode' do
      mock_client = instance_double(HuginnShopsavvyAgent::APIClient)
      allow(HuginnShopsavvyAgent::APIClient).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:get_product).with('B0CX23V2ZK').and_return({
        'name' => 'Some Product',
        'asin' => 'B0CX23V2ZK'
      })

      event = Event.new(payload: { 'identifier' => 'B0CX23V2ZK', 'mode' => 'lookup' })
      expect { @agent.receive([event]) }.to change { @agent.events.count }.by(1)
    end
  end

  describe 'error handling' do
    it 'logs API errors without raising' do
      mock_client = instance_double(HuginnShopsavvyAgent::APIClient)
      allow(HuginnShopsavvyAgent::APIClient).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:search_products).and_raise(
        HuginnShopsavvyAgent::APIClient::AuthError.new('Invalid API key')
      )

      expect { @agent.check }.not_to raise_error
      expect(@agent.events.count).to eq(0)
    end
  end
end
