require 'logger'
require 'logglier'

module TomecastLogger
  class << self
    def logger
      if(ENV.has_key?('LOGGLY_TOKEN'))
        @logger ||= Logglier.new("https://logs-01.loggly.com/inputs/#{ENV['LOGGLY_TOKEN']}/tag/ruby/", :threaded => true)
      else
        @logger = Logger.new(STDOUT)
      end
    rescue => e
      @logger = Logger.new(STDOUT)
    end

    def logger=(logger)
      @logger = logger
    end
  end

  # Addition
  def self.included(base)
    class << base
      def logger
        TomecastLogger.logger
      end
    end
  end

  def logger
    TomecastLogger.logger
  end
end