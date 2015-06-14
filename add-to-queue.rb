require 'sidekiq'
Sidekiq.configure_server do |config|
  config.redis = { :url => ENV['REDIS_SERVER_URL'] }
end

Sidekiq.configure_client do |config|
  config.redis = { :url => ENV['REDIS_SERVER_URL'] }
end

class SpoutWorker
  include Sidekiq::Worker
end

Sidekiq::Client.enqueue(SpoutWorker, 'Serial', 'Episode 12: What We Know','http://dts.podtrac.com/redirect.mp3/files.serialpodcast.org/sites/default/files/podcast/1433448396/serial-s01-e12.mp3','2014-12-18T10:30:00Z')