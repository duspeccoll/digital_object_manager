# Digital Object Manager 2.0

This plugin allows for the download of MODS representations of Archival Objects in a batch, as provided by the user in a CSV or tab-delimited text file. The MODS records are packaged in a ZIP archive for download.

The plugin also allows a user to update links to digital objects in a batch using CSV files as input. It checks the first column of the CSV input for an Archival Object component ID, searches for it, and then does two things:

* checks for an External Object link to [Special Collections @ DU](https://specialcollections.du.edu); it adds a link if none exists, and updates the PID in the link if it does
* checks if a Digital Object is attached to the Archival Object; it creates one with the Islandora handle as Digital Object ID if none exists, and updates the Digital Object ID if it does

The handle updater expects as input an Archival Object component ID and a PID for an Islandora digital object (in our case 'codu:\d+'). You can specify a handle prefix, as well as an External Document title for updating the link to the repository in an item record, in the 'defaults' section of locales/en.yml.

Pull requests always welcomed.

# Digital Object Manager 1.0 (of historical interest)

Digital Object Manager formerly allowed a user to create a Digital Object based on the metadata from a related Item record. It was written in response to a problem we had at Denver where archivists were manually transcribing item-level metadata during the course of digitization activities. It turned out not to scale very well, and in the meantime we figured out how to export MODS representations of Archival Object records, so I bagged most of it and replaced it with what's here now.

Questions? E-mail kevin.clair@du.edu.
