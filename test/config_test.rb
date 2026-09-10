# frozen_string_literal: true

require_relative "test_helper"

class ConfigTest < Minitest::Test
  def test_save_and_delete_blog
    Dir.mktmpdir do |dir|
      config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))

      config.save_blog("olly", api_key: "secret", base_url: "https://api.example.com")

      assert_equal "secret", config.blog("olly")["api_key"]
      assert_equal "https://api.example.com", config.blog("olly")["base_url"]

      config.delete_blog("olly")

      assert_empty config.blogs
    end
  end

  def test_invalid_config_raises_clear_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, ".pagecord.yml")
      File.write(path, "blogs:\n  nope: [")
      config = PagecordCLI::Config.new(path)

      error = assert_raises(PagecordCLI::Config::Error) { config.blogs }

      assert_includes error.message, "Could not read #{path}"
    end
  end
  def test_default_blog_round_trips
    Dir.mktmpdir do |dir|
      config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))
      config.save_blog("olly", api_key: "secret")
      config.save_default_blog("olly")

      assert_equal "olly", config.default_blog
    end
  end

  def test_deleting_the_default_blog_clears_the_default
    Dir.mktmpdir do |dir|
      config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))
      config.save_blog("olly", api_key: "secret")
      config.save_blog("work", api_key: "secret")
      config.save_default_blog("olly")

      config.delete_blog("work")
      assert_equal "olly", config.default_blog

      config.delete_blog("olly")
      assert_nil config.default_blog
    end
  end
end
