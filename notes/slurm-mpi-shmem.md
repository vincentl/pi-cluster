# Slurm, MPI and OpenSHMEM working notes

Raw notes moved out of the old Readme on 2026-09-22. Not yet scripted; `head/40-slurm.sh` is the planned home.
Commands were run by hand on the head node (`/image/pi5` is the compute image). Not a procedure.

```bash
# Do we want to have a separate /opt partition?

# munge & slurm + update users/groups on network image
apt install libmunge-dev libmunge2 munge
dd if=/dev/random bs=1 count=1024 > /etc/munge/munge.key
chown munge:munge /etc/munge/munge.key
chmod 400 /etc/munge/munge.key
systemctl restart munge
apt install -y slurm-wlm slurm-wlm-doc slurm-client libpmix-bin libpmix-dev libpmix2
apt install -y libucx-dev libucx0 ucx-utils

cp -p /etc/passwd /etc/shadow /etc/group /etc/gshadow /image/pi5/etc/
cp -p /etc/munge/munge.key /image/pi5/etc/munge/

# configure slurm
mkdir /opt/slurm
touch /opt/slurm/slurm.conf
echo "include /opt/slurm/slurm.conf" > /etc/slurm/slurm.conf
echo "include /opt/slurm/slurm.conf" > /image/pi5/etc/slurm/slurm.conf
echo "include /opt/slurm/cgroup.conf" > /etc/slurm/cgroup.conf
echo "include /opt/slurm/cgroup.conf" > /image/pi5/etc/slurm/cgroup.conf

cat >/opt/slurm/cgroup.conf<< EOF
ConstrainCores=yes
ConstrainDevices=yes
ConstrainRAMSpace=yes
ConstrainSwapSpace=yes
EOF

# slurm configurator

chmod a+r /etc/slurm/slurm.conf
mkdir /var/spool/slurmctld
chown -R slurm:slurm /var/spool/slurmctld
systemctl enable slurmctld
systemctl restart slurmctld
systemctl restart slurmd


# scripts

sed -i 's/#MpiDefault=/MpiDefault=pmi2/' /opt/slurm/slurm.conf
sed -i 's|#Epilog=|Epilog=/opt/slurm/scripts/epilog.sh|' /opt/slurm/slurm.conf
sed -i 's|#Prolog=|Prolog=/opt/slurm/scripts/prolog.sh|' /opt/slurm/slurm.conf
sed -i 's|#TaskProlog=|TaskProlog=/opt/slurm/scripts/taskprolog.sh|' /opt/slurm/slurm.conf

cat >/opt/slurm/scripts/epilog.sh<< 'EOF'
#! /bin/bash

# remove the temporary directory
export SLURM_TMPDIR=/tmp/${SLURM_JOB_USER}-${SLURM_JOBID}
if [ -d "$SLURM_TMPDIR" ] ; then
    rm -rf "$SLURM_TMPDIR"
fi

exit 0
EOF

cat >/opt/slurm/scripts/prolog.sh<< 'EOF'
#! /bin/bash

# prepare the temporary directory.
export SLURM_TMPDIR=/tmp/${SLURM_JOB_USER}-${SLURM_JOBID}
mkdir $SLURM_TMPDIR
chown ${SLURM_JOB_USER}:users $SLURM_TMPDIR
chmod 700 $SLURM_TMPDIR

exit 0
EOF

cat >/opt/slurm/scripts/taskprolog.sh<< 'EOF'
#! /bin/bash

echo export SLURM_TMPDIR=/tmp/${SLURM_JOB_USER}-${SLURM_JOBID}

exit 0
EOF

chmod a+rx /opt/slurm/scripts/*.sh
chown -R slurm:slurm /opt/slurm
scontrol reconfigure


# compute node image

- Need to create /root/setup-script.sh and chmod it, then
systemd-nspawn --boot --directory=/image/pi5 --bind=/srv/tftp:/boot --bind=/image/pi5/var:/var --bind=/opt:/opt --exec /root/setup-script.sh


update-initramfs -u
apt install -y libmunge-dev libmunge2 munge
echo "d /var/log/munge 0700 munge munge -" >> /etc/tmpfiles.d/vardirs.conf
echo "d /var/lib/munge 0700 munge munge -" >> /etc/tmpfiles.d/vardirs.conf
chown munge:munge /etc/munge/munge.key
chmod 400 /etc/munge/munge.key
apt install -y slurmd slurm-client libpmix-bin libpmix-dev libpmix2
apt install -y libpmi2-0 libpmi2-0-dev
apt install -y libucx-dev libucx0 ucx-utils

systemctl enable slurmd
systemctl restart slurmd



scontrol update NodeName=b02 State=RESUME


# mpi
apt install mpich

# shmem

apt update
apt install -y git build-essential autoconf automake libtool libnuma-dev
apt install -y libev4
apt install libev-dev

git clone https://github.com/portals4/portals4.git
cd portals4
./autogen.sh
./configure --prefix=/opt/local --disable-transport-ib --enable-zero-mrsfatal
make -j
make install

```
