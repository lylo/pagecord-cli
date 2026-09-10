# frozen_string_literal: true

require "minitest/autorun"
require "stringio"
require "tmpdir"

require_relative "../lib/pagecord_cli"

ENV.delete("PAGECORD_BLOG")

class FakeClient
  Error = PagecordCLI::Client::Error

  Request = Struct.new(:api_key, :base_url, :action, :args, keyword_init: true)

  class << self
    attr_accessor :requests, :upload_token, :verify_error, :update_error, :settings

    def reset!
      self.requests = []
      self.upload_token = "sgid-123"
      self.verify_error = nil
      self.update_error = nil
      self.settings = { "theme" => "base", "font" => "sans", "custom_css" => "body { color: red }", "custom_head_html" => nil }
    end
  end

  reset!

  attr_reader :api_key, :base_url

  def initialize(api_key:, base_url:)
    @api_key = api_key
    @base_url = base_url
  end

  def verify!
    raise self.class.verify_error if self.class.verify_error

    self.class.requests << Request.new(api_key: api_key, base_url: base_url, action: :verify, args: [])
    true
  end

  def create_post(params)
    self.class.requests << Request.new(api_key: api_key, base_url: base_url, action: :create_post, args: [ params ])
    { "token" => "created-token" }
  end

  def update_post(token, params)
    raise self.class.update_error if self.class.update_error

    self.class.requests << Request.new(api_key: api_key, base_url: base_url, action: :update_post, args: [ token, params ])
    { "token" => token }
  end

  def appearance
    record(:appearance)
    self.class.settings
  end

  def update_appearance(params)
    record(:update_appearance, params)
    self.class.settings.merge(params)
  end

  def custom_code
    record(:custom_code)
    self.class.settings
  end

  def update_custom_code(params)
    record(:update_custom_code, params)
    self.class.settings.merge(params)
  end

  def upload_attachment(path)
    self.class.requests << Request.new(api_key: api_key, base_url: base_url, action: :upload_attachment, args: [ path ])
    { "attachable_sgid" => self.class.upload_token }
  end

  private

    def record(action, *args)
      self.class.requests << Request.new(api_key: api_key, base_url: base_url, action: action, args: args)
    end
end

module ClientSwap
  def with_fake_client
    original = PagecordCLI.send(:remove_const, :Client)
    PagecordCLI.const_set(:Client, FakeClient)
    FakeClient.reset!
    yield
  ensure
    PagecordCLI.send(:remove_const, :Client)
    PagecordCLI.const_set(:Client, original)
  end
end
