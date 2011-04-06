#!/usr/bin/env ruby
require 'fastercsv'
require 'yaml'
require 'curb'
require 'active_support'

class String
  def xml_escape
    gsub(/[&<>'"]/) do |char|
      case char
      when '&' then '&amp;'
      when '<' then '&lt;'
      when '>' then '&gt;'
      when "'" then '&apos;'
      when '"' then '&quote;'
      end
    end
  end
end

class UnfuddleTicket

  def initialize(redmine_ticket)
    @config = YAML.load_file "unfuddle.yml"
    @redmine  = redmine_ticket.to_hash
    @unfuddle = {}
    @redmine.map do |k,v|
      self[k] = v
    end
    @curl = Curl::Easy.new
    @curl.userpwd = "#{@config[:username]}:#{@config[:password]}"
  end

  def post
    @curl.headers['Content-type'] = @curl.headers['Accept'] = 'application/xml'
    @curl.url = "http#{@config[:ssl?] ? 's' : ''}://#{@config[:subdomain]}.unfuddle.com/api/v1/projects/#{@config[:project_id]}/tickets"
    @curl.http_post self.to_xml
    if @curl.response_code == 201
      puts "Created ticket #{self['summary']}"
    else
      warn "Failed to create ticket #{self['summary']}"
    end
  end

  def [](key)
    @unfuddle[key]
  end

  def []=(key,value)
    case key
    when '#'
      @unfuddle["field1-value"] = value
      # I added "RedMine #" as a custom field due to http://unfuddle.com/community/forums/6/topics/624
    when 'Status'
      case value
      when "New"
        @unfuddle['status'], @unfuddle['resolution'] = 'new',''
      when "Blocked"
        @unfuddle['status'], @unfuddle['resolution'] = 'resolved','postponed'
      when "Duplicate"
        @unfuddle['status'], @unfuddle['resolution'] = 'resolved','duplicate'
      when "Won't Fix"
        @unfuddle['status'], @unfuddle['resolution'] = 'resolved','duplicate'
      when "Works For Me"
        @unfuddle['status'], @unfuddle['resolution'] = 'resolved','works_for_me'
      when "Resolved"
        @unfuddle['status'], @unfuddle['resolution'] = 'resolved','fixed'
      when "Delivered"
        @unfuddle['status'], @unfuddle['resolution'] = 'closed','fixed'
      when "In Progress"
        @unfuddle['status'], @unfuddle['resolution'] = 'accepted',''
      else
        raise UnrecognizedRedmineStatus, "Unrecognized redmine status: #{value}"
      end
    when 'Project'
      nil # Do nothing
    when 'Tracker'
      nil
    when 'Priority'
      case value
      when "Urgent"
        @unfuddle['priority'] = '4'
      when "High"
        @unfuddle['priority'] = '3'
      when "Normal"
        @unfuddle['priority'] = '2'
      when "Immediate"
        @unfuddle['priority'] = '5'
      when "Low"
        @unfuddle['priority'] = '1'
      else
        raise UnrecognizedRedminePriority, "Unrecognized redmine priority: #{value}"
      end
    when 'Subject'
      @unfuddle['summary'] = value.xml_escape
    when 'Assigned to'
      nil # Unfuddle is looking for assignee-ids, too much effort and it no longer matters
    when 'Category'
      nil # No data in dump
    when 'Target version'
      nil
    when 'Author'
      nil
    when 'Start'
      nil
    when 'Due date'
      @unfuddle['due-on'] = value
    when '% Done'
      nil
    when 'Estimated time'
      nil
    when 'Created'
      nil # Read-only field in unfuddle
    when 'Updated'
      nil # Don't care
    when 'Description'
      @unfuddle['description'] = value.xml_escape
    else
      raise UnrecognizedRedmineField, "Unrecognized redmine field: #{key}"
    end
  end

  def to_xml
    @unfuddle.to_xml(:root => :ticket, :skip_instruct => true)
  end
end

if ARGV.empty?
  puts "USAGE: #{__FILE__} redmine_dump.csv" 
  exit
else
  FCSV.foreach("#{ARGV.shift}", :headers => true) do |ticket|
    UnfuddleTicket.new(ticket).post
  end
end
