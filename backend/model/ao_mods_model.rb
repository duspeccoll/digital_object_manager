class AOMODSModel < ASpaceExport::ExportModel
  model_for :ao_mods

  include JSONModel

  attr_accessor :title
  attr_accessor :language_term
  attr_accessor :extents
  attr_accessor :notes
  attr_accessor :subjects
  attr_accessor :names
  attr_accessor :type_of_resource
  attr_accessor :repository_note

  # begin plugin
  attr_accessor :local_identifier
  attr_accessor :digital_origin
  # end plugin

  @archival_object_map = {
    :language => :language_term=,
    :extents => :handle_extent,
    :subjects => :handle_subjects,
    :linked_agents => :handle_agents,
    :notes => :handle_notes,
    # begin plugin
    :component_id => :local_identifier=,
    :instances => :handle_instances
    # end plugin
  }

  @name_type_map = {
    'agent_person' => 'personal',
    'agent_family' => 'family',
    'agent_corporate_entity' => 'corporate',
    'agent_software' => nil
  }

  @name_part_type_map = {
    'primary_name' => 'family',
    'title' => 'termsOfAddress',
    'rest_of_name' => 'given',
    'family_name' => 'family',
    'prefix' => 'termsOfAddress'
  }

  # begin plugin
  @digital_origin_map = {
    'born_digital' => "born digital",
    'digitized_micro' => "digitized microfilm",
    'digitized_other' => "digitized other analog",
    'reformatted' => "reformatted digital"
  }
  # end plugin

  def initialize
    @extents = []
    @notes = []
    @subjects = []
    @names = []
    @parts = []
    # begin plugin
    @digital_origin = ""
    # end plugin
  end

  # meaning, 'archival object' in the abstract
  def self.from_archival_object(obj)

    mods = self.new

    # taking a stab at including date expression in titleInfo/title
    mods.title = build_title(obj)

    mods.apply_map(obj, @archival_object_map)

    mods
  end

  def self.name_type_map
    @name_type_map
  end

  def self.name_part_type_map
    @name_part_type_map
  end

  # begin plugin
  def self.digital_origin_map
    @digital_origin_map
  end
  # end plugin

  @@mods_note = Struct.new(:tag, :type, :label, :content, :wrapping_tag)
  def self.new_mods_note(*a)
    @@mods_note.new(*a)
  end

  def self.build_title(obj)
    mods_title = obj.title

    obj.dates.each do |date|
      if date['label'] == "creation"
        mods_title << ", #{date['expression']}"
      end
    end

    mods_title
  end

  def new_mods_note(*a)
    self.class.new_mods_note(*a)
  end


  def handle_notes(notes)
    notes.each do |note|
      content = ASpaceExport::Utils.extract_note_text(note)
      mods_note = case note['type']
                  when 'accessrestrict'
                    new_mods_note('accessCondition',
                                   'restrictionOnAccess',
                                   note['label'],
                                   content)
                  when 'userestrict'
                    new_mods_note('accessCondition',
                                  'useAndReproduction',
                                  note['label'],
                                  content)
                  when 'legalstatus'
                    new_mods_note('accessCondition',
                                  note['type'],
                                  note['label'],
                                  content)
                  when 'physdesc'
                    new_mods_note('note',
                                  nil,
                                  note['label'],
                                  content,
                                  'physicalDescription')
                  when 'abstract'
                    new_mods_note('abstract',
                                  nil,
                                  note['label'],
                                  content)
                  else
                    new_mods_note('note',
                                  note['type'],
                                  note['label'],
                                  content)
                  end
     self.notes << mods_note
    end
  end


  def handle_extent(extents)
    extents.each do |ext|
      e = ext['number']
      e << " (#{ext['portion']})" if ext['portion']
      e << " #{ext['extent_type']}"

      self.extents << e
    end
  end


  def handle_subjects(subjects)
    subjects.map {|s| s['_resolved'] }.each do |subject|
      self.subjects << {
        'terms' => subject['terms'].map {|t| t['term']},
        'source' => subject['source']
      }
    end
  end

  # begin plugin
  def handle_instances(instances)
    instances.map { |i| i['digital_object']['_resolved'] }.each do |object|
      if object['user_defined']
        unless object['user_defined']['enum_2'].nil?
          self.digital_origin = self.class.digital_origin_map[object['user_defined']['enum_2']] if digital_origin.empty?
        end
      end
    end
  end
  # end plugin

  def handle_agents(linked_agents)
    linked_agents.each do |link|
      agent = link['_resolved']
      role = link['role']
      name_type = self.class.name_type_map[agent['jsonmodel_type']]
      # shift in granularity - role repeats for each name
      agent['names'].each do |name|
        self.names << {
          'type' => name_type,
          'role' => role,
          'source' => name['source'],
          'parts' => name_parts(name, agent['jsonmodel_type']),
          'displayForm' => name['sort_name']
        }
      end
    end
  end

  def name_parts(name, type)
    fields = case type
             when 'agent_person'
               ["primary_name", "title", "prefix", "rest_of_name", "suffix", "fuller_form", "number"]
             when 'agent_family'
               ["family_name", "prefix"]
             when 'agent_software'
               ["software_name", "version", "manufacturer"]
             when 'agent_corporate_entity'
               ["primary_name", "subordinate_name_1", "subordinate_name_2", "number"]
             end
    parts = []
    fields.each do |field|
      part = {}
      part['type'] = self.class.name_part_type_map[field]
      part.delete('type') if part['type'].nil?
      part['content'] = name[field] unless name[field].nil?
      parts << part unless part.empty?
    end
    parts
  end

end
