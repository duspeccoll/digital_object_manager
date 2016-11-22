class ArchivesSpaceService < Sinatra::Base

  Endpoint.get('/repositories/:repo_id/archival_objects/mods/:id.xml')
    .description("Get a MODS representation of an Archival Object")
    .params(["id", :id],
            ["repo_id", :repo_id])
    .permissions([:view_repository])
    .returns([200, "(:archival_object)"]) \
  do
    obj = resolve_references(ArchivalObject.to_jsonmodel(params[:id]), ['repository::agent_representation', 'linked_agents', 'subjects', 'digital_object'])
    mods = ASpaceExport.model(:ao_mods).from_archival_object(JSONModel(:archival_object).new(obj))

    xml_response(ASpaceExport::serialize(mods))
  end

  Endpoint.get('/repositories/:repo_id/archival_objects/mods/:id.:fmt/metadata')
    .description("Get metadata for an Archival Object MODS export")
    .params(["id", :id],
            ["repo_id", :repo_id])
    .permissions([:view_repository])
    .returns([200, "The export metadata"]) \
  do
    json_response({"filename" => "#{ArchivalObject[params[:id]].component_id}_mods.xml".gsub(/\s+/, '_'), "mimetype" => "application/xml"})
  end

end
