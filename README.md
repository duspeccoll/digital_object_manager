# digitized_object

This plugin allows a user to create a Digital Object based on the metadata from a related Item record. It solves a problem we had at Denver where archivists were manually transcribing item-level metadata during the course of digitization activities, and (for us) removes the need to have native MODS export for archival object records.

It works by searching archival objects for the item you wish to digitize. It checks to see if digital objects are already attached to the item. The user can then either replace an existing Digital Object's metadata with the metadata in the item record, or attach a new Digital Object.

Things to do:
* Write the 'replace' action (it behaves slightly differently than the 'create' action)
* Clean up the CSS some
* Make sure the plugin title and other locales are consistent across all of the code

Questions? E-mail kevin.clair@du.edu.
