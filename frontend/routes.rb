ArchivesSpace::Application.routes.draw do

  match('/plugins/digitized_object' => 'digitized_object#index', :via => [:get])
  match('/plugins/digitized_object/search' => 'digitized_object#search', :via => [:get])
  match('/plugins/digitized_object/select' => 'digitized_object#select', :via => [:get])
  match('/plugins/digitized_object/create' => 'digitized_object#create', :via => [:get])
  match('/plugins/digitized_object/merge' => 'digitized_object#merge', :via => [:get])

end
