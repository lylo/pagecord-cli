# frozen_string_literal: true

require "yaml"
require "date"
require "digest"

module PagecordCLI
  class PostFile
    MARKDOWN_EXTENSIONS = [ ".md", ".markdown" ].freeze
    HTML_EXTENSIONS = [ ".html", ".htm" ].freeze
    FRONT_MATTER = /\A---[ \t]*\n(.*?)\n---[ \t]*\n?/m
    HTML_METADATA = /\A\s*<!--\s*pagecord:\s*\n(.*?)\n-->\s*/m

    attr_reader :path, :content, :metadata, :body

    def initialize(path)
      @path = path
      @content = File.read(path)
      @metadata, @body = extract_metadata
    end

    def markdown?
      MARKDOWN_EXTENSIONS.include?(File.extname(path).downcase)
    end

    def html?
      HTML_EXTENSIONS.include?(File.extname(path).downcase)
    end

    def token_for(blog)
      if markdown?
        metadata["pagecord_token"]
      else
        metadata.dig(blog, "token") || metadata[blog]
      end
    end

    def content_for(blog, client:)
      return body unless markdown?

      ImageUploads.new(
        body,
        file_path: path,
        metadata: metadata,
        blog: blog,
        client: client
      ).process
    end

    def write_token(blog, token, api_key: nil, status: nil)
      if markdown?
        metadata["pagecord_token"] = token
        metadata["pagecord_blog_fingerprint"] = self.class.blog_fingerprint(api_key) if api_key
        metadata["status"] = status if status
        write_markdown
      else
        metadata[blog] = token
        write_html
      end
    end

    def content_format
      markdown? ? "markdown" : nil
    end

    def params
      publish_params = { title: title_from_metadata }

      %w[slug published_at canonical_url locale].each do |key|
        value = frontmatter_string(metadata[key])
        publish_params[key.to_sym] = value if value
      end

      tags = tags_from_metadata
      publish_params[:tags] = tags if tags

      hidden = frontmatter_boolean(metadata["hidden"])
      publish_params[:hidden] = hidden unless hidden.nil?

      publish_params
    end

    def wrong_blog?(blog, api_key)
      return false unless markdown?
      return false unless metadata["pagecord_token"]
      return false unless metadata["pagecord_blog_fingerprint"]

      metadata["pagecord_blog_fingerprint"].to_s != self.class.blog_fingerprint(api_key)
    end

    def self.blog_fingerprint(api_key)
      Digest::SHA256.hexdigest(api_key)[0, 12]
    end

    def default_title
      title = File.basename(path, File.extname(path)).tr("_-", " ").squeeze(" ").strip
      title.empty? ? "" : title[0].upcase + title[1..].to_s
    end

    def supported?
      markdown? || html?
    end

    private

      def extract_metadata
        if markdown?
          extract_markdown_metadata
        elsif html?
          extract_html_metadata
        else
          [ {}, content ]
        end
      end

      def extract_markdown_metadata
        match = content.match(FRONT_MATTER)
        return [ {}, content ] unless match

        yaml = YAML.safe_load(match[1], permitted_classes: [ Date, Time ], aliases: false) || {}
        [ stringify_keys(yaml), content[match[0].length..] || "" ]
      rescue Psych::Exception
        [ {}, content ]
      end

      def extract_html_metadata
        match = content.match(HTML_METADATA)
        return [ {}, content ] unless match

        data = YAML.safe_load(match[1], aliases: false) || {}
        [ normalize_html_metadata(data), content[match[0].length..] || "" ]
      rescue Psych::Exception
        [ {}, content ]
      end

      def title_from_metadata
        return default_title unless metadata.key?("title")
        return "" if metadata["title"].nil?

        frontmatter_string(metadata["title"]).to_s
      end

      def tags_from_metadata
        tags = metadata["tags"]
        return if tags.nil?

        if tags.is_a?(Array)
          tags.map { |tag| frontmatter_string(tag).to_s }.join(", ")
        else
          frontmatter_string(tags)
        end
      end

      def frontmatter_string(value)
        return if value.nil?

        value = value.to_s
        quoted = value.match(/\A(['"])(.*)\1\z/)
        quoted ? quoted[2] : value
      end

      def frontmatter_boolean(value)
        return if value.nil?
        return value if value == true || value == false

        normalized = frontmatter_string(value).to_s.strip.downcase
        return true if normalized == "true"
        return false if normalized == "false"

        !!value
      end

      def write_markdown
        File.write(path, "#{YAML.dump(metadata)}---\n#{body}")
      end

      def write_html
        File.write(path, "<!-- pagecord:\n#{YAML.dump(flat_html_metadata).delete_prefix("---\n")}-->\n#{body}")
      end

      def flat_html_metadata
        metadata.transform_values { |value| value.is_a?(Hash) ? value["token"] : value }
      end

      def normalize_html_metadata(data)
        stringify_keys(data).transform_values do |value|
          value.is_a?(Hash) ? value : { "token" => value }
        end
      end

      def stringify_keys(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, item), hash| hash[key.to_s] = stringify_keys(item) }
        when Array
          value.map { |item| stringify_keys(item) }
        else
          value
        end
      end
  end
end
