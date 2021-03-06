require 'rsolr'
require 'ead_parser'
require 'rest-client'
require 'open-uri'
require 'geocoder'
require 'document_types'

namespace :bassi do
  desc "Parse EAD File"
  task :"parse-ead" do
    ead = EadParser.new("#{Rails.root}/data/bassi-ead.xml")
    solr = Blacklight.solr
    documents = solrize_ead ead
    unless documents.blank?
      documents.each { |doc| solr.add doc }
      solr.commit
    end
  end

  desc "Generate index HTML"
  task :"generate-index" do
    f = File.open("#{Rails.root}/data/bassi-ead.xml")
    doc = Nokogiri::XML(f)
    f.close
    doc.root.search('indexentry').each do |node|
      node.children.each do |child|
        if child.class == Nokogiri::XML::Element
          result = "<li><a href=\"/it/catalog?q=#{URI.encode(child.content)}\">#{child.content}</a></li>"
          puts result
        end
      end
    end
  end

  desc "Generate tab-delimited list of item identifiers"
  task :"generate-item-list" do
    ead = EadParser.new("#{Rails.root}/data/bassi-ead.xml")
    list_items ead
  end
end

def solrize_ead(ead)
  documents = []
  folders = []
  ead.reader.archdesc.dsc.c01s.each do |c01|
    c01.c02s.each do |c02|
      unless exclude_document?(c02)
        containers = containers_for_collection(c02)
        if folders.include? container_key(containers)
          documents << document_from_contents(ead, c02, c01, c01, containers)
        else
          # handle the case where the folder level object IS the content
          if c02.dao.try(:href)
            documents << folder_from_contents(c02, containers, c01, :folder_is_content => true)
            documents << document_from_contents(ead, c02, c01, c01, containers)
          else
            documents << folder_from_contents(c02, containers, c01)
          end
          folders << container_key(containers) unless folders.include? container_key(containers)
        end
      end
      c02.c03s.each do |c03|
        unless exclude_document?(c03)
          containers = containers_for_collection(c03)
          if folders.include? container_key(containers)
            documents << document_from_contents(ead, c03, c02, c01, containers)
          else
            # handle the case where the folder level object IS the content
            if c03.dao.try(:href)
              documents << folder_from_contents(c02, containers, c01, :folder_is_content => true)
              documents << document_from_contents(ead, c03, c02, c01, containers)
            else
              documents << folder_from_contents(c02, containers, c01)
            end
            folders << container_key(containers) unless folders.include? container_key(containers)
          end
        end
        c03.c04s.each do |c04|
          next if exclude_document?(c04)
          containers = containers_for_collection(c04)
          if folders.include? container_key(containers)
            documents << document_from_contents(ead, c04, c03, c01, containers)
          else
            # handle the case where the folder level object IS the content
            if c04.dao.try(:href)
              documents << folder_from_contents(c02, containers, c01, :folder_is_content => true)
              documents << document_from_contents(ead, c04, c03, c01, containers)
            else
              documents << folder_from_contents(c02, containers, c01)
            end
            folders << container_key(containers) unless folders.include? container_key(containers)
          end
        end
      end
    end
    dates = dates_from_unitdate(c01.did)
    documents << { :id => c01.identifier,
                   :title_tsi => [clean_string(c01.did.unittitle), dates.try(:date)].join(" "),
                   :level_ssim => c01.level,
                   :description_tsim => description(c01),
                   :purl_ssi => c01.dao.try(:href) }
  end
  documents
end

# used for debugging ead hierarchy.
def all_items(ead)
  ead.reader.archdesc.dsc.c01s.each do |c01|
    c01.c02s.each do |c02|
      puts "#{c01.level}:#{c01.identifier} -> #{c02.level}:#{c02.identifier} -> #{c02.dao.try(:href)} | #{print_types(c02)}"
      c02.c03s.each do |c03|
        puts "#{c01.level}:#{c01.identifier} -> #{c02.level}:#{c02.identifier} -> #{c03.level}:#{c03.identifier} -> #{c03.dao.try(:href)} | #{print_types(c03)}"
        c03.c04s.each do |c04|
          puts "#{c01.level}:#{c01.identifier} -> #{c02.level}:#{c02.identifier} -> #{c03.level}:#{c03.identifier} -> #{c04.level}:#{c04.identifier} -> #{c04.dao.try(:href)} | #{print_types(c04)}"
        end
      end
    end
    puts "\n"
  end
end

# tab-delimited version of all_items method
def list_items(ead)
  ead.reader.archdesc.dsc.c01s.each do |c01|
    c01.c02s.each do |c02|
      puts "#{c01.level}:#{c01.identifier} \t #{c02.level}:#{c02.identifier} \t #{c02.dao.try(:href)} \t #{print_types(c02)}"
      c02.c03s.each do |c03|
        puts "#{c01.level}:#{c01.identifier} \t #{c02.level}:#{c02.identifier} \t #{c03.level}:#{c03.identifier} \t #{c03.dao.try(:href)} \t #{print_types(c03)}"
        c03.c04s.each do |c04|
          puts "#{c01.level}:#{c01.identifier} \t #{c02.level}:#{c02.identifier} \t #{c03.level}:#{c03.identifier} \t #{c04.level}:#{c04.identifier} \t #{c04.dao.try(:href)} \t #{print_types(c04)}"
        end
      end
    end
    puts "\n"
  end
