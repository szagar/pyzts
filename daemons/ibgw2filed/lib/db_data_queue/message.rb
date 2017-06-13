require "json"
require "log_helper"

module DbDataQueue
  class Message
    include LogHelper

    def initialize(params)
      @command = params[:command]
      @data    = params[:data]
    end

    def json_msg
      #msg = {command: @command, data: @data}.to_json
      msg = hash_msg.to_json
      #puts "Message#json_msg: #{msg}"
      msg
    end

    def hash_msg
      {command: @command, data: @data}
    end

    def self.decode(json_msg)
      msg = from_json(json_msg)
      [msg[:command],msg[:data]]
    rescue
      warn "DbDataQueue::Message cannot be decoded, message: #{json_msg}"
      ["nop",""]
    end

    private

    def self.from_json(json_msg)
      JSON.parse(json_msg, symbolize_names: true)
    rescue
      warn "DbDataQueue::Message cannot parse json message: #{json_msg}"
    end
  end
end
