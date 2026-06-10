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
end
