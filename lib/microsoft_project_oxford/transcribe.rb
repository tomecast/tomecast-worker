require 'net/http'
require 'uri'
require 'rest-client'
require 'json'
require 'securerandom'
require_relative 'authentication'
require 'ratelimit'
require_relative '../helpers/tomecast_logger'

# unless ENV['REDIS_SERVER_URL']
#   raise 'Redis Server Url is missing'
# end
unless ENV['SPEECH_API_KEY']
  raise 'Speech API Key is missing'
end

class Transcribe
  include TomecastLogger

  def initialize(segments_folder='segments/', transcriptions_folder='transcripts/')
    @endpoint = 'https://speech.platform.bing.com/recognize'
    @auth = Authentication.new('TomeCast',ENV['SPEECH_API_KEY'])
    @segments_folder = segments_folder
    #@redis = Redis.new(:url => "#{ENV['REDIS_SERVER_URL']}/ratelimit")
  end

  def start()

    #transcribe_ratelimit = Ratelimit.new('transcribe',{:redis =>@redis})

    #loop through the segments, and use the speech api to transcribe them.
    Dir["#{@segments_folder}*"].sort().each do |file_name|
      next if File.directory? file_name

      #generate the output(transcript) filename
      basename = File.basename(file_name,'.wav')
      transcript_file = "transcript/#{basename}.json"


      #p "current requests in the last 3s: #{transcribe_ratelimit.count(ENV['SPEECH_API_KEY'], 3)}"

      #transcribe_ratelimit.exec_within_threshold(ENV['SPEECH_API_KEY'], :threshold => 1, :interval => 3) do
        logger.debug "processing #{file_name}"
        transcribe_request(file_name, transcript_file)
        sleep 2
        #transcribe_ratelimit.add(ENV['SPEECH_API_KEY'])
      #end

    end
  end


  def transcribe_request(segment_file, transcript_file, retries=5)
    attempts_left ||=retries

    #https://www.projectoxford.ai/doc/speech/REST/Recognition
    url_params = {
        :scenarios => 'ulm', #The context for performing a recognition. The supported values are: ulm, websearch
        :appid => 'D4D52672-91D7-4C74-8AD8-42B1D98141A5', #A globally unique identifier used for this application. Always use appID = D4D52672-91D7-4C74-8AD8-42B1D98141A5. Do Not Generate a new GUID. It is unsupported.
        :locale => 'en-US', #Language code of the audio content in IETF RFC 5646. Case does not matter.
        'device.os'=> 'wp7', #Operating system the client is running on. This is an open field but we encourage clients to use be consistent across devices and applications.
        :version => '3.0', #The API version being used by the client. The required value is 3.0
        :format => 'json', #Specifies the desired format of the returned data. The required value is JSON .
        :instanceid => '565D69FF-E928-4B7E-87DA-9A750B96D9E3', #A globally unique device identifier of the device making the request.
        :requestid => SecureRandom.uuid.upcase
    }

    headers = {
        :accept => 'application/json;text/xml',
        :content_type =>'audio/wav; codec=""audio/pcm""; samplerate=16000',
        :authorization => 'Bearer ' + @auth.get_access_token
    }

    segment_audio_file = File.open(segment_file, 'r')
    request_url = "#{@endpoint}?#{encode_url_params(url_params)}"

    #p request_url, segment_audio_file, headers

    res = RestClient.post request_url, segment_audio_file, headers
    #p res.body
    File.open(transcript_file, 'w') { |file| file.write(res.body) }


    #payload will most likely be one of the following payloads:

    #invalid audio/could not detect
    #{"version"=>"3.0", "header"=>{"status"=>"error", "properties"=>{"requestid"=>"9a8413dd-89fb-42e3-997f-0d0969a279e6", "NOSPEECH"=>"1"}}}

    #successfully transcribed audio clip
    #{"version"=>"3.0", "header"=>{"status"=>"success", "scenario"=>"ulm", "name"=>"every time I'm editing me I always think who is this idiot talking and why does he sound so much like me", "lexical"=>"every time i'm editing me i always think who is this idiot talking and why does he sound so much like me", "properties"=>{"requestid"=>"f8e183aa-ed1a-4cf9-b234-d64225a864a1", "HIGHCONF"=>"1"}}, "results"=>[{"scenario"=>"ulm", "name"=>"every time I'm editing me I always think who is this idiot talking and why does he sound so much like me", "lexical"=>"every time i'm editing me i always think who is this idiot talking and why does he sound so much like me", "confidence"=>"0.914633", "properties"=>{"HIGHCONF"=>"1"}}]}

    #rate limit hit
    #this shouldnt happen with the ratelimiting gem.

    #access token key expired.
    #thsi shouldt happen because of the timeout logic in the Authetnication script

  rescue RestClient::InternalServerError, RestClient::Forbidden => e
    if (attempts_left -= 1) > 0
      sleep 2 #sleep two seconds
      logger.warn "Retrying because of Error #{e.http_code}"
      logger.warn e.response
      retry
    else
      logger.fatal 'No more retries left, stopping.'
    end
  else
    logger.debug 'Sucessfully transcribed audio segment'
  end

  def encode_url_params(url_params)
    url_params.map do |key, value|
      "#{CGI.escape(key.to_s)}=#{CGI.escape(value.to_s)}"
    end.join('&')
  end


end

# transcribe = Transcribe.new
# transcribe.transcribe_request('/srv/tomecast-worker/segments/segment-2679.39-19.66.wav')