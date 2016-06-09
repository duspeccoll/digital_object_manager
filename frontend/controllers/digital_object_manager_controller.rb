class DigitalObjectManagerController < ApplicationController

	require 'csv'
	require 'zip'
	require 'net/http'

	set_access_control "view_repository" => [:index, :download],
                     "update_digital_object_record" => [:update]

	def index
	end

	def download
		datafile = params[:datafile]
		case datafile.content_type
		when 'text/plain', 'text/csv', 'application/vnd.ms-excel'
			output = write_zip(datafile)
			output.rewind
			send_data output.read, filename: "mods_download_#{Time.now.strftime("%Y%m%d_%H%M%S")}.zip"
		else
			flash[:error] = I18n.t("plugins.digital_object_manager.messages.invalid_mime_type", :filename => "#{datafile.original_filename}")
			redirect_to :controller => :digital_object_manager, :action => :index
		end
	end

	def update
		datafile = params[:datafile]
		case datafile.content_type
		when 'text/plain', 'text/csv', 'application/vnd.ms-excel'
			file = update_records(datafile)
			file.rewind
			send_data file.read, filename: "activity_log.txt"
			file.close
			File.delete('activity_log.txt') if File.exist?('activity_log.txt')
		else
			flash[:error] = I18n.t("plugins.digital_object_manager.messages.invalid_mime_type", :filename => "#{datafile.original_filename}")
			redirect_to :controller => :digital_object_manager, :action => :index
		end
	end

	private

	def write_zip(datafile)
		output = Zip::OutputStream.write_buffer do |zos|
			log = Array.new
			datafile.read.each_line do |line|
				CSV.parse(line) do |row|
					search_data = Search.all(session[:repo_id], { 'q' => row[0] })
					if search_data.results?
						search_data['results'].each do |result|
							obj = JSON.parse(result['json'])
							if obj['component_id'] = row[0]
								mods = download_mods(obj)
								unless mods.nil?
									zos.put_next_entry "#{row[0].gsub(/\./, '_')}.xml"
									zos.print mods
									log.push("#{row[0].gsub(/\./, '_')}.xml downloaded")
								end
								log.push("#{row[0]} found but no MODS record downloaded") if mods.nil?
							end
						end
					else
						log.push("#{row[0]} not found in ArchivesSpace")
					end
				end
			end
			zos.put_next_entry "action_log.txt"
			log.each do |entry|
				zos.puts entry
			end
		end
		return output
	end

	def update_records(datafile)
		file = File.new('activity_log.txt', 'a+')
		datafile.read.each_line do |line|
			CSV.parse(line) do |row|
				log = "#{row[0]}: "
				if row.length != 2
					log << "Row must contain exactly two elements. No action taken."
				else
					# limit our search to archival objects so we only get item records
					search_data = Search.all(session[:repo_id], {
						"q" => row[0], "filter_term[]" => { "primary_type" => "archival_object" }.to_json
					})
					if search_data.results?
						search_data['results'].each do |result|
							obj = JSON.parse(result['json'])
							if obj['component_id'] = row[0]
								if row[1] =~ /^codu:\d+$/
									item = JSONModel::HTTP.get_json(obj['uri'])

									# working with Islandora links on the item record
									if item['external_documents'].empty?
										item, log = add_item_link(item, row[1], log)
									else
										if item['external_documents'].map{ |doc| doc['title'] }.include?("#{I18n.t("plugins.digital_object_manager.defaults.link_title")}")
											item, log = update_item_link(item, row[1], log)
										else
											item, log = add_item_link(item, row[1], log)
										end
									end

									# working with digital object instances
									if item['instances'].empty?
										item, log = add_digital_object(item, row[1], log)
									else
										if item['instances'].map{ |i| i['instance_type'] }.include?("digital_object")
											item['instances'].each do |instance|
												log = update_digital_object(instance, row[1], log) if instance['instance_type'] == "digital_object"
											end
										else
											item, log = add_digital_object(item, row[1], log)
										end
									end

									JSONModel::HTTP.post_json(URI("#{JSONModel::HTTP.backend_url}#{obj['uri']}"), item.to_json)
								else
									log << "No action taken. Ensure that your handle is properly formed."
								end
							end
						end
					end
				end
				file.puts(log)
			end
		end
		return file
	end

	def download_mods(obj)
		id = obj['uri'].gsub(/\/repositories\/#{session[:repo_id]}\/archival_objects\//, '')
		url = URI("#{JSONModel::HTTP.backend_url}/repositories/#{session[:repo_id]}/archival_objects/mods/#{id}.xml")
		req = Net::HTTP::Get.new(url.request_uri)
		req['X-ArchivesSpace-Session'] = Thread.current[:backend_session]
		resp = Net::HTTP.start(url.host, url.port) { |http| http.request(req) }
		mods = resp.body if resp.code == "200"

		return mods
	end

	def add_item_link(item, handle, log)
		item['external_documents'].push(JSONModel(:external_document).new({
			:title => I18n.t("plugins.digital_object_manager.defaults.link_title"),
			:location => "#{I18n.t("plugins.digital_object_manager.defaults.prefix")}#{handle}",
			:publish => true
		}))
		log << "Added Fedora handle #{handle} to #{item['uri']}. "
		return item, log
	end

	def update_item_link(item, handle, log)
		item['external_documents'].each do |doc|
			if doc['title'] == I18n.t("plugins.digital_object_manager.defaults.link_title")
				unless doc['location'].end_with?(handle)
					doc['location'].gsub!(/codu:\d+/, handle)
					log << "Updated #{item['uri']} with Fedora handle #{handle}. "
				end
			end
		end
		return item, log
	end

	def add_digital_object(item, handle, log)
		object = JSONModel(:digital_object).new({
			'title' => item['title'],
			'digital_object_id' => "#{I18n.t("plugins.digital_object_manager.defaults.prefix")}#{handle}",
			'publish' => true
		}).to_json
		resp = JSONModel::HTTP.post_json(URI("#{JSONModel::HTTP.backend_url}/repositories/#{session[:repo_id]}/digital_objects"), object)
		if resp.code == "200"
			uri = ASUtils.json_parse(resp.body)['uri']
			item['instances'].push(JSONModel(:instance).new({
				:instance_type => "digital_object",
				:digital_object => {
					:ref => uri
				}
			}))
			log << "Created #{uri} with Fedora handle #{handle}. Linked #{uri} to #{item['uri']}."
		end
		return item, log
	end

	def update_digital_object(instance, handle, log)
		object = JSONModel::HTTP.get_json("#{instance['digital_object']['ref']}")
		url = "#{I18n.t("plugins.digital_object_manager.defaults.prefix")}#{handle}"
		unless object['digital_object_id'] = url
			object['digital_object_id'] = "#{url}"
			JSONModel::HTTP.post_json(URI("#{JSONModel::HTTP.backend_url}#{instance['digital_object']['ref']}"), object.to_json)
			log << "Added Fedora handle #{handle} to #{object['uri']}."
		end
		return log
	end
end
