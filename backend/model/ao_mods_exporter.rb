class MODSSerializer < ASpaceExport::Serializer
  serializer_for :ao_mods

  include JSONModel

  def serialize(mods, opts = {})

    builder = Nokogiri::XML::Builder.new(:encoding => "UTF-8") do |xml|
      serialize_mods(mods, xml)
    end

    builder.to_xml
  end

  def serialize_mods(mods, xml)

    root_args = {'version' => '3.4'}
    root_args['xmlns'] = 'http://www.loc.gov/mods/v3'

    xml.mods(root_args){
      serialize_mods_inner(mods, xml)
    }
  end


  def serialize_mods_inner(mods, xml)

    xml.titleInfo {
      xml.title mods.title
    }

    xml.identifier(:type => 'local') {
      xml.text mods.local_identifier
    }

    xml.language {
      xml.languageTerm(:type => 'code') {
        xml.text mods.language_term
      }
    }

    unless mods.extents.empty?
      xml.physicalDescription {
        mods.extents.each do |extent|
          xml.extent extent
        end
      }
    end

    mods.notes.each do |note|
      if note.wrapping_tag
        xml.send(note.wrapping_tag) {
          serialize_note(note, xml)
        }
      else
        serialize_note(note, xml)
      end
    end

    if (repo_note = mods.repository_note)
      xml.note(:displayLabel => repo_note.label) {
        xml.text repo_note.content
      }
    end

    mods.subjects.each do |subject|
      xml.subject(:authority => subject['source']) {
        subject['terms'].each do |term|
          xml.topic term
        end
      }
    end

    mods.names.each do |name|

      case name['role']
      when 'subject'
        xml.subject {
          serialize_name(name, xml)
        }
      else
        serialize_name(name, xml)
      end
    end

    mods.parts.each do |part|
      xml.part(:ID => part['id']) {
        xml.detail {
          xml.title part['title']
        }
      }
    end

  end


  # wrapped the namePart in an 'unless' so it wouldn't export empty tags
  def serialize_name(name, xml)
    atts = {:type => name['type']}
    atts[:authority] = name['source'] if name['source']
    xml.name(atts) {
      name['parts'].each do |part|
        unless part['content'].nil?
          if part['type']
            xml.namePart(:type => part['type']) {
              xml.text part['content']
            }
          else
            xml.namePart part['content']
          end
        end
      end
      xml.role {
        xml.roleTerm(:type => 'text', :authority => 'marcrelator') {
          xml.text name['role']
        }
      }
    }
  end


  def serialize_note(note, xml)
    atts = {}
    atts[:type] = note.type if note.type
    atts[:displayLabel] = note.label if note.label

    xml.send(note.tag, atts) {
      xml.text note.content
    }
  end
end
