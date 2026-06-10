# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module PagecordCLI
  class Client
    class Error < StandardError
      attr_reader :status

      def initialize(status, message)
        @status = status
        super(message)
      end
    end

    attr_reader :api_key, :base_url
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 30
    WRITE_TIMEOUT = 30

    def initialize(api_key:, base_url:)
      @api_key = api_key
      @base_url = base_url
    end

    def verify!
      request(Net::HTTP::Get.new(uri_for("/posts")))
      true
    end

    def create_post(params)
      request(json_request(Net::HTTP::Post, "/posts", params))
    end

    def update_post(token, params)
      request(json_request(Net::HTTP::Patch, "/posts/#{token}", params))
    end

    def upload_attachment(path)
      uri = uri_for("/attachments")
      http_request = Net::HTTP::Post.new(uri)
      http_request["Authorization"] = "Bearer #{api_key}"
      http_request.set_form([
        [
          "file",
          File.open(path, "rb"),
          { filename: File.basename(path), content_type: content_type(path) }
        ]
      ], "multipart/form-data")

      request(http_request)
    end

    private

      def json_request(klass, path, params)
        request = klass.new(uri_for(path))
        request["Content-Type"] = "application/json"
        request.body = JSON.dump(params)
        request
      end

      def request(http_request)
        http_request["Authorization"] ||= "Bearer #{api_key}"
        response = Net::HTTP.start(http_request.uri.hostname, http_request.uri.port, use_ssl: http_request.uri.scheme == "https") do |http|
          http.open_timeout = OPEN_TIMEOUT
          http.read_timeout = READ_TIMEOUT
          http.write_timeout = WRITE_TIMEOUT if http.respond_to?(:write_timeout=)
          http.request(http_request)
        end

        handle_response(response)
      ensure
        http_request.body_stream&.close if http_request.respond_to?(:body_stream)
      end

      def handle_response(response)
        body = response.body.to_s
        parsed = body.empty? ? {} : JSON.parse(body)

        case response
        when Net::HTTPSuccess
          parsed
        else
          raise Error.new(response.code.to_i, error_message(parsed, response.code))
        end
      rescue JSON::ParserError
        raise Error.new(response.code.to_i, "Unexpected response from Pagecord")
      end

      def error_message(parsed, status)
        return parsed["error"] if parsed["error"]
        return parsed["errors"].join(", ") if parsed["errors"].is_a?(Array)

        "Pagecord API returned #{status}"
      end

      def uri_for(path)
        URI.join(base_url.end_with?("/") ? base_url : "#{base_url}/", path.delete_prefix("/"))
      end

      def content_type(path)
        case File.extname(path).downcase
        when ".jpg", ".jpeg" then "image/jpeg"
        when ".png" then "image/png"
        when ".gif" then "image/gif"
        when ".webp" then "image/webp"
        when ".mp4" then "video/mp4"
        when ".mov" then "video/quicktime"
        when ".mp3" then "audio/mpeg"
        when ".wav" then "audio/wav"
        else "application/octet-stream"
        end
      end
  end
end
