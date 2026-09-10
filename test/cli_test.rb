# frozen_string_literal: true

require_relative "test_helper"

class CLITest < Minitest::Test
  include ClientSwap

  def test_login_saves_blog_with_base_url
    with_fake_client do
      Dir.mktmpdir do |dir|
        config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))
        input = StringIO.new("secret\n")
        output = StringIO.new

        status = PagecordCLI::CLI.new(
          [ "login", "olly", "--base-url", "http://localhost:3000" ],
          config: config,
          input: input,
          output: output
        ).run

        assert_equal 0, status
        assert_equal "secret", config.blog("olly")["api_key"]
        assert_equal "http://localhost:3000", config.blog("olly")["base_url"]
        assert_equal :verify, FakeClient.requests.first.action
      end
    end
  end

  def test_login_normalizes_app_domain_to_api_domain
    with_fake_client do
      Dir.mktmpdir do |dir|
        config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))
        input = StringIO.new("secret\n")

        status = PagecordCLI::CLI.new(
          [ "login", "joel", "--base-url", "https://pagecord.net" ],
          config: config,
          input: input
        ).run

        assert_equal 0, status
        assert_equal "https://api.pagecord.net", config.blog("joel")["base_url"]
        assert_equal "https://api.pagecord.net", FakeClient.requests.first.base_url
      end
    end
  end

  def test_logout_without_subdomain_works_for_one_blog
    Dir.mktmpdir do |dir|
      config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))
      config.save_blog("olly", api_key: "secret")
      output = StringIO.new

      status = PagecordCLI::CLI.new([ "logout" ], config: config, output: output).run

      assert_equal 0, status
      assert_empty config.blogs
      assert_includes output.string, "Removed olly"
    end
  end

  def test_logout_requires_subdomain_for_multiple_blogs
    Dir.mktmpdir do |dir|
      config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))
      config.save_blog("olly", api_key: "secret")
      config.save_blog("work", api_key: "secret")
      error = StringIO.new

      status = PagecordCLI::CLI.new([ "logout" ], config: config, error: error).run

      assert_equal 1, status
      assert_includes error.string, "Please specify a subdomain"
    end
  end

  def test_list_shows_saved_blogs
    Dir.mktmpdir do |dir|
      config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))
      config.save_blog("olly", api_key: "secret")
      config.save_blog("local", api_key: "secret", base_url: "http://localhost:3000")
      output = StringIO.new

      status = PagecordCLI::CLI.new([ "list" ], config: config, output: output).run

      assert_equal 0, status
      assert_includes output.string, "olly"
      assert_includes output.string, "local (http://localhost:3000)"
    end
  end

  def test_config_errors_are_shown_without_overwriting_config
    Dir.mktmpdir do |dir|
      path = File.join(dir, ".pagecord.yml")
      File.write(path, "blogs:\n  nope: [")
      config = PagecordCLI::Config.new(path)
      error = StringIO.new

      status = PagecordCLI::CLI.new([ "list" ], config: config, error: error).run

      assert_equal 1, status
      assert_includes error.string, "Could not read #{path}"
      assert_equal "blogs:\n  nope: [", File.read(path)
    end
  end

  def test_publish_without_subdomain_works_for_one_blog
    with_fake_client do
      Dir.mktmpdir do |dir|
        config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))
        config.save_blog("olly", api_key: "secret")
        file = File.join(dir, "hello-world.md")
        File.write(file, "Hello **world**\n")

        status = PagecordCLI::CLI.new([ "publish", file ], config: config).run

        assert_equal 0, status
        request = FakeClient.requests.find { |item| item.action == :create_post }
        assert_equal "published", request.args.first[:status]
        assert_equal "markdown", request.args.first[:content_format]
        assert_equal "Hello world", request.args.first[:title]
        assert_includes File.read(file), "pagecord_token: created-token"
        assert_includes File.read(file), "status: published"
      end
    end
  end

  def test_publish_does_not_override_front_matter_title
    with_fake_client do
      Dir.mktmpdir do |dir|
        config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))
        config.save_blog("olly", api_key: "secret")
        file = File.join(dir, "hello-world.md")
        File.write(file, "---\ntitle: Front Matter\n---\nHello\n")

        status = PagecordCLI::CLI.new([ "publish", file ], config: config).run

        assert_equal 0, status
        request = FakeClient.requests.find { |item| item.action == :create_post }
        assert_equal "Front Matter", request.args.first[:title]
      end
    end
  end

  def test_publish_uses_front_matter_fields
    with_fake_client do
      Dir.mktmpdir do |dir|
        config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))
        config.save_blog("olly", api_key: "secret")
        file = File.join(dir, "hello-world.md")
        File.write(file, "---\ntitle: 'Front Matter'\nslug: fm-slug\ntags:\n  - obsidian\n  - cli\npublished_at: '2026-01-02T03:04:05Z'\ncanonical_url: 'https://example.com/original'\nhidden: 'false'\nlocale: en\n---\nHello\n")

        status = PagecordCLI::CLI.new([ "publish", file ], config: config).run

        assert_equal 0, status
        request = FakeClient.requests.find { |item| item.action == :create_post }
        assert_equal "Front Matter", request.args.first[:title]
        assert_equal "fm-slug", request.args.first[:slug]
        assert_equal "obsidian, cli", request.args.first[:tags]
        assert_equal "2026-01-02T03:04:05Z", request.args.first[:published_at]
        assert_equal "https://example.com/original", request.args.first[:canonical_url]
        assert_equal false, request.args.first[:hidden]
        assert_equal "en", request.args.first[:locale]
      end
    end
  end

  def test_publish_allows_blank_title
    with_fake_client do
      Dir.mktmpdir do |dir|
        config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))
        config.save_blog("olly", api_key: "secret")
        file = File.join(dir, "hello-world.md")
        File.write(file, "Hello\n")

        status = PagecordCLI::CLI.new([ "publish", file, "--title", "" ], config: config).run

        assert_equal 0, status
        request = FakeClient.requests.find { |item| item.action == :create_post }
        assert_equal "", request.args.first[:title]
      end
    end
  end

  def test_publish_requires_subdomain_for_multiple_blogs
    with_fake_client do
      Dir.mktmpdir do |dir|
        config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))
        config.save_blog("olly", api_key: "secret")
        config.save_blog("work", api_key: "secret")
        file = File.join(dir, "hello.md")
        File.write(file, "Hello\n")
        error = StringIO.new

        status = PagecordCLI::CLI.new([ "publish", file ], config: config, error: error).run

        assert_equal 1, status
        assert_includes error.string, "Please specify a subdomain"
      end
    end
  end

  def test_draft_updates_existing_blog_token
    with_fake_client do
      Dir.mktmpdir do |dir|
        config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))
        config.save_blog("olly", api_key: "secret")
        file = File.join(dir, "hello.md")
        File.write(file, "---\npagecord_token: old-token\n---\nHello\n")

        status = PagecordCLI::CLI.new([ "draft", file ], config: config).run

        assert_equal 0, status
        request = FakeClient.requests.find { |item| item.action == :update_post }
        assert_equal "old-token", request.args[0]
        assert_equal "draft", request.args[1][:status]
        assert_includes File.read(file), "pagecord_blog_fingerprint:"
        assert_includes File.read(file), "status: draft"
      end
    end
  end

  def test_publish_rejects_file_linked_to_another_blog
    with_fake_client do
      Dir.mktmpdir do |dir|
        config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))
        config.save_blog("olly", api_key: "secret")
        file = File.join(dir, "hello.md")
        File.write(file, "---\npagecord_token: old-token\npagecord_blog_fingerprint: #{PagecordCLI::PostFile.blog_fingerprint("other")}\n---\nHello\n")
        error = StringIO.new

        status = PagecordCLI::CLI.new([ "publish", file ], config: config, error: error).run

        assert_equal 1, status
        assert_includes error.string, "linked to another configured blog"
        assert_empty FakeClient.requests
      end
    end
  end
  def test_blog_use_sets_the_default_blog
    Dir.mktmpdir do |dir|
      config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))
      config.save_blog("olly", api_key: "secret")
      config.save_blog("work", api_key: "secret")
      output = StringIO.new

      status = PagecordCLI::CLI.new([ "blog", "use", "work" ], config: config, output: output).run

      assert_equal 0, status
      assert_equal "work", config.default_blog
      assert_includes output.string, "Using work"
    end
  end

  def test_blog_use_rejects_an_unknown_blog
    Dir.mktmpdir do |dir|
      config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))
      config.save_blog("olly", api_key: "secret")
      error = StringIO.new

      status = PagecordCLI::CLI.new([ "blog", "use", "nope" ], config: config, error: error).run

      assert_equal 1, status
      assert_includes error.string, "Unknown blog: nope"
      assert_nil config.default_blog
    end
  end

  def test_default_blog_is_used_when_several_are_configured
    with_fake_client do
      Dir.mktmpdir do |dir|
        config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))
        config.save_blog("olly", api_key: "secret")
        config.save_blog("work", api_key: "work-secret")
        config.save_default_blog("work")
        file = File.join(dir, "hello.md")
        File.write(file, "Hello\n")

        status = PagecordCLI::CLI.new([ "publish", file ], config: config, output: StringIO.new).run

        assert_equal 0, status
        assert_equal "work-secret", FakeClient.requests.last.api_key
      end
    end
  end

  def test_blog_flag_beats_the_environment_and_the_default
    with_fake_client do
      Dir.mktmpdir do |dir|
        config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))
        config.save_blog("olly", api_key: "olly-secret")
        config.save_blog("work", api_key: "work-secret")
        config.save_default_blog("work")
        ENV["PAGECORD_BLOG"] = "work"
        output = StringIO.new

        status = PagecordCLI::CLI.new([ "appearance", "show", "--blog", "olly" ], config: config, output: output).run

        assert_equal 0, status
        assert_equal "olly-secret", FakeClient.requests.last.api_key
      ensure
        ENV.delete("PAGECORD_BLOG")
      end
    end
  end

  def test_environment_beats_the_default_blog
    with_fake_client do
      Dir.mktmpdir do |dir|
        config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))
        config.save_blog("olly", api_key: "olly-secret")
        config.save_blog("work", api_key: "work-secret")
        config.save_default_blog("work")
        ENV["PAGECORD_BLOG"] = "olly"

        status = PagecordCLI::CLI.new([ "appearance", "show" ], config: config, output: StringIO.new).run

        assert_equal 0, status
        assert_equal "olly-secret", FakeClient.requests.last.api_key
      ensure
        ENV.delete("PAGECORD_BLOG")
      end
    end
  end

  def test_global_flag_is_accepted_before_the_command
    with_fake_client do
      Dir.mktmpdir do |dir|
        config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))
        config.save_blog("olly", api_key: "olly-secret")
        config.save_blog("work", api_key: "work-secret")
        output = StringIO.new

        status = PagecordCLI::CLI.new([ "--blog", "work", "appearance", "show" ], config: config, output: output).run

        assert_equal 0, status
        assert_equal "work-secret", FakeClient.requests.last.api_key
      end
    end
  end

  def test_unknown_flag_fails_without_raising
    Dir.mktmpdir do |dir|
      config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))
      config.save_blog("olly", api_key: "secret")
      error = StringIO.new

      status = PagecordCLI::CLI.new([ "list", "--nope" ], config: config, error: error).run

      assert_equal 1, status
      assert_includes error.string, "invalid option"
    end
  end

  def test_help_is_shown_without_arguments
    output = StringIO.new

    status = PagecordCLI::CLI.new([ "--help" ], output: output).run

    assert_equal 0, status
    assert_includes output.string, "pagecord custom-code show"
  end

  def test_blog_list_marks_the_default
    Dir.mktmpdir do |dir|
      config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))
      config.save_blog("olly", api_key: "secret")
      config.save_default_blog("olly")
      output = StringIO.new

      status = PagecordCLI::CLI.new([ "blog", "list", "--json" ], config: config, output: output).run

      assert_equal 0, status
      assert_equal [ { "subdomain" => "olly", "base_url" => PagecordCLI::Config::DEFAULT_BASE_URL, "default" => true } ],
        JSON.parse(output.string)
    end
  end

  def test_appearance_show_prints_each_setting
    with_fake_client do
      Dir.mktmpdir do |dir|
        config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))
        config.save_blog("olly", api_key: "secret")
        output = StringIO.new

        status = PagecordCLI::CLI.new([ "appearance", "show" ], config: config, output: output).run

        assert_equal 0, status
        assert_includes output.string, "theme: base"
      end
    end
  end

  def test_appearance_update_sends_only_the_flags_given
    with_fake_client do
      Dir.mktmpdir do |dir|
        config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))
        config.save_blog("olly", api_key: "secret")

        status = PagecordCLI::CLI.new(
          [ "appearance", "update", "--theme", "sand", "--show-branding", "false" ],
          config: config, output: StringIO.new
        ).run

        assert_equal 0, status
        assert_equal({ "theme" => "sand", "show_branding" => false }, FakeClient.requests.last.args.first)
      end
    end
  end

  def test_appearance_update_rejects_a_non_boolean_branding_value
    with_fake_client do
      Dir.mktmpdir do |dir|
        config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))
        config.save_blog("olly", api_key: "secret")
        error = StringIO.new

        status = PagecordCLI::CLI.new(
          [ "appearance", "update", "--show-branding", "maybe" ], config: config, error: error
        ).run

        assert_equal 1, status
        assert_empty FakeClient.requests
      end
    end
  end

  def test_appearance_update_without_flags_fails
    with_fake_client do
      Dir.mktmpdir do |dir|
        config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))
        config.save_blog("olly", api_key: "secret")
        error = StringIO.new

        status = PagecordCLI::CLI.new([ "appearance", "update" ], config: config, error: error).run

        assert_equal 1, status
        assert_includes error.string, "Nothing to update"
      end
    end
  end

  def test_custom_code_show_writes_one_field_verbatim
    with_fake_client do
      Dir.mktmpdir do |dir|
        config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))
        config.save_blog("olly", api_key: "secret")
        output = StringIO.new

        status = PagecordCLI::CLI.new([ "custom-code", "show", "--css" ], config: config, output: output).run

        assert_equal 0, status
        assert_equal "body { color: red }", output.string
      end
    end
  end

  def test_custom_code_update_reads_a_file
    with_fake_client do
      Dir.mktmpdir do |dir|
        config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))
        config.save_blog("olly", api_key: "secret")
        css = File.join(dir, "blog.css")
        File.write(css, "body { color: blue }\n")

        status = PagecordCLI::CLI.new(
          [ "custom-code", "update", "--css", css ], config: config, output: StringIO.new
        ).run

        assert_equal 0, status
        assert_equal({ "custom_css" => "body { color: blue }\n" }, FakeClient.requests.last.args.first)
      end
    end
  end

  def test_quiet_suppresses_the_confirmation
    with_fake_client do
      Dir.mktmpdir do |dir|
        config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))
        config.save_blog("olly", api_key: "secret")
        output = StringIO.new

        status = PagecordCLI::CLI.new(
          [ "appearance", "update", "--theme", "sand", "--quiet" ], config: config, output: output
        ).run

        assert_equal 0, status
        assert_empty output.string
      end
    end
  end
  def test_custom_code_update_reports_an_unreadable_file
    with_fake_client do
      Dir.mktmpdir do |dir|
        config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))
        config.save_blog("olly", api_key: "secret")
        error = StringIO.new

        status = PagecordCLI::CLI.new(
          [ "custom-code", "update", "--css", "#{dir}/missing.css" ], config: config, error: error
        ).run

        assert_equal 1, status
        assert_equal "Could not read #{dir}/missing.css\n", error.string
        assert_empty FakeClient.requests
      end
    end
  end
  def test_custom_code_update_says_so_when_given_content_instead_of_a_path
    with_fake_client do
      Dir.mktmpdir do |dir|
        config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))
        config.save_blog("olly", api_key: "secret")
        error = StringIO.new

        status = PagecordCLI::CLI.new(
          [ "custom-code", "update", "--css", "@media print { body { color: black } }" ],
          config: config, error: error
        ).run

        assert_equal 1, status
        assert_equal "--css takes a file path, not the content itself\n", error.string
        assert_empty FakeClient.requests
      end
    end
  end

  def test_custom_code_update_reads_every_field_from_a_file
    with_fake_client do
      Dir.mktmpdir do |dir|
        config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))
        config.save_blog("olly", api_key: "secret")
        footer = File.join(dir, "footer.html")
        File.write(footer, "<p>Thanks for reading</p>")

        status = PagecordCLI::CLI.new(
          [ "custom-code", "update", "--footer-html", footer ], config: config, output: StringIO.new
        ).run

        assert_equal 0, status
        assert_equal({ "custom_footer_html" => "<p>Thanks for reading</p>" }, FakeClient.requests.last.args.first)
      end
    end
  end
end
