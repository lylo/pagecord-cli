# frozen_string_literal: true

require "io/console"
require "optparse"

module PagecordCLI
  class CLI
    attr_reader :argv, :config, :input, :output, :error

    def initialize(argv, config: Config.new, input: $stdin, output: $stdout, error: $stderr)
      @argv = argv.dup
      @config = config
      @input = input
      @output = output
      @error = error
    end

    def run
      command = argv.shift

      case command
      when "login" then login
      when "logout" then logout
      when "list" then list
      when "publish" then publish("published")
      when "draft" then publish("draft")
      when "help", nil, "-h", "--help" then help
      else
        fail_with("Unknown command: #{command}")
      end
    rescue Client::Error => e
      fail_with(api_error_message(e))
    rescue Config::Error => e
      fail_with(e.message)
    rescue Errno::ENOENT => e
      fail_with(e.message)
    rescue Interrupt
      error.puts
      fail_with("Cancelled")
    end

    private

      def login
        options = { base_url: Config::DEFAULT_BASE_URL }
        parser = OptionParser.new do |opts|
          opts.on("--base-url URL") { |value| options[:base_url] = value }
        end
        parser.parse!(argv)

        subdomain = argv.shift
        return fail_with("Usage: pagecord login SUBDOMAIN") unless subdomain

        base_url = Config.normalize_base_url(options[:base_url])
        api_key = prompt_api_key
        client = Client.new(api_key: api_key, base_url: base_url)
        client.verify!
        config.save_blog(subdomain, api_key: api_key, base_url: base_url)

        output.puts "Saved #{subdomain}"
        0
      end

      def logout
        subdomain = resolve_blog(argv.shift)
        return fail_with("No blogs are configured") if config.blogs.empty?
        return fail_with("Please specify a subdomain") unless subdomain
        return fail_with("Unknown blog: #{subdomain}") unless config.blog(subdomain)

        config.delete_blog(subdomain)
        output.puts "Removed #{subdomain}"
        0
      end

      def list
        return fail_with("No blogs are configured") if config.blogs.empty?

        config.blogs.each do |subdomain, details|
          suffix = details["base_url"] == Config::DEFAULT_BASE_URL ? "" : " (#{details["base_url"]})"
          output.puts "#{subdomain}#{suffix}"
        end

        0
      end

      def publish(status)
        options = publish_options
        parser = OptionParser.new do |opts|
          opts.on("--title TITLE") { |value| options[:title] = value }
          opts.on("--slug SLUG") { |value| options[:slug] = value }
          opts.on("--published-at TIME") { |value| options[:published_at] = value }
          opts.on("--tags TAGS") { |value| options[:tags] = value }
          opts.on("--canonical-url URL") { |value| options[:canonical_url] = value }
          opts.on("--hidden") { options[:hidden] = true }
          opts.on("--locale LOCALE") { |value| options[:locale] = value }
        end
        parser.parse!(argv)

        file_path = argv.shift
        subdomain = resolve_blog(argv.shift)

        return fail_with("Usage: pagecord #{status == "draft" ? "draft" : "publish"} FILE [SUBDOMAIN]") unless file_path
        return fail_with("No blogs are configured. Run pagecord login SUBDOMAIN first.") if config.blogs.empty?
        return fail_with("Please specify a subdomain") unless subdomain
        return fail_with("Unknown blog: #{subdomain}") unless config.blog(subdomain)

        post_file = PostFile.new(file_path)
        return fail_with("Unsupported file type: #{file_path}") unless post_file.supported?

        blog_config = config.blog(subdomain)
        api_key = blog_config.fetch("api_key")
        return fail_with("This file is linked to another configured blog.") if post_file.wrong_blog?(subdomain, api_key)

        client = Client.new(api_key: blog_config.fetch("api_key"), base_url: blog_config.fetch("base_url", Config::DEFAULT_BASE_URL))
        params = post_file.params.merge(options.compact).merge(
          content: post_file.content_for(subdomain, client: client),
          status: status
        )
        params[:content_format] = post_file.content_format if post_file.content_format

        result = if (token = post_file.token_for(subdomain))
          client.update_post(token, params)
        else
          client.create_post(params)
        end

        post_file.write_token(subdomain, result.fetch("token"), api_key: api_key, status: status)
        output.puts "#{status == "draft" ? "Saved draft" : "Published"} #{file_path} to #{subdomain}"
        0
      end

      def publish_options
        {
          title: nil,
          slug: nil,
          published_at: nil,
          tags: nil,
          canonical_url: nil,
          hidden: nil,
          locale: nil
        }
      end

      def resolve_blog(name)
        return name if name
        return config.blogs.keys.first if config.blogs.size == 1

        nil
      end

      def prompt_api_key
        output.print "API key: "

        if input.tty?
          key = input.noecho(&:gets).to_s.strip
          output.puts
          key
        else
          input.gets.to_s.strip
        end
      end

      def api_error_message(api_error)
        if api_error.status == 404
          "#{api_error.message}. If this file should create a new post, remove its saved Pagecord token."
        else
          api_error.message
        end
      end

      def help
        output.puts <<~HELP
          Usage:
            pagecord login SUBDOMAIN
            pagecord logout [SUBDOMAIN]
            pagecord list
            pagecord publish FILE [SUBDOMAIN] [options]
            pagecord draft FILE [SUBDOMAIN] [options]

          Publish options:
            --title TITLE
            --slug SLUG
            --published-at TIME
            --tags TAGS
            --canonical-url URL
            --hidden
            --locale LOCALE
        HELP
        0
      end

      def fail_with(message)
        error.puts message
        1
      end
  end
end
