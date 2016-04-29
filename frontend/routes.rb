ArchivesSpace::Application.routes.draw do

  match('/plugins/digital_object_manager' => 'digital_object_manager#index', :via => [:get])
  match('/plugins/digital_object_manager/update' => 'digital_object_manager#update', :via => [:post])
  match('/plugins/digital_object_manager/download' => 'digital_object_manager#download', :via => [:post])
  match('/plugins/ao_mods/:id/download' => 'ao_mods#download', :via => [:get])

end
