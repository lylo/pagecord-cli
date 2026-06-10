# frozen_string_literal: true

require "digest"

module PagecordCLI
  class ImageUploads
    MARKDOWN_IMAGE = /!\[([^\]]*)\]\(([^)]+)\)/
    OBSIDIAN_IMAGE = /!\[\[([^\]]+)\]\]/
    IMAGE_EXTENSIONS = /\.(jpe?g|png|gif|webp)\z/i

    attr_reader :content, :file_path, :metadata, :blog, :client

    def initialize(content, file_path:, metadata:, blog:, client:)
      @content = content
      @file_path = file_path
      @metadata = metadata
      @blog = blog
      @client = client
    end

    def process
      with_markdown_images = content.gsub(MARKDOWN_IMAGE) do |match|
        path = Regexp.last_match(2)
        local_path?(path) ? attachment_tag_for(path) : match
      end

      with_markdown_images.gsub(OBSIDIAN_IMAGE) do |match|
        path = Regexp.last_match(1)
        local_path?(path) ? attachment_tag_for(path) : match
      end
    end

    private

      def attachment_tag_for(path)
        sgid = cached_sgid(path) || upload(path)
        %(<action-text-attachment sgid="#{sgid}"></action-text-attachment>)
      end

      def cached_sgid(path)
        cache = attachment_cache[filename(path)]
        return unless cache
        return unless cache["hash"] == checksum(absolute_path(path))

        cache["sgid"]
      end

      def upload(path)
        result = client.upload_attachment(absolute_path(path))
        sgid = result.fetch("attachable_sgid")

        attachment_cache[filename(path)] = {
          "hash" => checksum(absolute_path(path)),
          "sgid" => sgid
        }

        sgid
      end

      def attachment_cache
        metadata["pagecord_attachments"] ||= {}
      end

      def local_path?(path)
        return false if path.match?(%r{\A[a-z][a-z0-9+.-]*:}i)
        return false if path.start_with?("#", "/")
        return false unless path.match?(IMAGE_EXTENSIONS)

        File.file?(absolute_path(path))
      end

      def absolute_path(path)
        File.expand_path(path, File.dirname(file_path))
      end

      def checksum(path)
        Digest::SHA256.file(path).hexdigest[0, 16]
      end

      def filename(path)
        File.basename(path)
      end
  end
end
