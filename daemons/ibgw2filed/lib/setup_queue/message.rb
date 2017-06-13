require "json"
require_relative "../log_helper"

module SetupQueue
  class Message
    include LogHelper

    def initialize(params)
      @command = params[:command]
      @data    = params[:data]
    end

    def to_json
      {command: @command, data: @data}.to_json
    end

    def self.decode(json_msg)
      warn "SMZ: decode(#{json_msg})"
      msg = from_json(json_msg)
      warn "SMZ: msg = #{msg}"
      [msg[:command],msg[:data]]
    rescue
      warn "SetupQueue::Message cannot be decoded, message: #{json_msg}"
      ["nop",""]
    end

    private

    def self.from_json(json_msg)
      JSON.parse(json_msg, symbolize_names: true)
    rescue
      warn "SetupQueue::Message cannot parse json message: #{json_msg}"
    end
  end
end
