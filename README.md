# huginn_shopsavvy_agent

Huginn agents for [ShopSavvy](https://shopsavvy.com) price monitoring and deal discovery. Connects your Huginn automation workflows to ShopSavvy's product database of millions of products across thousands of retailers.

## Agents

### ShopSavvy Product Lookup Agent

Search for products by text query or look up a specific product by identifier (UPC, EAN, ISBN, ASIN, URL, or model number).

- **Search mode**: Returns multiple product results for a text query
- **Lookup mode**: Returns details and current offers for a specific product identifier
- **Event-driven**: Can receive events from other agents containing a `query` or `identifier` field
- Default schedule: every 12 hours

### ShopSavvy Price Monitor Agent

Watch a product's price across retailers and get alerted when the price drops.

- **below_threshold**: Alert when price drops below your target price
- **any_drop**: Alert whenever price is lower than the last check
- **both**: Alert on either condition
- Persists last known price between checks using Huginn memory
- Default schedule: every 6 hours

### ShopSavvy Deal Discovery Agent

Discover trending community-sourced deals from ShopSavvy's social deal feed.

- **Deduplication**: Only emits events for deals not previously seen, tracked via Huginn memory
- **Sorting**: Hot (trending), New (latest), or Top (highest voted)
- **Grade filtering**: Optionally filter deals by minimum quality grade (A+, A, B+, etc.)
- **Category filtering**: Optionally filter to a specific product category
- Default schedule: every 2 hours

## Installation

Add this to your Huginn `.env` file:

```
ADDITIONAL_GEMS=huginn_shopsavvy_agent
```

Then run:

```bash
bundle
```

Or, if installing from source:

```
ADDITIONAL_GEMS=huginn_shopsavvy_agent(github: shopsavvy/huginn-shopsavvy-agent)
```

## Configuration

All three agents require a ShopSavvy Data API key. Get yours at [shopsavvy.com/data](https://shopsavvy.com/data).

### Product Lookup Agent

| Option | Description | Default |
|---|---|---|
| `api_key` | Your ShopSavvy Data API key (password field) | *required* |
| `mode` | `search` (text query) or `lookup` (identifier) | `search` |
| `query_or_identifier` | Search text or product identifier (UPC/EAN/ISBN/ASIN/URL) | *required* |
| `limit` | Maximum number of search results | `20` |

### Price Monitor Agent

| Option | Description | Default |
|---|---|---|
| `api_key` | Your ShopSavvy Data API key (password field) | *required* |
| `identifier` | Product identifier to monitor (UPC/EAN/ISBN/ASIN) | *required* |
| `threshold_price` | Target price for below_threshold alerts | *required for threshold modes* |
| `trigger_mode` | `below_threshold`, `any_drop`, or `both` | `below_threshold` |
| `retailer` | Optionally limit to offers from a specific retailer | *empty* |

### Deal Discovery Agent

| Option | Description | Default |
|---|---|---|
| `api_key` | Your ShopSavvy Data API key (password field) | *required* |
| `category` | Filter deals to a specific category | *empty* |
| `min_grade` | Minimum deal grade to emit (e.g., `B+`, `A`) | *empty* |
| `sort` | `hot` (trending), `new` (latest), or `top` (highest voted) | `hot` |
| `limit` | Maximum deals to fetch per check | `25` |

## Example Workflows

### Price Drop Email Alert

1. **ShopSavvy Price Monitor Agent** watches a product with `trigger_mode: below_threshold`
2. **Email Agent** sends you an email when the price drops

### New Deal Slack Notification

1. **ShopSavvy Deal Discovery Agent** finds trending deals with `sort: hot` and `min_grade: B+`
2. **Slack Agent** posts each new deal to a channel

### Product Research Pipeline

1. **Website Agent** or **RSS Agent** detects a product mention
2. **ShopSavvy Product Lookup Agent** receives the event and searches for the product
3. **ShopSavvy Price Monitor Agent** starts tracking the best result

## Development

```bash
git clone https://github.com/shopsavvy/huginn-shopsavvy-agent.git
cd huginn-shopsavvy-agent
bundle install
bundle exec rake spec
```

## License

MIT License. See [LICENSE](LICENSE) for details.

Made by [Monolith Technologies, Inc.](https://shopsavvy.com)
