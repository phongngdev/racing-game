# Racing audio asset credits

Runtime files are shipped under `assets/audio/racing/`. Original sources are
used with their stated licenses; renamed runtime files are listed below.
Kenney's source license texts are preserved in `assets/audio/licenses/`.

## CC0 sources

- **Kenney — Impact Sounds 1.0**, CC0 1.0: [asset page](https://kenney.nl/assets/impact-sounds). Its OGG clips supply wall and car impact variants, dirt thuds, grass/grit bursts, and edge debris. Selected clips include `impactMetal_light_000`, `impactMetal_heavy_000/001`, `impactPlate_medium_000/001`, `impactWood_heavy_000`, `impactWood_medium_000`, and `footstep_grass_000/002/004`.
- **Kenney — Interface Sounds 1.0**, CC0 1.0: [asset page](https://kenney.nl/assets/interface-sounds). `tick_001/002`, `select_006`, and `confirmation_001/002` supply countdown, GO, checkpoint, and finish cues.
- **Kenney Vleugels — Music Jingles**, CC0 1.0: [asset page](https://kenney.nl/assets/music-jingles). `jingles_NES04`, `jingles_NES10`, and `jingles_HIT02` supply victory, draw, and DNF cues.
- **Ziph — Some sounds**, CC0: [OpenGameArt page](https://opengameart.org/content/some-sounds-0). `motorseamless01.wav`, `motorseamless08.wav`, and `motorseamless13.wav` are the idle, mid, and high engine layers. The creator describes the synthesized car motor as intended for pitch bending and crossfading.
- **Yaroslav_Novikov — Car 1**, CC0: [OpenGameArt page](https://opengameart.org/content/car-1-1). The moving-car recording was trimmed into the repeating `surface/road_roll.wav` road bed; a 125 ms overlap crossfade was applied at its loop point.

## Attribution-required source

- **audible-edge (Tom Haigh), submitted by qubodup — Car tire squeal skid loop**, CC BY 3.0: [OpenGameArt page](https://opengameart.org/content/car-tire-squeal-skid-loop). `surface/tire_skid.wav` is the supplied loop used for tire squeal. Credit: “Car tire squeal skid loop” by Tom Haigh (audible-edge), submitted by qubodup, CC BY 3.0. No edits were made to this file.

## Runtime mapping

- `engine/engine_{idle,mid,high}.wav` — Ziph's three motor loop recordings.
- `surface/road_roll.wav` — processed CC0 moving-car recording; looped under both cars, scaled with speed.
- `surface/tire_skid.wav` — CC BY tire-squeal loop; looped while braking or steering hard at speed.
- `surface/grit_*.ogg`, `surface/edge_debris.ogg` — Kenney grass/grit and wood debris clips, randomized or triggered near track edges.
- `collision/*.ogg` — Kenney metal, plate, wood, and ground impacts, selected and layered by collision type and intensity.
- `race/*.ogg` — Kenney countdown, GO, checkpoint, and finish feedback.
- `result/*.ogg` — Kenney victory, draw, and DNF jingles.

Kenney released each cited pack under CC0 1.0; attribution is included here as a courtesy. The audio directory itself is not registered as a Flutter asset; these documents and source notices are not bundled in the runtime.