end

def print_types(c)
  containers_for_collection(c).inspect
end

def clean_string(s)
  str = (s.class == Array ? s.join(' ') : s)
  str.gsub(/\s+/, " ").strip unless str.nil?
end

def container_key(containers)
  return nil if containers.blank?
  "box#{containers['Box']}-folder#{containers['Folder']}"
end

def containers_for_collection(c)
  types = {}
  c.did.container_types.each_with_index do |type, ix|
    types[type] = c.did.containers[ix]
  end
  types
end

def description(content)
  contents = []
  content.odd.each do |odd|
    contents << clean_string(odd.try(:p))
  end
  unless content.scopecontent.nil?
    content.scopecontent.each do |scope|
      contents << clean_string(scope.try(:ps))
    end
  end
  contents
end

def dates_from_unitdate(did)
  dates = OpenStruct.new
  return dates unless did.unitdate
  dates.date = did.unitdate.try(:value)
  if did.unitdate.try(:normal)
    dates.start_year = did.unitdate.normal.split("/").first
    dates.end_year   = did.unitdate.normal.split("/").last
  end
  dates
end

def date_range_from_unitdate(dates)
  return nil unless dates.try(:start_year) && dates.try(:end_year)
  (dates.start_year..dates.end_year).to_a
end

def image_ids_from_purl(purl)
  return [] unless purl
  result = RestClient.get "#{purl}.xml" # now get the content metadata from the PURL page and index the filenames
  doc = Nokogiri::XML(result)
  cm = doc.xpath('//contentMetadata')
  cm.xpath('//file').map { |file| file.attributes['id'] }
rescue RestClient::Exception => e # we might get a 404 if the object is not yet accessioned...
  warn "Error fetching '#{purl.xml}': #{e.message}"
end

def druid_from_purl(purl)
  purl ? /[A-Za-z]{2}[0-9]{3}[A-Za-z]{2}[0-9]{4}/.match(purl).to_s : nil
end

def exclude_document?(content)
  %w(ref961 ref975 ref1525 ref1571).include?(content.identifier)
end

def folder_from_contents(content, containers, series, options = {})
  dates = dates_from_unitdate(content.did)
  { :id                   => container_key(containers),
    :title_tsi            => [clean_string(content.did.unittitle), dates.try(:date)].join(" "),
    :level_ssim           => 'Folder',
    :box_ssim             => containers['Box'],
    :folder_ssim          => containers['Folder'],
    :extent_ssim          => content.did.physdesc.try(:extent),
    :unit_date_ssim       => dates.try(:date),
    :begin_year_itsim     => dates.try(:start_year),
    :end_year_itsim       => dates.try(:end_year),
    :description_tsim     => description(content),
    :series_ssim          => series.identifier,
    :folder_is_content_bi => options[:folder_is_content] }
end

def document_from_contents(ead, content, direct_parent, series, containers)
  unittitle_parts = ead.unittitle_parts(content.identifier)
  dates = dates_from_unitdate(content.did)
  cached_lookup = {}
  coordinates = []
  unittitle_parts.geogname.each do |location_name|
    next if BassiVeratti::Application.config.no_geocode.include?(location_name)
    lookup_name = BassiVeratti::Application.config.geocode_swap[location_name] || location_name
    results = Geocoder.search(lookup_name, :cache => cached_lookup)
    sleep 0.1 # don't overload the geolookup API
    coordinates << "#{location_name}|#{results.first.latitude}|#{results.first.longitude}" unless results.empty?
  end

  purl = content.dao.try(:href)
  druid = druid_from_purl(purl)
  imageids = image_ids_from_purl(purl)

  { :id => content.identifier,
    :title_tsi => [clean_string(content.did.unittitle), dates.try(:date)].join(" "),
    :en_document_types_ssim => DocumentTypes.document_types[content.identifier] ?
                               DocumentTypes.document_types[content.identifier][:en] :
                               nil,
    :it_document_types_ssim => DocumentTypes.document_types[content.identifier] ?
                               DocumentTypes.document_types[content.identifier][:it] :
                               nil,
    :level_ssim => content.level,
    :direct_parent_ssim => direct_parent.identifier,
    :direct_parent_level_ssim => direct_parent.level,
    :box_ssim => containers["Box"],
    :folder_ssim => containers["Folder"],
    :parent_folder_ssim => container_key(containers),
    :series_ssim => series.identifier,
    :purl_ssi => purl,
    :druid_ssi => druid,
    :image_id_ssim => imageids,
    :extent_ssim => content.did.physdesc.extent,
    :description_tsim => description(content),
    :personal_name_ssim => unittitle_parts.persname,
    :geographic_name_ssim => unittitle_parts.geogname,
    :coordinates_ssim => coordinates,
    :corporate_name_ssim => unittitle_parts.corpname,
    :family_name_ssim => unittitle_parts.famname,
    :date_range_itim => date_range_from_unitdate(dates),
    :unit_date_ssim => dates.try(:date),
    :begin_year_itsim => dates.try(:start_year),
    :end_year_itsim => dates.try(:end_year) }
end
