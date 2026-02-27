require_relative '../helper'


class LookerBodyParamsTest < Minitest::Spec

  def access_token
    '87614b09dd141c22800f96f11737ade5226d7ba8'
  end

  def sdk_client(swagger, engine)
    faraday = Faraday.new do |conn|
      conn.use LookerSDK::Response::RaiseError
      conn.adapter :rack, engine
    end

    LookerSDK.reset!
    LookerSDK::Client.new do |config|
      config.swagger = swagger
      config.access_token = access_token
      config.faraday = faraday
    end
  end

  def default_swagger
    json = <<-JSON
      {
        "swagger": "2.0",
        "basePath": "/api/4.0",
        "paths": {
          "/test_post_urlencoded": {
            "post": {
              "operationId": "test_post_urlencoded",
              "consumes": ["application/x-www-form-urlencoded"],
              "parameters": [
                {
                  "name": "param1",
                  "in": "query",
                  "type": "string"
                },
                {
                  "name": "param2",
                  "in": "query",
                  "type": "string"
                }
              ],
              "responses": {
                "200": { "description": "Success" }
              }
            }
          },
          "/test_post_json": {
            "post": {
              "operationId": "test_post_json",
              "consumes": ["application/json"],
              "parameters": [
                {
                  "name": "param1",
                  "in": "query",
                  "type": "string"
                }
              ],
              "responses": {
                "200": { "description": "Success" }
              }
            }
          },
          "/test_post_default": {
            "post": {
              "operationId": "test_post_default",
              "parameters": [
                {
                  "name": "param1",
                  "in": "query",
                  "type": "string"
                }
              ],
              "responses": {
                "200": { "description": "Success" }
              }
            }
          }
        }
      }
    JSON
    @swagger ||= JSON.parse(json, :symbolize_names => true)
  end

  def verify(response, method, path, expected_body='', expected_query={}, content_type = nil)
    mock = Minitest::Mock.new.expect(:call, response) do |env|
      req = Rack::Request.new(env)
      req_body = req.body&.gets || ''
      
      # Parse body if it's JSON
      begin
        parsed_body = JSON.parse(req_body, :symbolize_names => true)
      rescue JSON::ParserError
        parsed_body = req_body
      end

      # Check method
      method_match = req.request_method == method.to_s.upcase
      
      # Check path
      path_match = req.path_info == path

      # Check query params
      parsed_query = JSON.parse(req.params.to_json, :symbolize_names => true)
      query_match = parsed_query == expected_query
      
      # Check body
      body_match = parsed_body == expected_body
      
      if !body_match
        puts "Body mismatch! Expected: #{expected_body.inspect}, Got: #{parsed_body.inspect}"
      end
      method_match && path_match && query_match && body_match
    end

    
    yield sdk_client(default_swagger, mock)
    mock.verify
  end

  def response
    [200, {'Content-Type' => 'application/json'}, [{}.to_json]]
  end

  describe "Body Params Refactor" do
    it "moves query params to body for POST when consumes is x-www-form-urlencoded" do
      # Expect body to have params, query to be empty
      verify(response, :post, '/api/4.0/test_post_urlencoded', {param1: 'foo', param2: 'bar'}, {}) do |sdk|
        sdk.test_post_urlencoded(nil, param1: 'foo', param2: 'bar')
      end
    end

    it "keeps params in query for POST when consumes is application/json" do
      # Expect body to be empty (or nil), query to have params
      verify(response, :post, '/api/4.0/test_post_json', '', {param1: 'foo'}) do |sdk|
        sdk.test_post_json(nil, param1: 'foo')
      end
    end

    it "keeps params in query for POST when consumes is unspecified" do
      # Expect body to be empty, query to have params
      verify(response, :post, '/api/4.0/test_post_default', '', {param1: 'foo'}) do |sdk|
        sdk.test_post_default(nil, param1: 'foo')
      end
    end
  end
end
