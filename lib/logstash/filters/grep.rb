require "logstash/filters/base"
require "logstash/namespace"

# Grep filter.
#
# Useful for:
# * Dropping events
# * Tagging events
# * Adding static fields
#
# Events not matched ar dropped. If 'negate' is set to true (defaults false), then
# matching events are dropped.
#
# Config:
# - grep:
#   <type>:
#     - match:
#         <field>: <regexp>
#       negate: true/false
#       add_fields:
#         <field>: <value>
#       add_tags:
#         - tag1
#         - tag2
#
class LogStash::Filters::Grep < LogStash::Filters::Base

  config_name "grep"
  config :negate, :validate => :boolean
  config :match, :validate => :hash
  config :add_fields, :validate => :hash
  config :add_tags, :validate => :array

  # Config for grep is:
  #   fieldname: pattern
  #   Allow arbitrary keys for this config.
  config /[A-Za-z0-9_-]+/, :validate => :string


  public
  def initialize(params)
    super

    @add_fields ||= {}
    @add_tags ||= []
  end # def initialize

  public
  def register
    @patterns = Hash.new { |h,k| h[k] = [] }
    @match.each do |field, pattern|
      re = Regexp.new(pattern)
      @patterns[field] << re
      @logger.debug(["grep: #{@type}/#{field}", pattern, re])
    end # @config.each
  end # def register

  public
  def filter(event)
    if event.type != @type
      @logger.debug("grep: skipping type #{event.type} from #{event.source}")
      event.cancel
      return
    end

    @logger.debug(["Running grep filter", event.to_hash, config])
    matched = false
    @patterns.each do |field, regexes|
      if !event[field]
        @logger.debug(["Skipping match object, field not present", field,
                      event, event[field]])
        next
      end

      # For each match object, we have to match everything in order to
      # apply any fields/tags.
      match_count = 0
      match_want = 0
      regexes.each do |re|
        match_want += 1

        # Events without this field, with negate enabled, count as a match.
        if event[field].nil? and @negate == true
          match_count += 1
        end

        (event[field].is_a?(Array) ? event[field] : [event[field]]).each do |value|
          if @negate
            @logger.debug("want negate match")
            next if re.match(value)
            @logger.debug(["grep not-matched (negate requsted)", { field => value }])
          else
            @logger.debug(["trying regex", re, value])
            next unless re.match(value)
            @logger.debug(["grep matched", { field => value }])
          end
          match_count += 1
          break
        end # each value in event[field]
      end # regexes.each

      if match_count == match_want
        matched = true
        @logger.debug("matched all fields (#{match_count})")

        @add_fields.each do |field, value|
          event[field] ||= []
          event[field] << event.sprintf(value)
          @logger.debug("grep: adding #{value} to field #{field}")
        end

        @add_tags.each do |tag|
          event.tags << event.sprintf(tag)
          @logger.debug("grep: adding tag #{tag}")
        end
      else
        @logger.debug("match block failed " \
                      "(#{match_count}/#{match_want} matches)")
        event.cancel
      end # match["match"].each
    end # config.each

    if not matched
      @logger.debug("grep: dropping event, no matches")
      event.cancel
      return
    end

    @logger.debug(["Event after grep filter", event.to_hash])
  end # def filter
end # class LogStash::Filters::Grep
