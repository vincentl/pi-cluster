# Figures

Files referenced by `Readme.md`. Vincent captures these; sessions only draw figure 1.

| File | What to capture | Readme section |
|------|-----------------|----------------|
| `01-overview.svg` | Diagram, not a photo: workstation, home router, head node (wifi in, `eth0` 10.0.0.1 out), switch, compute nodes 10.0.1.N. Show what is shared: `/image/pi5` ro, `/home` rw, `/opt` ro. Draw as SVG or Mermaid. | Top |
| `02-assembled.jpg` | The whole cluster, cabled and powered. | Assembly |
| `03-head-node.jpg` | Head node close-up: NVMe HAT and SSD, microSD slot, Ethernet. | Assembly |
| `04-imager-general.png` | Imager customisation: hostname, username, wifi, locale filled in. | 1. Flash |
| `05-imager-ssh.png` | Imager services tab: SSH enabled, public-key only, key pasted. | 1. Flash |
| `06-imager-bootloader.png` | Imager: Misc Utility Images → Bootloader → Network Boot selected. Only if the EEPROM step stays in the guide (decision D6). | 4. Add nodes |

Optional, as text blocks rather than images once the output is real: `10-nvme.sh`'s overwrite
prompt, `30-add-node.sh` reporting the MAC and serial, and the section 5 check output.

Crop screenshots to the dialog. Photos at 1600 px wide or less. Keep the numbering; add new
figures at the end.
