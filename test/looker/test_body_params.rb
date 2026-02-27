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
          "/test_post_query": {
            "post": {
              "operationId": "test_post_query",
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
                "200": {
                  "description": "Success"
                }
              }
            }
          },
          "/test_post_body": {
            "post": {
              "operationId": "test_post_body",
              "parameters": [
                {
                  "name": "body",
                  "in": "body",
                  "required": true,
                  "schema": {
                    "type": "object"
                  }
                }
              ],
              "responses": {
                "200": {
                  "description": "Success"
                }
              }
            }
          },
          "/test_get_query": {
            "get": {
              "operationId": "test_get_query",
              "parameters": [
                {
                  "name": "param1",
                  "in": "query",
                  "type": "string"
                }
              ],
              "responses": {
                "200": {
                  "description": "Success"
                }
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
    it "moves query params to body for POST when no body param is defined" do
      # We expect the query to be EMPTY and the body to contain param1 and param2
      verify(response, :post, '/api/4.0/test_post_query', {param1: 'foo', param2: 'bar'}, {}) do |sdk|
        # Calling with nil body and params in options (legacy pattern for no-body methods)
        sdk.test_post_query(nil, param1: 'foo', param2: 'bar')
      end
    end

    it "keeps params in body for POST when body param IS defined" do
      # Normal behavior: payload goes to body, options/query stay blank or separate
      verify(response, :post, '/api/4.0/test_post_body', {foo: 'bar'}, {}) do |sdk|
        sdk.test_post_body({foo: 'bar'})
      end
    end
    
    it "keeps params in query for GET" do
      verify(response, :get, '/api/4.0/test_get_query', '', {param1: 'foo'}) do |sdk|
        sdk.test_get_query(param1: 'foo')
      end
    end
  end
end
