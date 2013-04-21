require "logger"
LOGGER = Logger.new(DATA_DIR = File.expand_path(File.dirname(__FILE__), "debug.log"))

require "uri"
require 'net/http'
require 'alfred'
require "link_header"
require "json"

HOST = "https://git.squareup.com"
API_PATH = "/api/v3/"
REPOS_FILE = "repos.bin"
GITHUB_ICON = {:type => "default", :name => "github_32.png"}
THREADS = []

class Cache
  DATA_DIR = File.expand_path(File.dirname(__FILE__), "data")

  def self.path(name)
    "#{DATA_DIR}/#{name}"
  end

  def self.deserialize(data)
    Marshal.load(data)
  end

  def self.serialize(data)
    Marshal.dump(data)
  end

  def self.get(name)
    return nil unless File.exists? path(name)
    file = File.open(path(name), "r")
    start_time = Time.now
    contents = file.read
    file.close
    data = deserialize(contents)
    end_time = Time.now
    LOGGER.debug "cache read time #{(end_time - start_time) * 1000}ms"
    data
  end

  def self.put(name, data)
    saved = {
      :created_at => Time.now.to_i,
      :data => data
    }
    file = File.new(path(name), "w+")
    file.write(serialize(saved))
    file.close
  end
end

class GetReposJob
  def self.get(http, path)
    request = Net::HTTP::Get.new("#{API_PATH}#{path}")
    http.request(request)
  end

  def self.get_next_link(response)
    link_fields = response.header.get_fields("link")
    return nil unless link_fields

    link_fields.each do |link_field|
      LinkHeader.parse(link_field).links.each do |link|
        return link.href if link["rel"] == "next"
      end
    end
    return nil
  end

  def self.clean_up_link(href)
    href.gsub(HOST, '').gsub(API_PATH, '')
  end

  def self.get_repos(http, get_all)
    data = []
    response = get(http, "repositories")
    data = data + JSON.parse(response.body)
    return data unless get_all

    while next_link = get_next_link(response)
      LOGGER.debug "fetching #{next_link}.."
      response = get(http, clean_up_link(next_link))
      data = data + JSON.parse(response.body)
    end
    LOGGER.debug "done fetching"
    data
  end

  def self.fetch_and_save(get_all)
    uri = URI(HOST)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    data = get_repos(http, get_all)
    Cache.put(REPOS_FILE, data)
    data
  end

  def self.perform(get_all)
    cache = Cache.get(REPOS_FILE)
    if cache
      if (Time.now.to_i - cache[:created_at]) > 300 # 5 minute
        LOGGER.debug "Busting cache, its too old!"
        THREADS << Thread.new{ 
          fetch_and_save(get_all) 
        }
      end
      return cache[:data]
    end
    LOGGER.debug "No cache, slow fetch"
    fetch_and_save(get_all)
  end
end

query = ARGV.first.strip

Alfred.with_friendly_error do |alfred|
  alfred.with_rescue_feedback = true
  repos = GetReposJob.perform(true)
  feedback = alfred.feedback
  repos.each do |repo|
    if repo["name"].include?(query) or repo["full_name"].include?(query) 
      feedback.add_item({
            :uid      => repo["full_name"],
            :title    => repo["full_name"],
            :subtitle => repo["description"],
            :arg      => repo["html_url"],
            :valid    => true,
            :icon     => GITHUB_ICON
          })
    end
  end
  puts feedback.to_alfred
end
