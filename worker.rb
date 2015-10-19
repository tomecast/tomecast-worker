require 'open-uri'
require 'open3'
require 'fileutils'
require 'sidekiq'
require 'uri'
require 'octokit'
require_relative 'processor'
require_relative 'lib/helpers/tomecast_logger'

unless ENV['REDIS_SERVER_URL']
  raise 'Redis Server Url is missing'
end
unless ENV['SPEECH_API_KEY']
  raise 'Speech API Key is missing'
end
unless ENV['GITHUB_API_KEY']
  raise 'Github API Key is missing'
end

Sidekiq.configure_server do |config|
  config.redis = { :url => ENV['REDIS_SERVER_URL'] }
end

Sidekiq.configure_client do |config|
  config.redis = { :url => ENV['REDIS_SERVER_URL'] }
end

class SpoutWorker
  include Sidekiq::Worker
  include TomecastLogger

  def perform(podcast_title, episode_title, episode_url, pubdate, description='')

    #TODO: change this code so that it actually processes each job subfolder set (ie there could be multiple sidekiq workers running.)
    logger.info 'prepare environment'
    cleanup_temp_folders

    logger.info 'download podcast'
    uri = URI.parse(episode_url)
    episode_filename = File.basename(uri.path)
    download_podcast(episode_url, episode_filename)

    logger.info 'begin process podcast'
    processor = Processor.new("podcast/#{episode_filename}", {
      :episode_title => episode_title,
      :podcast_title => podcast_title,
      :episode_url => episode_url,
      :pubdate => pubdate,
      :description => description
    })
    transcript = processor.start()

    logger.info 'store transcript in github'
    store_transcript_in_github(podcast_title,transcript)

  rescue => e
    logger.error "podcast worker failed for #{podcast_title} - #{episode_title}"
    logger.error e.message + "\n " + e.backtrace.join("\n ")
    raise
  end

  def cleanup_temp_folders()
    logger.debug 'clear up temp folders'
    FileUtils.rm_rf Dir.glob("transcript/*")
    FileUtils.rm_rf Dir.glob("segments/*")
    FileUtils.rm_rf Dir.glob("podcast/*")
  end

  def download_podcast(episode_url, episode_filename)
    File.open("podcast/#{episode_filename}", "wb") do |saved_file|
      # the following "open" is provided by open-uri
      open(episode_url, "rb") do |read_file|
        saved_file.write(read_file.read)
      end
    end
  end

  def store_transcript_in_github(podcast_title,transcript)
    #write the file in github to a new branch.
    client = Octokit::Client.new(:access_token => ENV['GITHUB_API_KEY'])

    #write directly to the master branch.
    client.create_contents('tomecast/tomecast-podcasts',
                            "#{podcast_title}/#{cleaned_string(transcript['date'] +' '+ transcript['title'], ' ')}.json",
                            "Added new #{podcast_title} episode",
                            JSON.pretty_generate(transcript),
                           :branch => 'master')


  end

  #################################################################################################
  # Utilities
  def cleaned_string(raw, delim='_')
    raw.gsub(/^.*(\\|\/)/, '').gsub(/[^0-9A-Za-z.\-]/, delim)
  end
end
