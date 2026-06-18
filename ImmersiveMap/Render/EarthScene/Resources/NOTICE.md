# Night Lights Dataset Notice

Built-in night-lights texture:

- Source: NASA Black Marble 2016 Grayscale Maps
- File used: `BlackMarble_2016_3km_gray.jpg`
- Source page: https://science.nasa.gov/earth/earth-observatory/earth-at-night/maps/
- Direct asset URL: https://eoimages.gsfc.nasa.gov/images/imagerecords/144000/144897/BlackMarble_2016_3km_gray.jpg
- Data acquired: 2016
- Published: May 16, 2019

Built-in high-resolution night-lights tiles:

- Source: NASA Black Marble 2016 Grayscale Maps
- Files used: 2016 grayscale 500m tiled JPEGs `A1`...`D2`
- Generated runtime assets: `NightLightsTiles/night_lights_<z>_<x>_<y>.jpg`
- Metadata: `NightLightsTiles/night_lights_tiles_metadata.json`
- Tile range: z4...z6 at 1024 px, JPEG quality 90
- Filename convention: flat unique names are used because SwiftPM processed resources flatten nested directories.
- Size tradeoff: the bundled tile set is approximately 125 MB so package consumers have deterministic offline assets without build-time downloads.

Attribution:

NASA Earth Observatory images by Joshua Stevens, using Suomi NPP VIIRS data from Miguel Román, NASA GSFC.
