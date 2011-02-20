require "amqp" # rubygem 'amqp'
require "logstash/outputs/base"
require "logstash/namespace"
require "mq" # rubygem 'amqp'
require "cgi"

class LogStash::Outputs::Amqp < LogStash::Outputs::Base
  MQTYPES = [ "fanout", "queue", "topic" ]

  config :host => :string
  config :queue_type => :string
  config :queue_name => :string

  public
  def initialize(url, config={}, &block)
    super

    # Handle path /<vhost>/<type>/<name> or /<type>/<name>
    # vhost allowed to contain slashes
    if @url.path =~ %r{^/((.*)/)?([^/]+)/([^/]+)}
      unused, @vhost, @mqtype, @name = $~.captures
    else
      raise "amqp urls must have a path of /<type>/name or /vhost/<type>/name where <type> is #{MQTYPES.join(", ")}"
    end

    if !MQTYPES.include?(@mqtype)
      raise "Invalid type '#{@mqtype}' must be one of #{MQTYPES.join(", ")}"
    end
  end # def initialize

  public
  def register
    @logger.info("Registering output #{@url}")
    query_args = @url.query ? CGI.parse(@url.query) : {}
    amqpsettings = {
      :vhost => (@vhost or "/"),
      :host => @url.host,
      :port => (@url.port or 5672),
    }
    amqpsettings[:user] = @url.user if @url.user
    amqpsettings[:pass] = @url.password if @url.password
    amqpsettings[:logging] = query_args.include? "debug"
    @logger.debug("Connecting with AMQP settings #{amqpsettings.inspect} to set up #{@mqtype.inspect} queue #{@name.inspect}")
    @amqp = AMQP.connect(amqpsettings)
    @mq = MQ.new(@amqp)
    @target = nil

    case @mqtype
      when "fanout"
        @target = @mq.fanout(@name)
      when "queue"
        @target = @mq.queue(@name, :durable => @urlopts["durable"] ? true : false)
      when "topic"
        @target = @mq.topic(@name)
    end # case @mqtype
  end # def register

  public
  def receive(event)
    @logger.debug(["Sending event", { :url => @url, :event => event }])
    @target.publish(event.to_json)
  end # def receive

  # This is used by the ElasticSearch AMQP/River output.
  public
  def receive_raw(raw)
    if @target == nil
      raise "had trouble registering AMQP URL #{@url.to_s}, @target is nil"
    end

    @target.publish(raw)
  end # def receive_raw
end # class LogStash::Outputs::Amqp
