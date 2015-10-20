require 'net/http'
require 'uri'
require 'rest-client'
require 'json'
require_relative '../helpers/tomecast_logger'
class Authentication
  include TomecastLogger

  @access_token = nil
  @expires = nil

  def initialize(client_id, client_secret)
    @client_id = client_id
    @client_secret = client_secret

    auth_request
  end

  def get_access_token

    if !@access_token
      auth_request
    elsif Time.now > @expires
      logger.debug 'access token has expired. refreshing'
      auth_request
    end
    @access_token
  end

  def auth_request
    attempts_left ||=2

    auth_data = {
        :grant_type=>'client_credentials',
        :client_id=> @client_id,
        :client_secret=> @client_secret,
        :scope=> 'https://speech.platform.bing.com'
    }

    res = RestClient.post 'https://oxford-speech.cloudapp.net/token/issueToken', auth_data
    payload = JSON.parse(res.body)
    @access_token = payload['access_token']
    @expires = Time.now + (payload['expires_in'].to_i - 60) #Set the token expiry time to 1 minute before it actually exipres.
    logger.debug 'retrieved access token'


    # will throw an error when failure occurs.
    # https://dev.projectoxford.ai/docs/services/54d85c1d5eefd00dc474a0ef/operations/54f0389249c3f70a50e79b85
    #{ "statusCode": 403, "message": "Out of call volume quota. Quota will be replenished in 21.06:09:16." }
  rescue RestClient::Forbidden => e
    logger.error "This api key has no quota left. We cant use this key anylonger. TODO: support multiple keys. \n#{e.http_code}\n#{e.response}"

  rescue RestClient::InternalServerError,  RestClient::RequestTimeout, RestClient::ServiceUnavailable => e
    if (attempts_left -= 1) > 0
      sleep 2 #sleep two seconds
      logger.warn "Authentication failed, retrying because of Error #{e.http_code}"
      logger.warn e.response
      retry
    else
      logger.error 'No more retries left, stopping.'
    end
  else
    logger.debug 'Sucessfully retrieved api token'
  end
end
