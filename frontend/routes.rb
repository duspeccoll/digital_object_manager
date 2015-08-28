ArchivesSpace::Application.routes.draw do

  match('/plugins/digital_object_manager' => 'digital_object_manager#index', :via => [:get])
  match('/plugins/digital_object_manager/search' => 'digital_object_manager#search', :via => [:get])
  match('/plugins/digital_object_manager/select' => 'digital_object_manager#select', :via => [:get])
  match('/plugins/digital_object_manager/create' => 'digital_object_manager#create', :via => [:get])
  match('/plugins/digital_object_manager/merge' => 'digital_object_manager#merge', :via => [:get])

end
