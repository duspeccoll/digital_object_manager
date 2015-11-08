class DigitalObjectManagerController < ApplicationController

	set_access_control "view_repository" => [:index, :search, :select],
	                   "update_digital_object_record" => [:create, :merge]

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
		object = item_converter(JSONModel::HTTP::get_json(params[:item]))

    response = JSONModel::HTTP.post_json(URI("#{JSONModel::HTTP.backend_url}/repositories/#{session[:repo_id]}/digital_objects"), object)
		if response.code === "200"
			object_id = ASUtils.json_parse(response.body)['id']
			object_uri = ASUtils.json_parse(response.body)['uri']
			flash[:success] = I18n.t("plugins.digital_object_manager.messages.object_create", :title => "#{JSONModel::HTTP.get_json(object_uri)["title"]}").html_safe

      item = item_updater(JSONModel::HTTP::get_json(params[:item]), object_uri)

			item_response = JSONModel::HTTP.post_json(URI("#{JSONModel::HTTP.backend_url}#{item["uri"]}"), item.to_json)
			if item_response.code === "200"
				flash[:success] << I18n.t("plugins.digital_object_manager.messages.item_update", :title => "#{item["title"]}").html_safe
			else
				flash[:error] = I18n.t("plugins.digital_object_manager.messages.item_error", :uri => "#{item["uri"]}").html_safe
			end

			redirect_to :controller => :digital_objects, :action => :show, :id => object_id
		else
			flash[:error] = "#{I18n.t("plugins.digital_object_manager.messages.error")} #{ASUtils.json_parse(response.body)["error"].to_s}".html_safe
			redirect_to request.referer
		end

	end

	def merge
		# Merges item metadata into the digital object, overwriting what it finds.
		# Depending on how this tests we may need a separate method for the opposite action.
		new_object = item_merger(JSONModel::HTTP::get_json(params[:item]), JSONModel::HTTP::get_json(params[:object]))

		response = JSONModel::HTTP.post_json(URI("#{JSONModel::HTTP.backend_url}#{params[:object]}"), new_object.to_json)
	  if response.code === "200"
			object_id = ASUtils.json_parse(response.body)['id']
			object_uri = ASUtils.json_parse(response.body)['uri']
			flash[:success] = I18n.t("plugins.digital_object_manager.messages.object_update", :title => "#{JSONModel::HTTP.get_json(object_uri)["title"]}").html_safe
			redirect_to :controller => :digital_objects, :action => :show, :id => object_id
		else
			object_error = ASUtils.json_parse(response_body)['error'].to_s
			flash[:error] = I18n.t("plugins.digital_object_manager.messages.object_error", :error => "#{object_error}").html_safe
			redirect_to request.referer
		end

	end

	private

	def item_converter(item)
		# date handler:
		# copies existing dates without system fields, adds the current date as digitization date
		dates = Array.new(item['dates'])
		unless dates.empty?
			dates.each do |date|
				if date['label'] == "creation"
					date['label'] = "event"
				end
			end
		end
		dates.push(JSONModel(:date).new({
			:label => "creation",
			:date_type => "single",
			:expression => "undated"
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
		# converts Archival Object-typed notes to Digital Object types
		notes = note_handler(item)

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

	def item_updater(item, object_uri)
		item['instances'].push(JSONModel(:instance).new({
			:instance_type => "digital_object",
			:digital_object => { :ref => object_uri }
			}))

		if item['dates'].empty?
			item['dates'].push(JSONModel(:date).new({
				:label => "creation",
				:date_type => "single",
				:expression => "undated"
				}))
		end
		item
	end

  # method to merge item record metadata into an existing digital object
	# (assumes that the item record's metadata is primary)
	def item_merger(item, object)
		# make sure the object is published
		object['publish'] = true

		# it brings the language over from the item record, if not found in the object
		if defined? item['language']
			if object['language'] !=  item['language']
				object['language'] = item['language']
			end
		end

    # it merges item dates into the object if no dates are present in the object, or if the dates don't match
		# it also adds a digitization date if none is present
		if object['dates'].empty? || object['dates'] != item['dates']
			object['dates'] = item['dates']
		end

		# it copies the item's extents into the digital object
		if object['extents'].empty? || object['extents'] != item['extents']
			object['extents'] = item['extents']
		end

		# it copies the item's subject headings into the digital object
		if object['subjects'].empty? || object['subjects'] != item['subjects']
			object['subjects'] = item['subjects']
		end

    # it copies the item's linked agents into the digital object, if the digital object has none
		# otherwise it does nothing (this needs refinement)
		if object['linked_agents'].empty?
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
			object['linked_agents'] = linked_agents
		end

		# runs the note handler if there are no notes present in the digital object
		if object['notes'].empty?
			notes = note_handler(item)
			object['notes'] = notes
		end

		object
	end

	def note_handler(item)
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

			if note['type'] == "userestrict"
				notes.push(JSONModel(:note_digital_object).new({
					:type => note['type'],
					:content => content,
					:label => note['label'],
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
	  notes
	end
end
