This repository contains a draft to mechanically edit OpenStreetMap for the [AdopteUneCommune](https://wiki.openstreetmap.org/wiki/FR:Organised_Editing/Activities/AdopteUneCommune) challenge.

It is a prototype that acts as a proxy between maproulette.org and JOSM editor. Goal is to prepare a changeset and let human validate it.


# Run it:

- make sure JOSM remote control listens on port 8112 (instead of 8111)
- run `JOSM_CONTROL_PORT=8112 PORT=8111 ruby adopte-une-commune-assistant.rb`

# Description

https://forum.openstreetmap.fr/t/discussion-assistant-au-challenge-lieu-de-cultes-non-nommes-en-france/19397
