require 'open-uri'
require 'open3'
require 'fileutils'
require 'sidekiq'
require 'uri'
require 'octokit'

unless ENV['REDIS_SERVER_URL']
  raise 'Redis Server Url is missing'
end

Sidekiq.configure_server do |config|
  config.redis = { :url => ENV['REDIS_SERVER_URL'] }
end

Sidekiq.configure_client do |config|
  config.redis = { :url => ENV['REDIS_SERVER_URL'] }
end

class SpoutWorker
  include Sidekiq::Worker

  def perform(podcast_title, episode_title, episode_url, pubdate, description='')
    unless ENV['SPEECH_API_KEY']
      raise 'Speech API Key is missing'
    end

    unless ENV['GITHUB_API_KEY']
      raise 'Github API Key is missing'
    end

    #prepare environment
    cleanup_temp_folders
    compile_speech_transcriber

    #download podcast
    uri = URI.parse(episode_url)
    episode_filename = File.basename(uri.path)
    download_podcast(episode_url, episode_filename)

    #process podcast
    responses = process_podcast(episode_filename)

    #generate segments
    segments = generate_segments(responses)
    transcript = {
        'title' => episode_title,
        'date' => DateTime.rfc3339(pubdate).strftime('%F'),
        'description' => description,
        'episode_url' => episode_url,
        'segments' => segments
    }
    store_transcript_in_github(podcast_title,transcript)

  end

  def cleanup_temp_folders()
    #clear up temp folders
    FileUtils.rm_rf Dir.glob("transcript/*")
    FileUtils.rm_rf Dir.glob("segments/*")
    FileUtils.rm_rf Dir.glob("podcast/*")
  end

  def compile_speech_transcriber()
    ### Compile SpeechSDK Transcriber
    command = "mcs /reference:System.ServiceModel.dll /reference:System.Runtime.Serialization /reference:System.Web -r:SpeechSDK/x64/SpeechClient.dll Program.cs"

    Open3.popen3(command,:chdir=>'transcribe') do |stdin, out, err, external|
      # Create a thread to read from each stream
      { :stdout => out, :stderr => err }.each do |key, stream|
        puts "redirecting #{key.to_s}"
        Thread.new do
          until (line = stream.gets).nil? do
            puts "#{key} --> #{line}"
          end
        end
      end

      # Don't exit until the external process is done
      external.join
      if external.value.success?
        puts 'successfully compiled transcriber'
      else
        raise 'compile failed.'
      end
    end
  end

  def download_podcast(episode_url, episode_filename)
    File.open("podcast/#{episode_filename}", "wb") do |saved_file|
      # the following "open" is provided by open-uri
      open(episode_url, "rb") do |read_file|
        saved_file.write(read_file.read)
      end
    end
  end

  def process_podcast(episode_filename)
    # spliting the podcast into 10s clips with single channel audio and 16000 sample rate
    command = "sox podcast/#{episode_filename} -c 1 -r 16000 segments/segment.wav trim 0 10 : newfile : restart "

    Open3.popen3(command) do |stdin, out, err, external|
      # Create a thread to read from each stream
      { :stdout => out, :stderr => err }.each do |key, stream|
        puts "redirecting #{key.to_s}"
        Thread.new do
          until (line = stream.gets).nil? do
            puts "#{key} --> #{line}"
          end
        end
      end

      # Don't exit until the external process is done
      external.join
      if external.value.success?
        puts 'successfully split files'
      else
        raise 'splitting files caused an error.'
      end

    end

    responses = []

    #loop through the segments, and use the speech api to transcribe them.
    Dir['segments/*'].sort().each do |file_name|
      next if File.directory? file_name

      #get the index from the filename.
      index = File.basename(file_name,File.extname(file_name))[7..-1].to_i
      index = index -1

      command = "mono transcribe/Program.exe 'https://speech.platform.bing.com/recognize' '#{file_name}' '#{ENV['SPEECH_API_KEY']}'"
      Open3.popen3(command) do |stdin, out, err, external|
        # Create a thread to read from each stream
        { :stdout => out, :stderr => err }.each do |key, stream|
          puts "redirecting #{key.to_s}"
          Thread.new do
            until (line = stream.gets).nil? do
              puts "#{key} --> #{line}"

              if(key == :stdout)
                responses.insert(index, line)
              end
            end
          end
        end
        # Don't exit until the external process is done
        external.join
        if external.value.success?
          puts 'successfully transcribed file'
        else
          #errors here are not catastrophic
          puts 'an error occured while transcribing file'
        end
      end
    end
    return responses
  end

  def generate_segments(responses)
    ## merge the response segments into a coherent transcript
    segments = {}
    require 'json'
    responses.each_with_index do |response, index|
      next unless response
      segment = JSON.parse(response)
      next unless segment
      if segment['header']['status'] == 'error'
        segments[index*10] = {
            'requestid' => segment['header']['properties']['requestid'],
            'timestamp' => index*10,
            'content' => ''
        }
      else
        segments[index*10] = {
            'requestid' => segment['header']['properties']['requestid'],
            'confidence' => segment['results'][0]['confidence'],
            'timestamp' => index*10,
            'content' => segment['results'][0]['name']
        }
      end

    end
    return segments
  end

  def store_transcript_in_github(podcast_title,transcript)
    #write the file in github to a new branch.
    client = Octokit::Client.new(:access_token => ENV['GITHUB_API_KEY'])
    #get the master branch sha.
    master_resource = client.ref('tomecast/spout-podcasts', 'heads/master')

    #create a new branchname, ensure its safe.
    branchname = podcast_title + ' - ' + transcript['title']
    # Strip out the non-ascii characters and path delimiteres
    branchname = cleaned_string(branchname)

    client.create_ref('tomecast/spout-podcasts', 'heads/'+branchname, master_resource[:object][:sha])

    client.create_contents('tomecast/spout-podcasts',
                            "#{podcast_title}/#{(DateTime.rfc3339(transcript['date']).strftime('%F')+'-'+cleaned_string(transcript['title'], '-')).downcase}.json",
                            'Added new episode',
                            JSON.pretty_generate(transcript),
                           :branch => branchname)

    client.create_pull_request('tomecast/spout-podcasts', 'master', branchname,
                               "Added new #{podcast_title} episode")

  end

  #################################################################################################
  # Utilities
  def cleaned_string(raw, delim='_')
    raw.gsub(/^.*(\\|\/)/, '').gsub(/[^0-9A-Za-z.\-]/, delim)
  end
end
