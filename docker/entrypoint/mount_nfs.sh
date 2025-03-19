#!/bin/bash

set -e

# Mount the NFS share for storing models
mount -t nfs4 10.69.1.251:/volume1/exllamav2 /mnt/exllamav2