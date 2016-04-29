class DigitalObjectManagerController < ApplicationController

	require 'zip'
	require 'net/http'

	set_access_control "view_repository" => [:index, :download],
                     "update_digital_object_record" => [:update]

	def index
	end

	def download
		datafile = params[:datafile].read

		respond_to do |format|
			format.html do
				output = Zip::OutputStream.write_buffer do |zos|
					datafile.each_line do |item|
						item.chomp!
						search_data = Search.all(session[:repo_id], { 'q' => item })
						if search_data.results?
							search_data['results'].each do |result|
								obj = JSON.parse(result['json'])
								if obj['component_id'] = item
									id = obj['uri'].gsub(/\/repositories\/#{session[:repo_id]}\/archival_objects\//, '')
									url = URI("#{JSONModel::HTTP.backend_url}/repositories/#{session[:repo_id]}/archival_objects/mods/#{id}.xml")
									req = Net::HTTP::Get.new(url.request_uri)
									req['X-ArchivesSpace-Session'] = Thread.current[:backend_session]
									resp = Net::HTTP.start(url.host, url.port) { |http| http.request(req) }
									mods = resp.body if resp.code == "200"
									unless mods.nil?
										zos.put_next_entry "#{obj['component_id'].gsub(/\./, '_')}.xml"
										zos.print mods
									end
								end
							end
						end
					end
				end
				output.rewind
				send_data output.read, filename: "mods_download_#{Time.now.strftime("%Y%m%d_%H%M%S")}.zip"
			end
		end
	end

	def update
		datafile = params[:datafile].read

		@actions = Array.new
		datafile.each_line do |line|
			row = Array.new(line.split(","))
			search_data = Search.all(session[:repo_id], { 'q' => row[0] })
			if search_data.results?
				search_data['results'].each do |result|
					item = JSON.parse(result['json'])
					if item['component_id'] = row[0]
						object = JSONModel::HTTP.get_json(item['uri'])

						# add or update external document links
						if object['external_documents'].length > 0
							if object['external_documents'].map{ |doc| doc['title'] }.include? I18n.t("plugins.digital_object_manager.defaults.link_title")
								object['external_documents'].each do |document|
									if document['title'] == I18n.t("plugins.digital_object_manager.defaults.link_title")
										document['location'].gsub!(/codu:\d+/, row[1])
										@actions.push({
											'action' => "update_link",
											'title' => item['title'],
											'uri' => item['uri']
										})
									end
								end
							else
								object['external_documents'].push(JSONModel(:external_document).new({
									:title => I18n.t("plugins.digital_object_manager.defaults.link_title"),
									:location => "#{I18n.t("plugins.digital_object_manager.defaults.prefix")}#{row[1]}",
									:publish => true
								}))
								@actions.push({
									'action' => "add_new_link",
									'title' => item['title'],
									'uri' => item['uri']
								})
							end
						else
							object['external_documents'].push(JSONModel(:external_document).new({
								:title => I18n.t("plugins.digital_object_manager.defaults.link_title"),
								:location => "#{I18n.t("plugins.digital_object_manager.defaults.prefix")}#{row[1]}",
								:publish => true
							}))
							@actions.push({
								'action' => "add_new_link",
								'title' => item['title'],
								'url' => item['uri']
							})
						end

						JSONModel::HTTP.post_json(URI("#{JSONModel::HTTP.backend_url}#{item['uri']}"), object.to_json)

						# add or update links in digital objects
						if object['instances'].length > 0
							if object['instances'].map { |i| i['instance_type'] }.include? "digital_object"
								object['instances'].each do |instance|
									if instance['instance_type'] == "digital_object"
										digital_object = JSONModel::HTTP.get_json("#{instance['digital_object']['ref']}")
										digital_object['digital_object_id'] = "#{I18n.t("plugins.digital_object_manager.defaults.prefix")}#{row[1]}"
										JSONModel::HTTP.post_json(URI("#{JSONModel::HTTP.backend_url}#{instance['digital_object']['ref']}"), digital_object.to_json)
										@actions.push({
											'action' => "update_dao",
											'title' => digital_object['title'],
											'uri' => digital_object['uri']
										})
									end
								end
							else
								digital_object = JSONModel(:digital_object).new({
									'title' => item['title'],
									'digital_object_id' => "#{I18n.t("plugins.digital_object_manager.defaults.prefix")}#{row[1]}",
									'publish' => true
								}).to_json
								response = JSONModel::HTTP.post_json(URI("#{JSONModel::HTTP.backend_url}/repositories/#{session[:repo_id]}/digital_objects"), digital_object)
								if response.code == "200"
									@actions.push({
										'action' => "create_dao",
										'title' => digital_object['title'],
										'uri' => ASUtils.json_parse(response.body)['uri']
									})
								end
							end
						else
							digital_object = JSONModel(:digital_object).new({
								'title' => item['title'],
								'digital_object_id' => "#{I18n.t("plugins.digital_object_manager.defaults.prefix")}#{row[1]}",
								'publish' => true
							}).to_json
							response = JSONModel::HTTP.post_json(URI("#{JSONModel::HTTP.backend_url}/repositories/#{session[:repo_id]}/digital_objects"), digital_object)
							if response.code == "200"
								@actions.push({
									'action' => "create_dao",
									'title' => digital_object['title'],
									'uri' => ASUtils.json_parse(response.body)['uri']
								})
							end
						end
					end
				end
			end
		end
	end

end
