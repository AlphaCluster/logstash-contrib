require "logstash/outputs/base"
require "em-jack"

class LogStash::Outputs::Beanstalk < LogStash::Outputs::Base
  def initialize(url, config={}, &block)
    super

    @ttr = @urlopts["ttr"] || 300;
    if @url.path == "" or @url.path == "/"
      raise "must specify a tube for beanstalk output"
    end
  end

  def register
    tube = @url.path[1..-1] # Skip leading '/'
    port = @url.port || 11300
    @beanstalk = EMJack::Connection.new(:host => @url.host,
                                        :port => port,
                                        :tube => tube)
  end # def register

  def receive(event)
    @beanstalk.put(event.to_json, :ttr => @ttr)
  end # def receive
end # class LogStash::Outputs::Beanstalk
