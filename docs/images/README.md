# Figures

Photos and screenshots used by `Readme.md`. The two diagrams, the cluster overview and how a
compute node boots, are Mermaid code in the Readme itself, which GitHub draws in light and dark
themes; they have no file here.

| File | What it shows | Readme section | Source |
|------|---------------|----------------|--------|
| `01-cluster.jpg` | The cluster on its PoE switch: four compute nodes, numbered 1-4 on their Ethernet ports, and the head node with its SSD on the right, each on a red cable to the switch | Top | Vincent, IMG_0050, 2026-09-26, edited in a Claude chat on 2026-09-27: blue wall and power cables behind the switch removed, levelled by under 1°, cropped to 1270 × 903; then a thread on the desk at the bottom right filled in from the desk around it |
| `02-parts-head-node.jpg` | Head node parts and the switch | Parts | IMG_6845 (02-06: 960 × 1280 exports, 2026-09-23) |
| `03-parts-compute-node.jpg` | One compute node's parts: Pi 5, Waveshare PoE HAT (F), heatsink, thermal pads, standoffs | Parts | IMG_6862, turned 90° counter-clockwise (`-rotate -90`) |
| `04-pcie-ribbon.jpg` | The X1012's ribbon cable in the Pi 5's PCIe connector, cooler fitted | Assembly | IMG_6855 |
| `05-head-node.jpg` | The finished head node: X1012 with its SSD above the cooler | Assembly | IMG_6857 |
| `06-compute-node.jpg` | A compute node with its PoE HAT, cabled to the switch | Assembly | IMG_6864 |
| `07-imager-remote-access.png` | Imager's Remote access screen: SSH enabled, public key authentication, one key configured | 1. Flash | Vincent, Imager v2.0.11.1 on macOS, 2026-09-23 |

Photos: export the originals, then convert each one so it is at most 1600 px on its long side,
with its metadata (camera, date, any location) removed:

```bash
magick IMG_6864.jpeg -auto-orient -strip -resize '1600x1600>' -quality 82 06-compute-node.jpg
```

Screenshots: PNG of the Imager window (Cmd-Shift-4, then Space, then click the window on macOS),
converted to sRGB with the metadata removed, and the black frame outside the window trimmed so
the rounded corners are transparent. Keep the numbering; add new figures at the end.
