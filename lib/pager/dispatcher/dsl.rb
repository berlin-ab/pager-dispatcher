require 'httparty'
require 'timeout'
require 'active_support/all'
require 'clockwork'
require 'pagerduty'

module Pager
  class Response
    attr_reader :message

    def initialize(message, success: true)
      @message = message
      @success = success
    end

    def success?
      @success
    end
  end

  class UrlChecker
    def initialize(url)
      @url = url
    end

    def check(within:)
      response = do_it within: within
      log response.message
      response
    end

    def do_it(within:)
      Timeout.timeout(within) do
        response = HTTParty.get(@url)

        if response.code == 200
          Response.new "success checking #{@url}"
        else
          Response.new "error on #{@url}", success: false
        end
      end
    rescue SocketError => socket_error
      Response.new "error connecting to #{@url}", success: false
    rescue Timeout::Error => socket_error
      Response.new "timeout error on #{@url}", success: false
    end

    def log(message)
      Clockwork.manager.log message
    end
  end

  class Recipient
    attr_reader :pagerduty_api_key

    def initialize(pagerduty_api_key)
      @pagerduty_api_key = pagerduty_api_key
    end
  end

  class Notifier
    def self.send(recipient, message)
      raise 'missing pager duty service api key' if recipient.pagerduty_api_key.blank?

      pagerduty = Pagerduty.new(recipient.pagerduty_api_key)
      pagerduty.trigger(message, incident_key: message)
    end
  end

  module Dsl
    def notify(pagerduty_api_key)
      @recipient = Recipient.new(pagerduty_api_key)
    end

    def every(number_of_minutes, &block)
      Clockwork.every(number_of_minutes, 'check-url') do
        block.call
      end

      Clockwork.run
    end

    def check_url(url, within: nil)
      response = UrlChecker.new(url).check(
        within: within || 100.minutes
      )

      unless response.success?
        Notifier.send(@recipient, response.message)
      end
    end
  end
end

include Pager::Dsl
