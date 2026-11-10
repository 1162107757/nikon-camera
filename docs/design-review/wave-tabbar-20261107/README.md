# Huevia Wave Tabbar review prototype

User requested a prototype inspired by [Moli_xEs / Wave tabbar](https://dribbble.com/shots/15187764-wave-tabbar) and supplied four reference frames. This is a local component proposal awaiting user review. It does not modify Android, build an APK, change photo-processing interfaces, or publish a website.

- Review board: http://127.0.0.1:8794/
- Single-screen interaction: http://127.0.0.1:8794/app.html
- Board image: review/desktop.jpg
- Four selected states: review/tabbar-states.jpg

Run from the project directory with: node docs/design-review/wave-tabbar-20261107/serve.mjs. The server binds only127.0.0.1. Click any of the four navigation entries, or use the board's replay button. Source controls are illustrative; other actions explain that this is only a navigation prototype. No account/camera/photo data is read or changed.

The reference's white floating silhouette, pastel solid icons and grey-to-colour wave fill are adapted to 预设 / 同步 / 相册 / 设置. Names remain visible; the current icon and name share one pale selected capsule. All icons retain colour at rest, matching the supplied final frame. An individual selection uses one440ms fill and220ms capsule movement; CSS/JS respect reduced motion. All function icons are authored SVG geometry, not a copied reference raster.

Review captures use a1264×1038 board, CSS390×844 phones (JPEG390×843 due capture rounding), and320×720 narrow mode. Browser checks cover four root/title states, no horizontal overflow,64px nav/56px item/4px inset geometry, rapid selection, keyboard focus, a real in-flight CSS matrix and the replay sequence. Reduced-motion source paths were inspected but not OS-emulated. This does not establish native performance or physical-device acceptance.

A single design detector run was degraded to regex because its HTML parser modules were unavailable. Its32 notices concern intentional scope-specific fonts, colours and radii versus the global native DESIGN record; it did not compute contrast or selector layout. Manual contrast roles are recorded in review/contrast.json. Six reused photo assets plus eight screenshots carry embedded provenance (14 checked,0missing); source URLs/hashes are in ASSETS.json. Reference frames are internal study only and are not rendered by the prototype.

Fresh finish review and local design documentation are recorded in review/ and DESIGN.md; prototype readiness does not imply user approval or permission to implement.
