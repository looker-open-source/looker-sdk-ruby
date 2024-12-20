############################################################################################
# The MIT License (MIT)
#
# Copyright (c) 2024 Google, LLC
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
############################################################################################

module LookerSDK
  class Error < StandardError

    # Returns the appropriate LookerSDK::Error subclass based
    # on status and response message
    #
    # @param [Hash] response HTTP response
    # @return [LookerSDK::Error]
    def self.from_response(response)
      status  = response[:status].to_i
      body    = response[:body].to_s
      headers = response[:response_headers]

      if klass =  case status
                  when 400      then LookerSDK::BadRequest
                  when 401      then error_for_401(headers)
                  when 403      then error_for_403(body)
                  when 404      then LookerSDK::NotFound
                  when 405      then LookerSDK::MethodNotAllowed
                  when 406      then LookerSDK::NotAcceptable
                  when 409      then LookerSDK::Conflict
                  when 415      then LookerSDK::UnsupportedMediaType
                  when 422      then LookerSDK::UnprocessableEntity
                  when 429      then LookerSDK::RateLimitExceeded
                  when 400..499 then LookerSDK::ClientError
                  when 500      then LookerSDK::InternalServerError
                  when 501      then LookerSDK::NotImplemented
                  when 502      then LookerSDK::BadGateway
                  when 503      then LookerSDK::ServiceUnavailable
                  when 500..599 then LookerSDK::ServerError
                  end
        klass.new(response)
      end
    end

    def initialize(response=nil)
      @response = response
      super(build_error_message)
    end

    # Documentation URL returned by the API for some errors
    #
    # @return [String]
    def documentation_url
      data[:documentation_url] if data.is_a? Hash
    end

    # Message string returned by the API for some errors
    #
    # @return [String]
    def message
      response_message
    end

    # Looker SDK error objects (e.g. LookerSDK::BadRequest) raise a
    # WebMock::NetConnectNotAllowedError if they are marshal dumped.
    def marshal_dump
      raise TypeError.new("Refusing to marshal")
    end

    # Error Doc URL
    #
    # @return [String]
    def error_doc_url(documentation_url)
      return nil unless documentation_url
      regexp = Regexp.new("https://(?<redirector>docs\.looker\.com\|cloud\.google\.com/looker/docs)/r/err/(?<api_version>.*)/(?<status_code>\\d{3})(?<api_path>.*)", Regexp::IGNORECASE)
      match_data = regexp.match documentation_url
      return nil unless match_data

      key = "#{match_data[:status_code]}#{match_data[:api_path].gsub(/\/:([^\/]+)/,"/{\\1}")}"
      error_doc = error_docs[key] || error_docs[match_data[:status_code]]
      return nil unless error_doc

      return "https://marketplace-api.looker.com/errorcodes/#{error_doc[:url]}"
    end

    def error_docs
      @error_docs ||=
        begin
          sawyer_options = {
            :links_parser => Sawyer::LinkParsers::Simple.new,
            :serializer  => LookerSDK::Client::Serializer.new(JSON),
            :faraday => Faraday.new
          }

          agent = Sawyer::Agent.new("https://marketplace-api.looker.com", sawyer_options) do |http|
            http.headers[:accept] = 'application/json'
            #http.headers[:user_agent] = conn_hash[:user_agent]
          end
          response = agent.call(:get,"/errorcodes/index.json")
          response.data || []
        end
    end

    # Returns most appropriate error for 401 HTTP status code
    # @private
    def self.error_for_401(headers)
      if LookerSDK::OneTimePasswordRequired.required_header(headers)
        LookerSDK::OneTimePasswordRequired
      else
        LookerSDK::Unauthorized
      end
    end

    # Returns most appropriate error for 403 HTTP status code
    # @private
    def self.error_for_403(body)
      if body =~ /rate limit exceeded/i
        LookerSDK::TooManyRequests
      elsif body =~ /login attempts exceeded/i
        LookerSDK::TooManyLoginAttempts
      else
        LookerSDK::Forbidden
      end
    end

    # Array of validation errors
    # @return [Array<Hash>] Error info
    def errors
      if data && data.is_a?(Hash)
        data[:errors] || []
      else
        []
      end
    end

    private

    def data
      @data ||=
        if (body = @response[:body]) && !body.empty?
          if body.is_a?(String) &&
            @response[:response_headers] &&
            @response[:response_headers][:content_type] =~ /json/

            Sawyer::Agent.serializer.decode(body)
          else
            body
          end
        else
          nil
        end
    end

    def response_message
      case data
      when Hash
        data[:message]
      when String
        data
      end
    end

    def response_error
      "Error: #{data[:error]}" if data.is_a?(Hash) && data[:error]
    end

    def response_error_summary
      return nil unless data.is_a?(Hash) && !Array(data[:errors]).empty?

      data[:errors].each do |e|
        edu = error_doc_url(e[:documentation_url])
        e[:error_doc_url] = edu if edu
      end
      summary = "\nError summary:\n"
      summary << data[:errors].map do |hash|
        hash.map { |k,v| "  #{k}: #{v}" }
      end.join("\n")

      summary
    end

    def build_error_message
      return nil if @response.nil?

      message =  "#{@response[:method].to_s.upcase} "
      message << redact_url(@response[:url].to_s) + ": "
      message << "#{@response[:status]} - "
      message << "#{response_message}" unless response_message.nil?
      message << "#{response_error}" unless response_error.nil?
      message << "#{response_error_summary}" unless response_error_summary.nil?
      message << "\n // See: #{documentation_url}" unless documentation_url.nil?
      message << "\n // And: #{error_doc_url(documentation_url)}" unless error_doc_url(documentation_url).nil?
      message
    end

    def redact_url(url_string)
      %w[client_secret access_token].each do |token|
        url_string.gsub!(/#{token}=\S+/, "#{token}=(redacted)") if url_string.include? token
      end
      url_string
    end
  end

  # Raised on errors in the 400-499 range
  class ClientError < Error; end

  # Raised when API returns a 400 HTTP status code
  class BadRequest < ClientError; end

  # Raised when API returns a 401 HTTP status code
  class Unauthorized < ClientError; end

  # Raised when API returns a 401 HTTP status code
  # and headers include "X-Looker-OTP" look TODO do we want to support this?
  class OneTimePasswordRequired < ClientError
    #@private
    OTP_DELIVERY_PATTERN = /required; (\w+)/i

    #@private
    def self.required_header(headers)
      OTP_DELIVERY_PATTERN.match headers['X-Looker-OTP'].to_s
    end

    # Delivery method for the user's OTP
    #
    # @return [String]
    def password_delivery
      @password_delivery ||= delivery_method_from_header
    end

    private

    def delivery_method_from_header
      if match = self.class.required_header(@response[:response_headers])
        match[1]
      end
    end
  end

  # Raised when Looker returns a 403 HTTP status code
  class Forbidden < ClientError; end

  # Raised when Looker returns a 403 HTTP status code
  # and body matches 'rate limit exceeded'
  class TooManyRequests < Forbidden; end

  # Raised when Looker returns a 403 HTTP status code
  # and body matches 'login attempts exceeded'
  class TooManyLoginAttempts < Forbidden; end

  # Raised when Looker returns a 404 HTTP status code
  class NotFound < ClientError; end

  # Raised when Looker returns a 405 HTTP status code
  class MethodNotAllowed < ClientError; end

  # Raised when Looker returns a 406 HTTP status code
  class NotAcceptable < ClientError; end

  # Raised when Looker returns a 409 HTTP status code
  class Conflict < ClientError; end

  # Raised when Looker returns a 414 HTTP status code
  class UnsupportedMediaType < ClientError; end

  # Raised when Looker returns a 422 HTTP status code
  class UnprocessableEntity < ClientError; end

  # Raised when Looker returns a 429 HTTP status code
  class RateLimitExceeded < ClientError; end

  # Raised on errors in the 500-599 range
  class ServerError < Error; end

  # Raised when Looker returns a 500 HTTP status code
  class InternalServerError < ServerError; end

  # Raised when Looker returns a 501 HTTP status code
  class NotImplemented < ServerError; end

  # Raised when Looker returns a 502 HTTP status code
  class BadGateway < ServerError; end

  # Raised when Looker returns a 503 HTTP status code
  class ServiceUnavailable < ServerError; end

  # Raised when client fails to provide valid Content-Type
  class MissingContentType < ArgumentError; end

  # Raised when a method requires an application client_id
  # and secret but none is provided
  class ApplicationCredentialsRequired < StandardError; end
end
