module SparkMotion
  class OAuth2Client
    include BW::KVO

    @@instances = []
    @observed = false
    @@request_retries = 0

    def self.instances
      @@instances ||= []
    end

    def self.first
      self.instances.first
    end

    VALID_OPTION_KEYS = [
      :api_key,
      :api_secret,
      :api_user,
      :endpoint,
      :auth_endpoint,
      :auth_grant_url,
      :callback,
      :user_agent,
      :version,
      :ssl
    ]

    # keys that are usually updated from Spark in order to access their API
    ACCESS_KEYS = [
      :authorization_code,
      :access_token,
      :refresh_token,
      :expires_in
    ]

    attr_accessor *VALID_OPTION_KEYS
    attr_accessor :authorized
    attr_accessor *ACCESS_KEYS

    DEBUGGER = [:d1, :d2]
    attr_accessor *DEBUGGER

    DEFAULT = {
      api_key: "YourAPIKey",
      api_secret: "YourAPISecret",
      api_user: nil,
      callback: "https://sparkplatform.com/oauth2/callback",
      endpoint: "https://developers.sparkapi.com", # change to https://api.developers.sparkapi.com for production
      auth_endpoint: "https://sparkplatform.com/oauth2",  # Ignored for Spark API Auth
      auth_grant_url: "https://api.sparkapi.com/v1/oauth2/grant",
      version: "v1",
      user_agent: "Spark API RubyMotion Gem #{VERSION}",
      ssl: true,

      authorization_code: nil,
      access_token: nil,
      refresh_token: nil,
      expires_in: 0
    }

    X_SPARK_API_USER_AGENT = "X-SparkApi-User-Agent"

    def initialize opts={}
      puts "#{self} initializing..."
      @@instances << self
      (VALID_OPTION_KEYS + ACCESS_KEYS).each do |key|
        send("#{key.to_s}=", opts[key] || DEFAULT[key])
      end
    end

    # Sample Usage:
    # client = SparkMotion::OAuth2Client.new
    # client.configure do |config|
    #   config.api_key      = "YourAPIKey"
    #   config.api_secret   = "YourAPISecret"
    #   config.callback     = "https://sparkplatform.com/oauth2/callback"
    #   config.auth_endpoint = "https://sparkplatform.com/oauth2"
    #   config.endpoint   = 'https://developers.sparkapi.com'
    # end
    def configure
      yield self
      self
    end

    def get_user_permission &block
      # app opens Mobile Safari and waits for a callback?code=<authorization_code>
      # <authorization_code> is then assigned to client.authorization_code

      url = "#{self.auth_endpoint}?response_type=code&client_id=#{self.api_key}&redirect_uri=#{self.callback}"
      UIApplication.sharedApplication.openURL NSURL.URLWithString url

      # AppDelegate#application:handleOpenURL will assign the new authorization code
      unless @observed
        observe(self, "authorization_code") do |old_value, new_value|
          self.authorize &block
          @observed = true
        end
      end

      return
    end

    def authorize &block
      callback = auth_response_handler
      options = {payload: setup_payload, headers: setup_headers}

      block ||= -> { puts "SparkMotion: default callback."}
      BW::HTTP.post(auth_grant_url, options) do |response|
        callback.call response, block
      end
    end

    alias_method :refresh, :authorize

    # Usage:
    # client.get(url, options <Hash>)
    # url<String>
    #   - url without the Spark API endpoint e.g. '/listings', '/my/listings'
    #   - endpoint can be configured in `configure` method
    # options<Hash>
    #   - options used for the query
    #     :payload<String>   - data to pass to a POST, PUT, DELETE query. Additional parameters to
    #     :headers<Hash>     - headers send with the request
    #   - for more info in options, see BW::HTTP.get method in https://github.com/rubymotion/BubbleWrap/blob/master/motion/http.rb
    #
    # Example:
    # if client = SparkMotion::OAuth2Client.new
    #
    # for GET request https://developers.sparkapi.com/v1/listings?_limit=1
    # client.get '/listings', {:payload => {:"_limit" => 1}}
    #
    # for GET request https://developers.sparkapi.com/v1/listings?_limit=1&_filter=PropertyType%20Eq%20'A'
    # client.get '/listings', {:payload => {:_limit => 1, :_filter => "PropertyType Eq 'A'"}}
    def get(spark_url, options={}, &block) # Future TODO: post, put
      # https://<spark_endpoint>/<api version>/<spark resource>
      complete_url = self.endpoint + "/#{version}" + spark_url

      block ||= lambda { |returned|
        puts("SparkMotion: default callback")
      }

      request = lambda {
        # refresh Authorization header every time `request` is called
        headers = {
          :"User-Agent" => "MotionSpark RubyMotion Sample App",
          :"X-SparkApi-User-Agent" => "MotionSpark RubyMotion Sample App",
          :"Authorization" => "OAuth #{self.access_token}"
        }
        opts={:headers => headers}
        opts.merge!(options)

        BW::HTTP.get(complete_url, opts) do |response|
          puts "SparkMotion: [status code #{response.status_code}] [#{spark_url}]"

          response_body = response.body ? response.body.to_str : ""

          if response.status_code == 200
            puts 'SparkMotion: Successful request.'

            @@request_retries = 0
            block.call(response_body)
          elsif @@request_retries > 0
            puts "SparkMotion: retried authorization, but failed."
          elsif @@request_retries == 0
            puts("SparkMotion: [status code #{response.status_code}] - Now retrying to establish authorization...")

            self.authorize do
              puts "SparkMotion: Will now retry the request [#{spark_url}]"

              @@request_retries += 1
              self.get(spark_url, opts, &block)
            end
          end
        end
      }

      if authorized?
        puts "SparkMotion: Requesting [#{spark_url}]"
        request.call
      elsif !authorized?
        puts 'SparkMotion: Authorization required. Falling back to authorization before requesting...'
        # TODO: get user permission first before trying #authorize...
        self.get_user_permission(&request)
      end
    end

    def logout
      self.expires_in = 0
      self.refresh_token = self.access_token = nil
    end

    def authorized?
      self.refresh_token && self.authorized
    end

    private

    # payload common to `authorize` and `refresh`
    def setup_payload
      payload = {
        client_id: self.api_key,
        client_secret:  self.api_secret,
        redirect_uri: self.callback,
      }

      if authorized?
        puts "SparkMotion: Previously authorized. Refreshing tokens..."
        payload[:refresh_token] = self.refresh_token
        payload[:grant_type] = "refresh_token"
      elsif self.authorization_code
        puts "SparkMotion: Seeking authorization..."
        payload[:code] = self.authorization_code
        payload[:grant_type] = "authorization_code"
      end

      payload
    end

    def setup_headers
      # http://sparkplatform.com/docs/api_services/read_first
      # These headers are required when requesting from the API
      # otherwise the request will return an error response.
      headers = {
        :"User-Agent" => "MotionSpark RubyMotion Sample App",
        :"X-SparkApi-User-Agent" => "MotionSpark RubyMotion Sample App"
      }
    end

    def auth_response_handler
      lambda { |response, block|
        response_json = response.body ? response.body.to_str : ""
        response_body = BW::JSON.parse(response_json)
        if response.status_code == 200 # success
          # usual response:
          # {"expires_in":86400,"refresh_token":"bkaj4hxnyrcp4jizv6epmrmin","access_token":"41924s8kb4ot8cy238doi8mbv"}"

          self.access_token = response_body["access_token"]
          self.refresh_token = response_body["refresh_token"]
          self.expires_in = response_body["expires_in"]
          puts "SparkMotion: [status code 200] - Client is now authorized to make requests."

          self.authorized = true

          block.call if block && block.respond_to?(:call)
        else
          # usual response:
          # {"error_description":"The access grant you supplied is invalid","error":"invalid_grant"}

          # TODO: handle error in requests better.
          # - there should be a fallback strategy
          # - try to authorize again? (without going through a loop)
          # - SparkMotion::Error module
          puts "SparkMotion: ERROR [status code #{response.status_code}] - Authorization Unsuccessful - response body: #{response_body["error_description"]}"
          self.authorized = false
        end
      }
    end
  end
end

# handle url from safari to get authorization_code during OAuth2Client#get_user_permission
class AppDelegate
  def application(app, handleOpenURL:url)
    query = url.query_to_hash
    client = SparkMotion::OAuth2Client.first
    client.authorization_code = query["code"]
    return
  end
end

class NSURL
  def query_to_hash
    query_arr = self.query.split(/&|=/)
    query = Hash[*query_arr] # turns [key1,value1,key2,value2] to {key1=>value1, key2=>value2}
  end
end