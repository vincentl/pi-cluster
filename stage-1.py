'''
stage-1 uses configuration values from `pi-cluster.toml` to
  - check ssh key exists
  - process templated setup files, applying configuration values to produce setup scripts and instruction messages
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

from utils import expand, value, template


parser = argparse.ArgumentParser(description='Pi-Cluster Stage 1 - Use cluster.toml configuration to produce setup scripts')
parser.add_argument('toml', type=str, help='Path to cluster configuration toml file', metavar='config.toml')
parser.add_argument('setup', type=str, help='destination directory for setup files')
option = parser.parse_args()

with open(option.toml, 'rb') as io:
    config = tomllib.load(io)

# SSH
key_name = value(config, 'ssh.key-name')
private_key_path = pathlib.PosixPath(f'~/.ssh/{key_name}').expanduser()
public_key_path = pathlib.PosixPath(f'~/.ssh/{key_name}.pub').expanduser()

config['@'] = {'option': {'setup': option.setup}}
config['@']['head-node'] = config['cluster']['node-prefix'] + config['cluster']['head-node-suffix']
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

    'head-node-nvme-setup.txt',
    'network-boot.txt',
    ]):
    print(f'Step {index+1}')
    print(expand('msgs', name, config))

# Scripts
os.makedirs(option.setup, exist_ok=True)
for name in ['nvme-setup.sh', 'network-boot.sh', 'add-node.sh']:
    dst = pathlib.PosixPath(option.setup).joinpath(name)
    fd = os.open(path=dst, flags=(os.O_WRONLY | os.O_CREAT | os.O_TRUNC), mode=0o750)
    with open(fd, 'w') as io:
        io.write(expand('setup', name, config))

# Basic configuration files
os.makedirs(option.setup, exist_ok=True)
for name in ['isc-dhcp-server']:
    dst = pathlib.PosixPath(option.setup).joinpath(name)
    fd = os.open(path=dst, flags=(os.O_WRONLY | os.O_CREAT | os.O_TRUNC), mode=0o644)
    with open(fd, 'w') as io:
        io.write(expand('setup', name, config))

# Configuration files with variable length
dst = pathlib.PosixPath(option.setup).joinpath('hosts')
fd = os.open(path=dst, flags=(os.O_WRONLY | os.O_CREAT | os.O_TRUNC), mode=0o644)
with open(fd, 'w') as io:
    io.write(expand('setup', 'hosts', config))
    io.write(template('10.0.0.1     {{@.head-node}}\n', config))
    for node in range(1, config['cluster']['node-count'] + 1):
        io.write(template(f'10.0.1.{node}     ' + '{{cluster.cluster.node-prefix}}' + f'{node:03d}\n', config))

dst = pathlib.PosixPath(option.setup).joinpath('dhcpd.conf')
fd = os.open(path=dst, flags=(os.O_WRONLY | os.O_CREAT | os.O_TRUNC), mode=0o644)
with open(fd, 'w') as io:
    io.write(expand('setup', 'dhcpd.conf', config))

dst = pathlib.PosixPath(option.setup).joinpath('dhcpd.conf')
fd = os.open(path=dst, flags=(os.O_WRONLY | os.O_CREAT | os.O_TRUNC), mode=0o644)
with open(fd, 'w') as io:
    io.write(expand('setup', 'dhcpd.conf', config))
