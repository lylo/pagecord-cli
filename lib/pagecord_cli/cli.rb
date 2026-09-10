# frozen_string_literal: true

require "io/console"
require "json"
require "optparse"

module PagecordCLI
  class CLI
    class Error < StandardError; end

    APPEARANCE_FIELDS = %w[
      theme font width layout
      custom_theme_bg_light custom_theme_text_light custom_theme_accent_light
      custom_theme_bg_dark custom_theme_text_dark custom_theme_accent_dark
    ].freeze

    CUSTOM_CODE_FIELDS = {
      "css" => "custom_css",
      "footer-html" => "custom_footer_html",
      "head-html" => "custom_head_html",
      "body-html" => "custom_body_html"
    }.freeze

    attr_reader :argv, :config, :input, :output, :error, :options

    def initialize(argv, config: Config.new, input: $stdin, output: $stdout, error: $stderr)
      @argv = argv.dup
      @config = config
      @input = input
      @output = output
      @error = error
      @options = {}
    end

    def run
      return help if argv.empty? || %w[help -h --help].include?(argv.first)

      parser.order!(argv)
      command = argv.shift

      case command
      when "login" then login
      when "logout" then logout
      when "list" then list
      when "blog" then blog
      when "appearance" then appearance
      when "custom-code" then custom_code
      when "publish" then publish("published")
      when "draft" then publish("draft")
      else
        fail_with("Unknown command: #{command}")
      end
    rescue Client::Error => e
      fail_with(api_error_message(e))
    rescue Error, Config::Error, OptionParser::ParseError, Errno::ENOENT => e
      fail_with(e.message)
    rescue Interrupt
      error.puts
      fail_with("Cancelled")
    end

    private

      def login
        base_url = Config::DEFAULT_BASE_URL
        parser { |opts| opts.on("--base-url URL") { |value| base_url = value } }.parse!(argv)

        subdomain = argv.shift
        return fail_with("Usage: pagecord login SUBDOMAIN") unless subdomain

        base_url = Config.normalize_base_url(base_url)
        api_key = prompt_api_key
        Client.new(api_key: api_key, base_url: base_url).verify!
        config.save_blog(subdomain, api_key: api_key, base_url: base_url)

        say "Saved #{subdomain}"
        0
      end

      def logout
        parser.parse!(argv)
        subdomain = resolve_blog(argv.shift)

        config.delete_blog(subdomain)
        say "Removed #{subdomain}"
        0
      end

      def blog
        case argv.shift
        when "list" then list
        when "use" then use
        else fail_with("Usage: pagecord blog list|use SUBDOMAIN")
        end
      end

      def list
        parser.parse!(argv)
        return fail_with("No blogs are configured") if config.blogs.empty?

        if options[:json]
          print_json(config.blogs.map { |subdomain, details|
            { subdomain: subdomain, base_url: details["base_url"], default: subdomain == config.default_blog }
          })
        else
          config.blogs.each do |subdomain, details|
            suffix = details["base_url"] == Config::DEFAULT_BASE_URL ? "" : " (#{details["base_url"]})"
            suffix += " (default)" if subdomain == config.default_blog
            output.puts "#{subdomain}#{suffix}"
          end
        end

        0
      end

      def use
        parser.parse!(argv)
        subdomain = argv.shift
        return fail_with("Usage: pagecord blog use SUBDOMAIN") unless subdomain
        return fail_with("Unknown blog: #{subdomain}") unless config.blog(subdomain)

        config.save_default_blog(subdomain)
        say "Using #{subdomain}"
        0
      end

      def appearance
        case argv.shift
        when "show" then show_appearance
        when "update" then update_appearance
        else fail_with("Usage: pagecord appearance show|update [--FIELD VALUE]")
        end
      end

      def show_appearance
        parser.parse!(argv)
        settings = client_for(resolve_blog).appearance

        if options[:json]
          print_json(settings)
        else
          settings.each { |key, value| output.puts "#{key}: #{value}" }
        end

        0
      end

      def update_appearance
        params = {}
        parser do |opts|
          APPEARANCE_FIELDS.each do |field|
            opts.on("--#{field.tr("_", "-")} VALUE") { |value| params[field] = value }
          end
          opts.on("--show-branding BOOL", TrueClass) { |value| params["show_branding"] = value }
        end.parse!(argv)

        return fail_with("Nothing to update") if params.empty?

        settings = client_for(resolve_blog).update_appearance(params)
        options[:json] ? print_json(settings) : say("Updated appearance")
        0
      end

      def custom_code
        case argv.shift
        when "show" then show_custom_code
        when "update" then update_custom_code
        else fail_with("Usage: pagecord custom-code show|update [--FIELD VALUE]")
        end
      end

      def show_custom_code
        field = nil
        parser do |opts|
          CUSTOM_CODE_FIELDS.each { |flag, name| opts.on("--#{flag}") { field = name } }
        end.parse!(argv)

        settings = client_for(resolve_blog).custom_code
        field ? output.print(settings[field].to_s) : print_json(settings)
        0
      end

      def update_custom_code
        params = {}
        parser do |opts|
          CUSTOM_CODE_FIELDS.each do |flag, name|
            opts.on("--#{flag} PATH") { |path| params[name] = read_file(flag, path) }
          end
          opts.on("--enabled BOOL", TrueClass) { |value| params["custom_code_enabled"] = value }
        end.parse!(argv)

        return fail_with("Nothing to update") if params.empty?

        settings = client_for(resolve_blog).update_custom_code(params)
        options[:json] ? print_json(settings) : say("Updated custom code")
        0
      end

      def publish(status)
        overrides = {}
        parser do |opts|
          opts.on("--title TITLE") { |value| overrides[:title] = value }
          opts.on("--slug SLUG") { |value| overrides[:slug] = value }
          opts.on("--published-at TIME") { |value| overrides[:published_at] = value }
          opts.on("--tags TAGS") { |value| overrides[:tags] = value }
          opts.on("--canonical-url URL") { |value| overrides[:canonical_url] = value }
          opts.on("--hidden") { overrides[:hidden] = true }
          opts.on("--locale LOCALE") { |value| overrides[:locale] = value }
        end.parse!(argv)

        file_path = argv.shift
        return fail_with("Usage: pagecord #{status == "draft" ? "draft" : "publish"} FILE [SUBDOMAIN]") unless file_path

        subdomain = resolve_blog(argv.shift)

        post_file = PostFile.new(file_path)
        return fail_with("Unsupported file type: #{file_path}") unless post_file.supported?

        api_key = config.blog(subdomain).fetch("api_key")
        return fail_with("This file is linked to another configured blog.") if post_file.wrong_blog?(subdomain, api_key)

        client = client_for(subdomain)
        params = post_file.params.merge(overrides).merge(
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
        say "#{status == "draft" ? "Saved draft" : "Published"} #{file_path} to #{subdomain}"
        0
      end

      def parser
        OptionParser.new do |opts|
          opts.on("--blog SUBDOMAIN") { |value| options[:blog] = value }
          opts.on("--json") { options[:json] = true }
          opts.on("--quiet") { options[:quiet] = true }
          yield opts if block_given?
        end
      end

      def resolve_blog(name = nil)
        raise Error, "No blogs are configured. Run pagecord login SUBDOMAIN first." if config.blogs.empty?

        subdomain = name || options[:blog] || ENV["PAGECORD_BLOG"] || config.default_blog ||
          (config.blogs.keys.first if config.blogs.size == 1)

        raise Error, "Please specify a subdomain" unless subdomain
        raise Error, "Unknown blog: #{subdomain}" unless config.blog(subdomain)

        subdomain
      end

      def client_for(subdomain)
        blog_config = config.blog(subdomain)
        Client.new(
          api_key: blog_config.fetch("api_key"),
          base_url: blog_config.fetch("base_url", Config::DEFAULT_BASE_URL)
        )
      end

      def read_file(flag, path)
        File.read(path)
      rescue SystemCallError
        raise Error, path.match?(/[{<]/) ? "--#{flag} takes a file path, not the content itself" : "Could not read #{path}"
      end

      def say(message)
        output.puts message unless options[:quiet]
      end

      def print_json(value)
        output.puts JSON.pretty_generate(value)
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
            pagecord blog list
            pagecord blog use SUBDOMAIN
            pagecord appearance show
            pagecord appearance update [options]
            pagecord custom-code show [--css|--footer-html|--head-html|--body-html]
            pagecord custom-code update --css blog.css
            pagecord custom-code update [options]
            pagecord publish FILE [SUBDOMAIN] [options]
            pagecord draft FILE [SUBDOMAIN] [options]

          Global options:
            --blog SUBDOMAIN
            --json
            --quiet

          Publish options:
            --title TITLE
            --slug SLUG
            --published-at TIME
            --tags TAGS
            --canonical-url URL
            --hidden
            --locale LOCALE

          Appearance options:
            --theme, --font, --width, --layout
            --custom-theme-bg-light, --custom-theme-text-light, --custom-theme-accent-light
            --custom-theme-bg-dark, --custom-theme-text-dark, --custom-theme-accent-dark
            --show-branding true|false

          Custom code options:
            --css, --footer-html, --head-html, --body-html (each takes a file path)
            --enabled true|false
        HELP
        0
      end

      def fail_with(message)
        error.puts message
        1
      end
  end
end
