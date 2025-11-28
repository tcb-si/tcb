# TCB Events

The humble event bus - a simple, thread-safe event bus for Ruby applications using the pub/sub pattern.

## Installation

Add this line to your application's Gemfile:
```ruby
gem 'tcb-events'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install tcb-events

## Usage
```ruby
require 'tcb-events'

# Create an event bus
bus = TCB::EventBus.new

# Define your event classes
UserRegistered = Data.define(:email)

# Subscribe to events
bus.subscribe(UserRegistered) do |event|
  puts "New user registered: #{event.email}"
end

# Publish events
bus.publish(UserRegistered.new("user@example.com"))
```

## Development

After checking out the repo, run `bundle install` to install dependencies. Then, run `rake test` to run the tests.

## Contributing

Bug reports and pull requests are welcome.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
