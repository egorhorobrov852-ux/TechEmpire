# Native procedural city art

The city geometry is generated in `scripts/world/city.gd` from native Godot box and cylinder meshes. It has no downloaded model dependencies or textures. Colors and sizes are separate from the economic model.

Static architecture, pavements, roads, windows, trees and scenery use MultiMesh batches grouped by material. Only six decorative cars and the selected-plot outline animate every frame. Businesses are rebuilt when the supplied game state changes, not every frame.

The 16 playable parcels are surrounded by a visible fence. Buildings and ground have separate picking colliders, so a vacant parcel does not have an invisible tower-sized hit area. The skyline and park outside the fence are decorative and cannot be purchased.

Camera: left drag / one finger to pan, right drag to rotate, wheel to zoom, two-finger pinch and rotation. A tap selects a parcel. Programmatic `focus_plot()` does not emit the user-selection signal.

Performance on Android hardware remains to be measured. Native rendering was visually checked with Godot 4.6.3 Compatibility on Mesa llvmpipe; this is a desktop software-rendering check, not an Android FPS measurement.
