class DigitizedObjectController < ApplicationController

	set_access_control "view_repository" => [:index, :search, :select],
	                   "update_digital_object_record" => [:create, :replace]

	def index
		@page = 1
	end

	def search
		@search_data = Search.all(session[:repo_id], params_for_backend_search)
	end

	def select
    @item = JSONModel::HTTP::get_json(params[:uri])
		@objects = Array.new

		@item['instances'].each do |instance|
			if instance["instance_type"] == "digital_object"
				@objects.push(instance["digital_object"]["ref"])
			end
		end
	end

	def create
		item = JSONModel::HTTP::get_json(params[:item])
		item_uri = item['uri']
		item_title = item['title']

		object = item_converter(item)

    response = JSONModel::HTTP.post_json(URI("#{JSONModel::HTTP.backend_url}/repositories/#{session[:repo_id]}/digital_objects"), object)
		if response.code === "200"
			id = ASUtils.json_parse(response.body)['id']
			uri = ASUtils.json_parse(response.body)['uri']
			digital_object_title = JSONModel::HTTP.get_json(uri)['title']
			flash.now[:success] = "Digital object <strong>#{digital_object_title}</strong> created".html_safe

			item['instances'].push(JSONModel(:instance).new({
				:instance_type => "digital_object",
				:digital_object => { :ref => uri }
				}))

			item = item.to_json

			item_response = JSONModel::HTTP.post_json(URI("#{JSONModel::HTTP.backend_url}#{item_uri}"), item)
			if item_response.code === "200"
				flash.now[:success] << "<br />Archival object <strong>#{item_title}</strong> updated".html_safe
			else
				flash.now[:error] = "Could not add digital object ref: <strong>#{item_uri}</strong>".html_safe
			end

			redirect_to :controller => :digital_objects, :action => :show, :id => id
		else
			flash.now[:error] = "#{I18n.t("plugins.digitized_object.messages.error")} #{ASUtils.json_parse(response.body)["error"].to_s}".html_safe
			redirect_to request.referer
		end

	end

	def replace
		item = JSONModel::HTTP::get_json(params[:item])
		object = JSONModel::HTTP::get_json(params[:object])
	end

	private

	def item_converter(item)
		time = Time.new()

		# date handler:
		# copies existing dates without system fields, adds the current date as digitization date
		dates = Array.new(item['dates'])
		dates.push(JSONModel(:date).new({
			:label => "digitized",
			:date_type => "single",
			:expression => time.strftime("%Y %B").to_s + " " + time.day.to_s,
			:begin => time.strftime("%Y-%m-%d")
			}))

		# linked agent handler:
		# copies existing agents, flips creator to source, adds Special Collections and Archives as creator
		linked_agents = Array.new(item['linked_agents'])
		linked_agents.each do |linked_agent|
			if linked_agent['role'] == "creator"
				linked_agent['role'] = "source"
			end
		end
		linked_agents.push({
			:role => "creator",
			:ref => "\/agents\/corporate_entities\/987"
			})

		# notes handler:
		# I don't know about this one yet, it's complicated
		notes = Array.new()
		item['notes'].each do |note|
			if note['jsonmodel_type'] == "note_multipart"
				content = Array.new()
				note['subnotes'].each do |subnote|
					content.push(subnote['content'])
				end
			elsif note['jsonmodel_type'] == "note_singlepart"
				content = note['content']
			end

			if note['type'] == "abstract"
				notes.push(JSONModel(:note_digital_object).new({
					:type => "summary",
					:content => content,
					:publish => note['publish']
					}))
			end
			if note['type'] == "odd"
				if note.has_key?('label')
				  if note['label'] == "Inscription and Marks"
				    notes.push(JSONModel(:note_digital_object).new({
					    :type => "inscription",
					    :content => content,
					    :publish => note['publish']
					    }))
				  end
			  else
			    notes.push(JSONModel(:note_digital_object).new({
						:type => "note",
						:content => content,
						:publish => note['publish']
						}))
				end
			end
			if note['type'] == "custodhist"
				notes.push(JSONModel(:note_digital_object).new({
					:type => note['type'],
					:content => content,
					:publish => note['publish']
					}))
			end
		end

		object = JSONModel(:digital_object).new({
			:title => item['title'],
			:digital_object_id => item['component_id'],
			:publish => true,
			:language => (item['language'] if defined? item['language']),
			:dates => dates,
			:extents => item['extents'],
			:subjects => item['subjects'],
			:linked_agents => linked_agents,
			:notes => notes
		}.reject{ |k,v| v.nil? }).to_json

		object
	end

end
