############################################################################################
# The MIT License (MIT)
#
# Copyright (c) 2024 Google LLC
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

require_relative '../helper'

describe LookerSDK::Client do

  before(:each) do
   setup_sdk
  end

  base_url = ENV['LOOKERSDK_BASE_URL'] || 'https://localhost:19999'
  verify_ssl = case ENV['LOOKERSDK_VERIFY_SSL']
               when /false/i
                 false
               when /f/i
                 false
               when '0'
                 false
               else
                 true
               end
  api_version = ENV['LOOKERSDK_API_VERSION'] || '4.0'
  client_id = ENV['LOOKERSDK_CLIENT_ID']
  client_secret = ENV['LOOKERSDK_CLIENT_SECRET']

  opts = {}
  if (client_id && client_secret) then
    opts.merge!({
      :client_id => client_id,
      :client_secret => client_secret,
      :api_endpoint => "#{base_url}/api/#{api_version}",
    })
    opts[:connection_options] = {:ssl => {:verify => false}} unless verify_ssl
  else
    opts.merge!({
      :netrc => true,
      :netrc_file => File.join(fixture_path, '.netrc'),
      :connection_options => {:ssl => {:verify => false}},
    })

  end

  describe "run inline query" do
    it "blocking" do
      LookerSDK.reset!
      client = LookerSDK::Client.new(opts)
      response = client.run_inline_query("csv",
        {
          "model": "system__activity",
          "view": "history",
          "fields": ["history.query_run_count", "query.model"],
          "limit": 5000
        }
      )
      assert response
    end

    it "streaming" do
      LookerSDK.reset!
      client = LookerSDK::Client.new(opts)
      response = ""
      client.run_inline_query("csv",
        {
          "model": "system__activity",
          "view": "history",
          "fields": ["history.query_run_count", "query.model"],
          "limit": 5000
        }
      ) do |data, progress|
        response << data
      end
      assert response
    end
  end
end
