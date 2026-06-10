# frozen_string_literal: true

require "fileutils"
require "date"
require "uri"
require "yaml"

module PagecordCLI
  class Config
    class Error < StandardError; end

    DEFAULT_PATH = File.expand_path("~/.pagecord.yml")
    DEFAULT_BASE_URL = "https://api.pagecord.com"

    attr_reader :path

    def initialize(path = DEFAULT_PATH)
      @path = path
    end

    def self.normalize_base_url(url)
      uri = URI(url.match?(%r{\Ahttps?://}) ? url : "https://#{url}")
      return uri.to_s.delete_suffix("/") if api_or_local_host?(uri.host)

      uri.host = "api.#{uri.host}"
      uri.to_s.delete_suffix("/")
    end

    def blogs
      data.fetch("blogs", {})
    end

    def blog(name)
      blogs[name]
    end

    def save_blog(name, api_key:, base_url: DEFAULT_BASE_URL)
      new_data = data
      new_data["blogs"] ||= {}
      new_data["blogs"][name] = {
        "api_key" => api_key,
        "base_url" => base_url
      }
      write(new_data)
    end

    def delete_blog(name)
      new_data = data
      new_data.fetch("blogs", {}).delete(name)
      write(new_data)
    end

    def resolve_blog(name = nil)
      return name if name && blog(name)
      return name if name

      return blogs.keys.first if blogs.size == 1

      nil
    end

    def data
      return { "blogs" => {} } unless File.exist?(path)

      YAML.safe_load_file(path, permitted_classes: [ Time, Date ], aliases: false) || { "blogs" => {} }
    rescue Psych::Exception => e
      raise Error, "Could not read #{path}: #{e.message}"
    end

    private

      def self.api_or_local_host?(host)
        host.start_with?("api.") || %w[localhost 127.0.0.1 ::1].include?(host)
      end

      def write(new_data)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, YAML.dump(new_data))
        File.chmod(0o600, path)
      rescue NotImplementedError
        true
      end
  end
end
