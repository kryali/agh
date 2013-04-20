require 'alfred'
require 'json'
require 'net/http'
require "link_header"

=begin

  uid
  The uid attribute is a value that is used to help Alfred learn about your results. You know that Alfred learns based on the items you use the most. That same mechanism can be used in feedback results. Give your results a unique identifier and Alfred will learn which ones you use the most and prioritize them by moving them up in the result list.
   
  arg
  The arg attribute is the value that is passed to the next portion of the workflow when the result item is selected in the Alfred results list. So if you pressed enter on the sample item above, the value 'r96664' would be passed to a shell script, applescript, or any of the other Action items.
   
  type
  The type attribute allows you to specify what type of result you are generating. Currently, the only value available for this attribute is file. This will allow you to specify that the feedback item is a file and allows you to use Result Actions on the feedback item.
   
   
  valid ( optional - Defaults to 'yes' )
  The valid attribute allows you to specify whether or not the result item is a "valid", actionable item. Valid values for this attribute are 'yes' or 'no'. By setting a result's valid attribute to 'no', the item won't be actioned when this item is selected and you press Return. This allows you to provide result items that are only for information or for help in auto completing information (See autocomplete flag below).
   
  autocomplete ( optional - Only available when valid = no )
  The autocomplete attribute is only used when the valid attribute has been set to 'no'. When attempting to action an item that has the valid attribute set to 'no' and an autocomplete value is specified, the autocomplete value is inserted into the Alfred window. When using this attribute, the arg attribute is ignored.
   
  Elements
   
  title
  The title element is the value that is shown in large text as the title for the result item. This is the main text/title shown in the results list.
   
  subtitle
  The subtitle element is the value shown under the title in the results list. When performing normal searches within Alfred, this is the area where you would normally see the file path.
   
  icon ( optional - If not icon value is available, the icon will be blank. If the icon element is not present, a folder icon will be used )
  The icon element allows you to specify the icon to use for your result item. This can be a file located in your workflow directory, an icon of a file type on your local machine, or the icon of a specific file on your system. To use the icons of a specific file type or another folder/file, you must provide a type attribute to the icon item. 
  Example: <icon type="fileicon">/Applications</icon> - Use the icon associated to /Applications
  Example: <icon type="filetype">public.folder</icon> - Use the public.folder (default folder) icon

=end

HOST = "https://git.squareup.com"
API_PATH = "/api/v3/"

class Cache
  DATA_DIR = File.expand_path(File.dirname(__FILE__), "data")

  def get(name)
    return nil unless File.exists? "#{DATA_DIR}/name"
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

  def self.get_all_repos(http, get_all)
    data = []
    response = get(http, "repositories")
    data = data + JSON.parse(response.body)
    return data unless get_all

    while next_link = get_next_link(response)
      puts "fetching #{next_link}.."
      response = get(http, clean_up_link(next_link))
      data = data + JSON.parse(response.body)
    end
    data
  end

  def self.fetch_and_save(get_all)
    uri = URI(HOST)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    get_all_repos(http, get_all)
  end

  def self.perform(get_all)
    fetch_and_save(get_all)
  end
end

Alfred.with_friendly_error do |alfred|
  repos = GetReposJob.perform(false)
  feedback = alfred.feedback
  repos.each do |repo|
    feedback.add_item({
          :uid      => repo["name"],
          :title    => repo["name"],
          :subtitle => repo["full_name"],
          :arg      => repo["name"],
          :valid    => true
        })
  end
  puts feedback.to_xml
end
