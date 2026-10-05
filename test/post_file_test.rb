# frozen_string_literal: true

require_relative "test_helper"

class PostFileTest < Minitest::Test
  def test_markdown_metadata_matches_obsidian_plugin
    Dir.mktmpdir do |dir|
      file = File.join(dir, "hello.md")
      File.write(file, "---\ntitle: Hello\n---\nBody\n")

      post_file = PagecordCLI::PostFile.new(file)
      post_file.write_token("olly", "abc123", api_key: "secret", status: "published")

      content = File.read(file)
      assert_includes content, "title: Hello"
      assert_includes content, "pagecord_token: abc123"
      assert_includes content, "pagecord_blog_fingerprint: #{PagecordCLI::PostFile.blog_fingerprint("secret")}"
      assert_includes content, "status: published"
      assert_includes content, "Body"
    end
  end

  def test_markdown_legacy_token_without_fingerprint_is_used
    Dir.mktmpdir do |dir|
      file = File.join(dir, "hello.md")
      File.write(file, "---\npagecord_token: abc123\n---\nBody\n")

      post_file = PagecordCLI::PostFile.new(file)

      assert_equal "abc123", post_file.token_for("olly")
    end
  end

  def test_markdown_token_for_another_fingerprint_is_still_read_but_marked_wrong_blog
    Dir.mktmpdir do |dir|
      file = File.join(dir, "hello.md")
      File.write(file, "---\npagecord_token: abc123\npagecord_blog_fingerprint: #{PagecordCLI::PostFile.blog_fingerprint("other")}\n---\nBody\n")

      post_file = PagecordCLI::PostFile.new(file)

      assert_equal "abc123", post_file.token_for("olly")
      assert post_file.wrong_blog?("olly", "secret")
    end
  end

  def test_html_metadata_is_inserted_and_removed_from_body
    Dir.mktmpdir do |dir|
      file = File.join(dir, "hello.html")
      File.write(file, "<p>Hello</p>\n")

      post_file = PagecordCLI::PostFile.new(file)
      post_file.write_token("olly", "abc123")

      reparsed = PagecordCLI::PostFile.new(file)
      assert_equal "abc123", reparsed.token_for("olly")
      assert_equal "<p>Hello</p>\n", reparsed.body
    end
  end

  def test_markdown_images_upload_once_and_reuse_cache
    Dir.mktmpdir do |dir|
      image = File.join(dir, "photo.jpg")
      file = File.join(dir, "hello.md")
      File.binwrite(image, "image")
      File.write(file, "Look ![Alt](photo.jpg)\n")

      client = FakeClient.new(api_key: "secret", base_url: "https://api.pagecord.com")
      post_file = PagecordCLI::PostFile.new(file)
      first = post_file.content_for("olly", client: client)
      post_file.write_token("olly", "abc123", api_key: "secret", status: "published")

      assert_includes first, "action-text-attachment"
      assert_equal 1, FakeClient.requests.count { |request| request.action == :upload_attachment }

      reparsed = PagecordCLI::PostFile.new(file)
      second = reparsed.content_for("olly", client: client)

      assert_includes second, "sgid-123"
      assert_equal 1, FakeClient.requests.count { |request| request.action == :upload_attachment }
      assert_includes File.read(file), "pagecord_attachments:"
      assert_includes File.read(file), "hash:"
    ensure
      FakeClient.reset!
    end
  end

  def test_obsidian_images_are_supported
    Dir.mktmpdir do |dir|
      image = File.join(dir, "photo.jpg")
      file = File.join(dir, "hello.md")
      File.binwrite(image, "image")
      File.write(file, "Look ![[photo.jpg]]\n")

      client = FakeClient.new(api_key: "secret", base_url: "https://api.pagecord.com")
      post_file = PagecordCLI::PostFile.new(file)

      assert_includes post_file.content_for("olly", client: client), "action-text-attachment"
    ensure
      FakeClient.reset!
    end
  end

  def test_markdown_images_carry_alt_and_caption
    Dir.mktmpdir do |dir|
      image = File.join(dir, "my photo.jpg")
      file = File.join(dir, "hello.md")
      File.binwrite(image, "image")
      File.write(file, %(![A "quiet" harbour](my photo.jpg "Dawn & dusk")\n))

      client = FakeClient.new(api_key: "secret", base_url: "https://api.pagecord.com")
      post_file = PagecordCLI::PostFile.new(file)

      assert_equal %(<action-text-attachment sgid="sgid-123" alt="A &quot;quiet&quot; harbour" caption="Dawn &amp; dusk"></action-text-attachment>\n),
        post_file.content_for("olly", client: client)
    ensure
      FakeClient.reset!
    end
  end

  def test_markdown_image_paths_are_percent_decoded
    Dir.mktmpdir do |dir|
      File.binwrite(File.join(dir, "my photo.jpg"), "image")
      File.binwrite(File.join(dir, "100%.jpg"), "image")
      file = File.join(dir, "hello.md")
      File.write(file, "![](my%20photo.jpg)\n![](100%.jpg)\n")

      client = FakeClient.new(api_key: "secret", base_url: "https://api.pagecord.com")
      post_file = PagecordCLI::PostFile.new(file)

      assert_equal %(<action-text-attachment sgid="sgid-123"></action-text-attachment>\n) * 2,
        post_file.content_for("olly", client: client)
    ensure
      FakeClient.reset!
    end
  end

  def test_unsupported_local_image_syntax_is_left_alone
    Dir.mktmpdir do |dir|
      file = File.join(dir, "hello.md")
      pdf = File.join(dir, "file.pdf")
      File.binwrite(pdf, "pdf")
      File.write(file, "Look ![PDF](file.pdf)\n")

      client = FakeClient.new(api_key: "secret", base_url: "https://api.pagecord.com")
      post_file = PagecordCLI::PostFile.new(file)

      assert_equal "Look ![PDF](file.pdf)\n", post_file.content_for("olly", client: client)
      assert_empty FakeClient.requests
    ensure
      FakeClient.reset!
    end
  end
end
