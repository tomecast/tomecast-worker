require 'net/http'
require 'uri'
require 'rest-client'
require 'json'
class Authentication

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
      auth_request
    end
    @access_token
  end

  def auth_request
    auth_data = {
        :grant_type=>'client_credentials',
        :client_id=> @client_id,
        :client_secret=> @client_secret,
        :scope=> 'https://speech.platform.bing.com'
    }

    res = RestClient.post 'https://oxford-speech.cloudapp.net/token/issueToken', auth_data
    payload = JSON.parse(res.body)
    @access_token = payload['access_token']
    @expires = Time.now + payload['expires_in'].to_i
  end
end