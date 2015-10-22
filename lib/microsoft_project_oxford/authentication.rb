require 'net/http'
require 'uri'
require 'rest-client'
require 'json'
require_relative '../helpers/tomecast_logger'
class Authentication
  include TomecastLogger


  def initialize(client_id, keys)
    @access_tokens = {}
    @client_id = client_id
    @keys = keys || []

    for key in @keys
      begin
        logger.info('init key:' + key)
        auth_request(key)
      rescue => e
        logger.error("an error occured while init key: #{e}")
        #do nothing, the key will automatically be removed.
      end
    end
  end

  #this function will determine the key to use for a request
  def find_key_for_hash(hash)
    if @keys.empty?
      logger.error "There are no keys left to use. "
      raise 'No keys available'
    end
    ndx = hash % @keys.length
    @keys[ndx]
  end

  #these functions can be used to remove a key, if it has failed due to quota expiry.
  def remove_key_for_hash(hash)
    key = find_key_for_hash(hash)
    remove_key(key)
  end
  def remove_key(key)
    @keys.delete(key)
    @access_tokens.delete(key)
  end

  def get_access_token(hash)
    key = find_key_for_hash(hash)
    access_token = @access_tokens[key]

    if !access_token
      auth_request(key)
    elsif Time.now > access_token[:expires]
      logger.info 'access token has expired. refreshing'
      auth_request(key)
    end
    @access_tokens[key][:token]
  rescue RestClient::Forbidden => e
    #if the request failed with a 403 error code, the key will be removed. retry to use a new key.
    retry
  end

  def auth_request(key)
    attempts_left ||=2

    auth_data = {
        :grant_type=>'client_credentials',
        :client_id=> @client_id,
        :client_secret=> key,
        :scope=> 'https://speech.platform.bing.com'
    }

    res = RestClient.post 'https://oxford-speech.cloudapp.net/token/issueToken', auth_data
    payload = JSON.parse(res.body)
    @access_tokens[key] = {
        :token =>payload['access_token'],
        :expires => Time.now + (payload['expires_in'].to_i - 60) #Set the token expiry time to 1 minute before it actually exipres.
    }
    logger.info 'retrieved access token'


    # will throw an error when failure occurs.
    # https://dev.projectoxford.ai/docs/services/54d85c1d5eefd00dc474a0ef/operations/54f0389249c3f70a50e79b85
    #{ "statusCode": 403, "message": "Out of call volume quota. Quota will be replenished in 21.06:09:16." }
  rescue RestClient::Forbidden => e
    logger.error "This api key has no quota left. We cant use this key any longer."
    remove_key(key)
    raise
  rescue RestClient::InternalServerError,  RestClient::RequestTimeout, RestClient::ServiceUnavailable => e
    if (attempts_left -= 1) > 0
      sleep 2 #sleep two seconds
      logger.warn "Authentication failed, retrying because of Error #{e.http_code}"
      logger.warn e.response
      retry
    else
      logger.error 'No more retries left, stopping.'
    end
  end
end
