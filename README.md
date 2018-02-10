# Primalize::JSONAPI

This is a JSON-API adapter for the [`primalize` gem](https://github.com/jgaskins/primalize). It aims to provide some level of compatibility with the JSON-API spec while still allowing for the type checking of Primalize.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'primalize-jsonapi'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install primalize-jsonapi

## Usage

```ruby
class OrderSerializer < Primalize::JSONAPI[Order]
  # Notice we no longer need the `id` field. It is assumed.
  attributes(
    customer_name: string,
    delivery_address: primalize(AddressSerializer),
    delivery_instructions: optional(string),
    shipping_carrier: enum(
      'UPS',
      'FedEx',
      'USPS',
      'Creepy white van',
    ),
    subtotal_cents: integer,
    shipping_fee_cents: integer,
    tax_cents: integer,
    total_cents: integer,
  )

  # Associations are similar to other serialization gems, but you need to
  # specify the serializer. There is no runtime inference. We do it inside
  # a block in case it has not been loaded yet.
  has_many(:line_items) { LineItemSerializer }
  has_one(:customer) { CustomerSerializer }
end

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jgaskins/primalize-jsonapi. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Primalize::JSONAPI project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/jgaskins/primalize-jsonapi/blob/master/CODE_OF_CONDUCT.md).
