'''
stage-1 uses configuration values from `pi-cluster.toml` to
  - check ssh key exists
  - process templated scripts, applying configuration values to produce setup scripts and instruction messages
    - microSD phase
      - activate PCIe
      - image NVMe
        - wifi settings
        - user
        - ssh key
    - prepare head node
      - install packages
      - configure 
    activate PCIe
    - 
'''
import argparse
import os
import pathlib
import re
import sys
import tomllib

from utils import expand, value


parser = argparse.ArgumentParser(description='Pi-Cluster Stage 1 - Use cluster.toml configuration to produce setup scripts')
parser.add_argument('toml', type=str, help='Path to cluster configuration toml file', metavar='config.toml')
parser.add_argument('scripts', type=str, help='destination directory')
option = parser.parse_args()

with open(option.toml, 'rb') as io:
    config = tomllib.load(io)

# SSH
key_name = value(config, 'ssh.key-name')
private_key_path = pathlib.PosixPath(f'~/.ssh/{key_name}').expanduser()
public_key_path = pathlib.PosixPath(f'~/.ssh/{key_name}.pub').expanduser()

config['@'] = {'option': {'scripts': option.scripts}}
config['@']['ssh'] = {}
config['@']['ssh']['config'] = str(pathlib.PosixPath(f'~/.ssh/config'))
config['@']['ssh']['private-key'] = str(private_key_path)
config['@']['ssh']['public-key'] = str(public_key_path)

if not private_key_path.exists() or not public_key_path.exists():
    print(expand('msgs', 'ssh-key-missing.txt', config))
    sys.exit(1)

for index, name in enumerate([
    'ssh-config.txt',
    'rpi-imager.txt',
    'compute-node-mac.txt',
    'head-node-nvme-setup.txt',
    'network-boot.txt',
    ]):
    print(f'Step {index+1}')
    print(expand('msgs', name, config))

os.makedirs(option.scripts, exist_ok=True)
for name in ['nvme-setup.sh']:
    dst = pathlib.PosixPath(option.scripts).joinpath(name)
    with open(dst, 'w') as io:
        io.write(expand('scripts', name, config))
    