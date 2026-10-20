require "action_cable/subscription_adapter/async"
require "action_cable/subscription_adapter/solid_cable"
require "securerandom"

module ActionCable
  module SubscriptionAdapter
    # Solid Cable delivers by polling the database (every 100 ms in
    # config/cable.yml). That is fine for messages from background jobs, but
    # it adds up to 100 ms to live positions, whose sender (the driver's
    # socket) and receivers (the customer's and dispatcher's sockets) sit in
    # the same web process.
    #
    # LocalFirst delivers to subscribers in this process at once and still
    # writes every message to Solid Cable for the other processes. Each
    # message is tagged with its origin, and a process drops its own messages
    # when they come back from the database, so nothing arrives twice.
    #
    #   config/cable.yml:  adapter: local_first   (Solid Cable settings unchanged)
    class LocalFirst < Base
      TAG = /\A\d+\.\h{8}\|/

      def initialize(server, local: nil, remote: nil)
        super(server)
        @origin = "#{Process.pid}.#{SecureRandom.hex(4)}|"
        @local = local || Async.new(server)
        @remote = remote || SolidCable.new(server)
        @remote_callbacks = Concurrent::Map.new
      end

      def broadcast(channel, payload)
        @local.broadcast(channel, payload)
        @remote.broadcast(channel, @origin + payload)
      end

      # The subscription is confirmed as soon as the local side is ready; the
      # remote side only carries messages from other processes.
      def subscribe(channel, callback, success_callback = nil)
        @local.subscribe(channel, callback, success_callback)
        @remote.subscribe(channel, remote_callback(channel, callback))
      end

      def unsubscribe(channel, callback)
        @local.unsubscribe(channel, callback)
        if (wrapper = @remote_callbacks.delete([ channel, callback ]))
          @remote.unsubscribe(channel, wrapper)
        end
      end

      def shutdown
        @local.shutdown
        @remote.shutdown
      end

      private
        def remote_callback(channel, callback)
          @remote_callbacks.compute_if_absent([ channel, callback ]) do
            lambda do |message|
              next if message.start_with?(@origin) # ours: already delivered locally

              callback.call(message.sub(TAG, ""))
            end
          end
        end
    end
  end
end
